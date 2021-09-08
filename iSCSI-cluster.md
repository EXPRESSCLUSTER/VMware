# Setting up iSCSI Target Cluster on VMware

## Versions
- vSphere Hypervisor 7.0 (vSphere ESXi 7.0)
- CentOS 8.2 x86_64 (CentOS-8.2.2004-x86_64-dvd1.iso)
- EXPRESSCLUSTER X for Linux 4.3.0-1

## VM nodes configuration

|Virtual HW	|Number, Amount	|
|:--		|:---		|
| vCPU		|  4 CPU	| 
| Memory	| 16 GB 	|
| vNIC		|  3 ports	|
| vHDD		| 16 GB for OS<br>500 GB for Mirror-disk	|

|					| Primary			| Secondary		|
|---					|---				|---			|
| Hostname				| ec1				| ec2			|
| root password				| passwd			| passwd		|
| IP Address for Management		| 172.31.255.11/24  		| 172.31.255.12/24	|
| IP Address for iSCSI Network		| 172.31.254.11/24		| 172.31.254.12/24	|
| IP Address for Mirroring		| 172.31.253.11/24		| 172.31.253.12/24	|
| Heartbeat Timeout			| 50 sec			| <-- |
| MD - Cluster Partition		| /dev/sdb1			| <-- |
| MD - Data Partition			| /dev/sdb2			| <-- |
| FIP for iSCSI Target			| 172.31.254.10			| <-- |
| WWN for iSCSI Target			| iqn.1996-10.com.ec		| <-- |
| WWN for ESXi#1 iSCSI Initiator	| iqn.1998-01.com.vmware:1	| <-- |
| WWN for ESXi#2 iSCSI Initiator	| iqn.1998-01.com.vmware:2	| <-- |

## Overall Setup Procedure
- Creating VMs (ec1 and ec2) on both ESXi, then installing Linux on them.
- Setting up ECX then iSCSI Target on them.
- Connecting ESXi iSCSI Initiator to iSCSI Target.

## Procedure

### Creating VMs on both ESXi

Download CetOS iso file and put it on `/vmfs/volumes/datastore1/iso/CentOS-8.2.2004-x86_64-dvd1.iso` of ESXi#1 and #2.

Login to the ESXi console shell by Putty/Teraterm > Run the below commands.
The disk size for the Mirror-disk which will become iSCSI Datastore can be specified as `VM_DISK_SIZE2=500GB` in the commands.

- on esxi1

	  #!/bin/sh -ue

	  # Parameters
	  DATASTORE_PATH=/vmfs/volumes/datastore1
	  ISO_FILE=/vmfs/volumes/datastore1/iso/CentOS-8.2.2004-x86_64-dvd1.iso
	  VM_NAME=ec1
	  VM_CPU_NUM=4
	  VM_MEM_SIZE=16384
	  VM_NETWORK_NAME1="VM Network"
	  VM_NETWORK_NAME2="Mirror_portgroup"
	  VM_NETWORK_NAME3="iSCSI_portgroup"
	  VM_GUEST_OS=centos8-64
	  VM_CDROM_DEVICETYPE=cdrom-image  # cdrom-image / atapi-cdrom
	  VM_DISK_SIZE1=16G
	  VM_DISK_SIZE2=500G

	  VM_DISK_PATH1=$DATASTORE_PATH/$VM_NAME/${VM_NAME}.vmdk
	  VM_DISK_PATH2=$DATASTORE_PATH/$VM_NAME/${VM_NAME}_1.vmdk
	  VM_VMX_FILE=$DATASTORE_PATH/$VM_NAME/$VM_NAME.vmx

	  # (0) Clean up existing VM
	  vid=`vim-cmd vmsvc/getallvms | grep ${VM_NAME} | awk '{print $1}'`
	  if [ ${vid} ]; then
	  	vim-cmd vmsvc/unregister $vid
	  fi
	  rm -rf $DATASTORE_PATH/$VM_NAME

	  # (1) Create dummy VM
	  VM_ID=`vim-cmd vmsvc/createdummyvm $VM_NAME $DATASTORE_PATH`

	  # (2) Edit vmx file
	  sed -i -e '/^guestOS /d' $VM_VMX_FILE
	  sed -i -e 's/lsilogic/pvscsi/' $VM_VMX_FILE
	  cat << __EOF__ >> $VM_VMX_FILE
	  guestOS = "$VM_GUEST_OS"
	  numvcpus = "$VM_CPU_NUM"
	  memSize = "$VM_MEM_SIZE"
	  scsi0:1.deviceType = "scsi-hardDisk"
	  scsi0:1.fileName = "${VM_NAME}_1.vmdk"
	  scsi0:1.present = "TRUE"
	  ethernet0.virtualDev = "vmxnet3"
	  ethernet0.present = "TRUE"
	  ethernet0.networkName = "$VM_NETWORK_NAME1"
	  ethernet0.addressType = "generated"
	  ethernet0.wakeOnPcktRcv = "FALSE"
	  ethernet1.virtualDev = "vmxnet3"
	  ethernet1.present = "TRUE"
	  ethernet1.networkName = "$VM_NETWORK_NAME2"
	  ethernet1.addressType = "generated"
	  ethernet1.wakeOnPcktRcv = "FALSE"
	  ethernet2.virtualDev = "vmxnet3"
	  ethernet2.present = "TRUE"
	  ethernet2.networkName = "$VM_NETWORK_NAME3"
	  ethernet2.addressType = "generated"
	  ethernet2.wakeOnPcktRcv = "FALSE"
	  ide0:0.present = "TRUE"
	  ide0:0.deviceType = "$VM_CDROM_DEVICETYPE"
	  ide0:0.fileName = "$ISO_FILE"
	  tools.syncTime = "TRUE"
	  __EOF__

	  # (3) Extend disk1
	  vmkfstools --extendvirtualdisk $VM_DISK_SIZE1 --diskformat eagerzeroedthick $VM_DISK_PATH1

	  # (4) Create disk2
	  vmkfstools --createvirtualdisk $VM_DISK_SIZE2 --diskformat eagerzeroedthick $VM_DISK_PATH2

	  # (5) Reload VM information
	  vim-cmd vmsvc/reload $VM_ID

- on esxi2

	  #!/bin/sh -ue

	  # Parameters
	  DATASTORE_PATH=/vmfs/volumes/datastore1
	  ISO_FILE=/vmfs/volumes/datastore1/iso/CentOS-8.2.2004-x86_64-dvd1.iso
	  VM_NAME=ec2
	  VM_CPU_NUM=4
	  VM_MEM_SIZE=16384
	  VM_NETWORK_NAME1="VM Network"
	  VM_NETWORK_NAME2="Mirror_portgroup"
	  VM_NETWORK_NAME3="iSCSI_portgroup"
	  VM_GUEST_OS=centos7-64
	  VM_CDROM_DEVICETYPE=cdrom-image  # cdrom-image / atapi-cdrom
	  VM_DISK_SIZE1=16G
	  VM_DISK_SIZE2=500G

	  VM_DISK_PATH1=$DATASTORE_PATH/$VM_NAME/${VM_NAME}.vmdk
	  VM_DISK_PATH2=$DATASTORE_PATH/$VM_NAME/${VM_NAME}_1.vmdk
	  VM_VMX_FILE=$DATASTORE_PATH/$VM_NAME/$VM_NAME.vmx

	  # (0) Clean up existing VM
	  vid=`vim-cmd vmsvc/getallvms | grep ${VM_NAME} | awk '{print $1}'`
	  if [ ${vid} ]; then
	  	vim-cmd vmsvc/unregister $vid
	  fi
	  rm -rf $DATASTORE_PATH/$VM_NAME

	  # (1) Create dummy VM
	  VM_ID=`vim-cmd vmsvc/createdummyvm $VM_NAME $DATASTORE_PATH`

	  # (2) Edit vmx file
	  sed -i -e '/^guestOS /d' $VM_VMX_FILE
	  sed -i -e 's/lsilogic/pvscsi/' $VM_VMX_FILE
	  cat << __EOF__ >> $VM_VMX_FILE
	  guestOS = "$VM_GUEST_OS"
	  numvcpus = "$VM_CPU_NUM"
	  memSize = "$VM_MEM_SIZE"
	  scsi0:1.deviceType = "scsi-hardDisk"
	  scsi0:1.fileName = "${VM_NAME}_1.vmdk"
	  scsi0:1.present = "TRUE"
	  ethernet0.virtualDev = "vmxnet3"
	  ethernet0.present = "TRUE"
	  ethernet0.networkName = "$VM_NETWORK_NAME1"
	  ethernet0.addressType = "generated"
	  ethernet0.wakeOnPcktRcv = "FALSE"
	  ethernet1.virtualDev = "vmxnet3"
	  ethernet1.present = "TRUE"
	  ethernet1.networkName = "$VM_NETWORK_NAME2"
	  ethernet1.addressType = "generated"
	  ethernet1.wakeOnPcktRcv = "FALSE"
	  ethernet2.virtualDev = "vmxnet3"
	  ethernet2.present = "TRUE"
	  ethernet2.networkName = "$VM_NETWORK_NAME3"
	  ethernet2.addressType = "generated"
	  ethernet2.wakeOnPcktRcv = "FALSE"
	  ide0:0.present = "TRUE"
	  ide0:0.deviceType = "$VM_CDROM_DEVICETYPE"
	  ide0:0.fileName = "$ISO_FILE"
	  tools.syncTime = "TRUE"
	  __EOF__

	  # (3) Extend disk1
	  vmkfstools --extendvirtualdisk $VM_DISK_SIZE1 --diskformat eagerzeroedthick $VM_DISK_PATH1

	  # (4) Create disk2
	  vmkfstools --createvirtualdisk $VM_DISK_SIZE2 --diskformat eagerzeroedthick $VM_DISK_PATH2

	  # (5) Reload VM information
	  vim-cmd vmsvc/reload $VM_ID

### Installing and configuring OS on both EC VMs

Open vSphere Host Client > Boot both EC VMs > Open the consoles of EC VMs > Install CentOS. During the installation, what to be specified are follows. Other things will be configured after the installation.

- "Installation Destination" > "16 GiB sda"
- "Software Selsection" > "Minimal Install"
- Root Password

After the completion of reboot at the end of the CentOS installation, Login to EC VMs, then issue the below commands to set hostname and IP address.

- On ec1

	  hostnamectl set-hostname ec1
	  nmcli c m ens192 ipv4.method manual ipv4.addresses 172.31.255.11/24 connection.autoconnect yes
	  nmcli c m ens224 ipv4.method manual ipv4.addresses 172.31.253.11/24 connection.autoconnect yes
	  nmcli c m ens256 ipv4.method manual ipv4.addresses 172.31.254.11/24 connection.autoconnect yes

- On ec2

	  hostnamectl set-hostname ec2
	  nmcli c m ens192 ipv4.method manual ipv4.addresses 172.31.255.12/24 connection.autoconnect yes
	  nmcli c m ens224 ipv4.method manual ipv4.addresses 172.31.253.12/24 connection.autoconnect yes
	  nmcli c m ens256 ipv4.method manual ipv4.addresses 172.31.254.12/24 connection.autoconnect yes

Put ECX rpm file and license files (name them ECX4.x-[A-Z].key) on `/root` of ec1 and ec2, then issue the below commands on both ec1 and 2 for doing the followings.

- Installing required packages
- Disabling firewall, SELinux and dnf-makecache
- Making partitions on vHDD (sdb)
- Installing EC and its license

	  mkdir /media/CentOS
	  mount /dev/cdrom /media/CentOS
	  yum --disablerepo=* --enablerepo=c8-media-BaseOS,c8-media-AppStream install -y targetcli target-restore perl
	  umount /media/CentOS
	  systemctl disable firewalld.service; systemctl disable dnf-makecache.timer
	  sed -i -e 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
	  yes no | ssh-keygen -t rsa -f /root/.ssh/id_rsa -N ""
	  parted -s /dev/sdb mklabel msdos mkpart primary 0% 1025MiB mkpart primary 1025MiB 100%
	  rpm -ivh expresscls.*.rpm
	  clplcnsc -i ECX4.x-*.key
	  reboot

### Configuring EC

On the client PC,

- Open Cluster WebUI ( http://172.31.255.11:29003/ )
- Change to [Config Mode] from [Operation Mode]
- Configure the cluster which have no failover-group.

	- [Cluster generation wizard]
	- Input *HCI-Cluster* as [Cluster name], [English] as Language > [Next]
	- [Add] > input *172.31.255.12* as [Server Name or IP Address] of secondary server > [OK]
	- Confirm *ec2* was added > [Next]
	- Configure Interconnect

		| Priority	| MDC	| ec1		| ec2		|
		|--		|--	|--		|--		|
		| 1		|	|172.31.255.11	| 172.31.255.12	|
		| 2		| mdc1	|172.31.253.11	| 172.31.253.12	|
		| 3		|	|172.31.254.11	| 172.31.254.12	|

	- [Next] > [Next] > [Next] > [Finish] > [Yes]

#### Changing Heartbeat Timeout value
- Click [Properties] button of [HCI-Cluster]
- [Timeout] tab > Set [Timeout] as *50* sec

#### Enabling primary node surviving on the dual-active detection
- [Recovery] tab > [Detail Config] in right hand of [Disable Shutdown When Multi-Failover-Service Detected] 
- Check [ec1] > [OK]
- [OK]

#### Adding the failover-group
- click [Add group] button of [Groups]
- Set [Name] as [*failover-vm*] > [Next]
- [Next]
- [Next]
- [Finish]

#### Adding the EXEC resource for MD recovery automation

This resource is enabling more automated MD recovery by supposing the node which the failover group trying to start has latest data than the other node.

- Click [Add resource] button in right side of [failover-vm]
- Select [EXEC resource] as [Type] > set *exec-md-recovery* as [Name] > [Next]
- **Uncheck** [Follow the default dependency] > [Next]
- [Next]
- Select start.sh then click [Replace] > Select [*exec-md-recovery.pl*]
- [Tuning] > [Maintenance] tab > input */opt/nec/clusterpro/log/exec-md-recovery.log* as [Log Output Path] > check [Rotate Log] > [OK]
- [Finish]

#### Adding the MD resource
- Click [Add resource] button in right side of [failover-vm]
- Select [Mirror disk resource] as [Type] > set *md1* as [Name] >  [Next]
- **Uncheck** [Follow the default dependency] > click [exec-md-recovery] > [Add] > [Next]
- [Next]
- Set
	- [none] as [File System] 
	- */dev/sdb2* as [Data Partition Device Name] 
	- */dev/sdb1* as [Cluster Partition Device Name]
- [Finish]

for md2 do the same like md1 by using
  - *md2* as [Name]
  - */dev/sdc2* as [Data Partition Device Name] 
  - */dev/sdc1* as [Cluster Partition Device Name]

#### Adding the execute resource for controlling target service
- Click [Add resource] button in right side of [failover-vm]
- Select [EXEC resource] as [Type] > set *exec-target* as [Name] > [Next]
- [Next]
- [Next]
- Select start.sh then click [Edit]
  - Change the tail of the script as below.

		echo "Starting iSCSI Target"
		systemctl start target
		echo "Started  iSCSI Target ($?)"
		exit 0

- Select stop.sh then click [Edit]
  - Change the tail of the script as below.

		echo "Stopping iSCSI Target"
		systemctl stop target
		echo "Stopped  iSCSI Target ($?)"
		exit 0
- [Tuning] > [Maintenance] tab > input `/opt/nec/clusterpro/log/exec-target.log` as [Log Output Path] > check [Rotate Log] > [OK]
- [Finish]

#### Adding floating IP resource for iSCSI Target
- Click [Add resource] button in right side of [failover-vm]
- Select [Floating IP resource] as [Type] > set *fip1* as [Name] > [Next]
- [Next]
- [Next]
- Set *172.31.254.10* as [IP Address]
- Click [Finish]

#### Adding the first custom monitor resource for automatic MD recovery
- Click [Add monitor Resource] button in right side of [Monitors]
  - [Info] section
  	- select [Custom monitor] as [Type] > input *genw-md* as [Name] > [Next]
  - [Monitor (common)] section
  	- input *60* as [Wait Time to Start Monitoring]
  	- select [Active] as [Monitor Timing]
  	- [Browse] button
  		- select [md1] > [OK]
  	- [Next]
  - [Monitor (special)] section
  	- [Replace]
  		- select *genw-md.pl* > [Open] > [Yes]
  	- input */opt/nec/clusterpro/log/genw-md.log* as [Log Output Path] > check [Rotate Log]
  	- [Next]
  - [Recovery Action] section
  	- select [Execute only the final action] as [Recovery Action]
  	- [Browse]
  		- [LocalServer] > [OK]
  	- [Finish]


#### Adding the second custom monitor resource for keeping remote EC VM and EC as online.
- Click [Add monitor Resource] button in right side of [Monitors]
  - [Info] section
  	- select [Custom monitor] as [type] > input *genw-remote-node* as [Name]> [Next]
  - [Monitor (common)] section
  	- select [Always] as [Monitor Timing]
	- [Next]
  - [Monitor (special)] section
  	- [Replace]
		- select *genw-remote-node.pl* > [Open] > [Yes]
	- [Edit]
		- write `$VMNAME1 = "ec1"` as VM name in the esxi1 inventory
		- write `$VMNAME2 = "ec2"` as VM name in the esxi2 inventory
		- write `$VMIP1 = "172.31.255.11"` as IP address of ec1
		- write `$VMIP2 = "172.31.255.12"` as IP address of ec2
		- write `$VMK1 = "172.31.255.2"` as IP address of esxi1 accessing from ec1
		- write `$VMK2 = "172.31.255.3"` as IP address of esxi2 accessing from ec2
	- input */opt/nec/clusterpro/log/genw-remote-node.log* as [Log Output Path] > check [Rotate Log] > [Next]
  - [Recovery Action] section
  	- select [Execute only the final action] as [Recovery Action]
	- [Browse]
		- [LocalServer] > [OK]
	- select [No operation] as [Final Action] > [Finish]

#### Adding the third custom monitor resource for updating arp table
- Click [Add monitor Resource] button in right side of [Monitors]
  - [Info] section
  	- select [Custom monitor] as [type] > input *genw-arpTable* as[Name] > [Next]
  - [Monitor (common)] section
  	- input *30* as [Interval]
	- select [Active] as [Monitor Timing]
	- [Browse] button
		- select [fip1] > [OK]
	- [Next]
  - [Monitor (special)] section
  	- [Replace]
		- select *genw-arpTable.sh* > [Open] > [Yes]
	- input */opt/nec/clusterpro/log/genw-arpTable.log* as [Log Output Paht] > check [Rotate Log] > [Next]
  - [Recovery Action] section
  	- select [Execute only the final action] as [Recovery Action]
	- [Browse]
		- [LocalServer] > [OK]
	- select [No operation] as [Final Action] > [Finish]

#### Applying the configuration
- Click [Apply the Configuration File]
- Reboot ec1, ec2 and wait for the completion of starting of the cluster *failover-vm*


### Configuring iSCSI Target

#### Obtaining IQN for iSCSI Software Adapter on **ESXi#1 and 2**.

On the client PC, download [plink.exe](https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html)
Open cmd.exe > Issue the plink command like follows. You need to understand the IP address of the ESXi#1 and 2, and root password, in the folloing sample 172.31.255.2, 172.31.255.3 and PASSWORD

	plink root@172.31.255.2 -pw PASSWORD -no-antispoof "VMHBA=`esxcli iscsi adapter list | grep 'iSCSI Software Adapter' | sed -r 's/\s.*iSCSI Software Adapter$//'`;esxcli iscsi adapter get --adapter=$VMHBA | grep '   Name:' | sed -r 's/[^:]*: //'
	
	plink root@172.31.255.3 -pw PASSWORD -no-antispoof "VMHBA=`esxcli iscsi adapter list | grep 'iSCSI Software Adapter' | sed -r 's/\s.*iSCSI Software Adapter$//'`;esxcli iscsi adapter get --adapter=$VMHBA | grep '   Name:' | sed -r 's/[^:]*: //'

On the execution of `plink` command, you might see the following. Answer `y` in the case.

	The server's host key is not cached in the registry. You
	have no guarantee that the server is the computer you
	think it is.
	The server's ecdsa-sha2-nistp256 key fingerprint is:
	ecdsa-sha2-nistp256 256 29:c9:7e:cf:fc:af:25:0c:14:be:70:9b:b6:06:5a:e8
	If you trust this host, enter "y" to add the key to
	PuTTY's cache and carry on connecting.
	If you want to carry on connecting just once, without
	adding the key to the cache, enter "n".
	If you do not trust this host, press Return to abandon the
	connection.
	Store key in cache? (y/n)

Then you will see the **IQN of iSCSI Initiator on ESXi#1 and 2** as follows likely. In this sample `iqn.1998-01.com.vmware:localhost:1983516280:65` is IQN of ESXi#1 and `iqn.1998-01.com.vmware:esxi7u2-b1:956052037:65`is IQN of ESXi#2.

	Keyboard-interactive authentication prompts from server:
	End of keyboard-interactive prompts from server
	iqn.1998-01.com.vmware:localhost:1983516280:65

	Keyboard-interactive authentication prompts from server:
	End of keyboard-interactive prompts from server
	iqn.1998-01.com.vmware:esxi7u2-b1:956052037:65

These are used as *IQN of iSCSI Initiator* in the next section to configure iSCSI Target.

#### Configuring iSCSI Target on **ec1 and 2**

On ec1, create block backstore and configure it as backstore for the iSCSI Target.
- Login to the console of ec1

- Start (iSCSI) target configuration tool

	  # targetcli

- Unset automatic save of the configuration for safe

	  > set global auto_save_on_exit=false

- Create fileio backstore (*idisk*) which have required size on mount point of the mirror disk

	  > cd /backstores/block
	  > create name=idisk1 dev=/dev/NMP1

- Creating IQN

	  > cd /iscsi
	  > create iqn.1996-10.com.ecx

- Assigning LUN to IQN

	  > cd /iscsi/iqn.1996-10.com.ec/tpg1/luns
	  > create /backstores/block/idisk1

- Allow ESXi#1 and 2 (*IQN of iSCSI Initiator* which were obtaind in the previous section) to scan the iSCSI target

	  > cd /iscsi/iqn.1996-10.com.ecx/tpg1/acls
	  > create iqn.1998-01.com.vmware:localhost:1983516280:65
	  > create iqn.1998-01.com.vmware:esxi7u2-b1:956052037:65

- Save config and exit

	  > cd /
	  > saveconfig
	  > exit

- Copy the saved target configuration to the other node

	  # scp /etc/target/saveconfig.json 172.31.255.12:/etc/target/

### Connecting ESXi iSCSI Initiator to iSCSI Target

This procedure also mount the iSCSI Target as EC_iSCSI datastore and format it with VMFS6 file system.

Login to the ESXi console shell by Putty/Teraterm > Run the below commands.

- on ESXi#1

	  #!/bin/sh -eu

	  # IP Addresss(FIP):Port for iSCSI Target
	  ADDR='172.31.254.10:3260'

	  # Enabling iSCSI Initiator
	  esxcli iscsi software set --enabled=true
	  echo [D] [$?] esxcli iscsi software set --enabled=true

	  # Finding vmhba for iSCSI Software Adapter
	  VMHBA=`esxcli iscsi adapter list | grep 'iSCSI Software Adapter' | sed -r 's/\s.*iSCSI Software Adapter$//'`
	  echo [D] [$?] VMHBA = [${VMHBA}]

	  # Discovering iSCSI Target 
	  esxcli iscsi adapter discovery sendtarget add --address=${ADDR} --adapter=${VMHBA}
	  echo [D] [$?] esxcli iscsi adapter discovery sendtarget add --address=${ADDR} --adapter=${VMHBA}

	  # Scanning iSCSI Software Adapter
	  esxcli storage core adapter rescan --adapter=${VMHBA}
	  echo [D] [$?] esxcli storage core adapter rescan --adapter=${VMHBA}

	  #
	  # The following portion creates new datastore on ECX virtual-iSCSI-shared disk.
	  # This need to be done on either of ESXi
	  #
	
	  # Finding LIO iSCSI device
	  DEVICE=`esxcli storage core device list | grep "Display Name: LIO-ORG" | sed -r 's/^.*\((.*)\)/\1/'`
	  echo [D] [$?] DEVICE = [${DEVICE]

	  # Calculating end of sectors
	  END_SECTOR=$(eval expr $(partedUtil getptbl /vmfs/devices/disks/${DEVICE} | tail -1 | awk '{print $1 " \\* " $2 " \\* " $3}') - 1)
	  echo [D] [$?] END_SECTOR = [${END_SECTOR]

	  # Createing partition
	  partedUtil setptbl "/vmfs/devices/disks/${DEVICE}" "gpt" "1 2048 ${END_SECTOR} AA31E02A400F11DB9590000C2911D1B8 0"
	  echo [D] [$?] partedUtil

	  # Formatting the partition and mount it as EC_iSCSI datastore
	  vmkfstools --createfs vmfs6 -S EC_iSCSI /vmfs/devices/disks/${DEVICE}:1
	  echo [D] [$?] vmkfstools

- On ESXi#2

	  #!/bin/sh -eu

	  # IP Addresss(FIP):Port for iSCSI Target
	  ADDR='172.31.254.10:3260'

	  # Enabling iSCSI Initiator
	  esxcli iscsi software set --enabled=true
	  echo [D] [$?] esxcli iscsi software set --enabled=true

	  # Finding vmhba for iSCSI Software Adapter
	  VMHBA=`esxcli iscsi adapter list | grep 'iSCSI Software Adapter' | sed -r 's/\s.*iSCSI Software Adapter$//'`
	  echo [D] [$?] VMHBA = [${VMHBA}]

	  # Discovering iSCSI Target 
	  esxcli iscsi adapter discovery sendtarget add --address=${ADDR} --adapter=${VMHBA}
	  echo [D] [$?] esxcli iscsi adapter discovery sendtarget add --address=${ADDR} --adapter=${VMHBA}

	  # Scanning iSCSI Software Adapter
	  esxcli storage core adapter rescan --adapter=${VMHBA}
	  echo [D] [$?] esxcli storage core adapter rescan --adapter=${VMHBA}

Reference:
[[1](https://kb.vmware.com/s/article/1036609)]
[[2](https://www.virten.net/2015/10/usb-devices-as-vmfs-datastore-in-vsphere-esxi-6-0/)]


Now the setup of HCI is completed for two ESXi boxes having a virtual shared disk made of Software-Defined Storage by ECX.

[Continue to deploying VMs to be protected.]()
