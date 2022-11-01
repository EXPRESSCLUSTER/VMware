# Setting up iSCSI Target Cluster on VMware

## Versions
- vSphere Hypervisor 7.0 (vSphere ESXi 7.0)
- Windows Server 2019
- EXPRESSCLUSTER X for Windows 4.3

## VM nodes configuration

|Virtual HW	|Number, Amount	|
|:--		|:---		|
| vCPU		|  4 CPU	| 
| Memory	| 16 GB 	|
| vNIC		|  3 ports	|
| vHDD		| 50 GB for OS<br>500 GB for Mirror-disk	|

|					| Primary			| Secondary		| Witness
|---					|---				|---			|
| Hostname				| ec1				| ec2			|
| root password				| passwd			| passwd		|
| IP Address for Management		| 172.31.255.11/24  		| 172.31.255.12/24	| 172.31.255.10
| IP Address for iSCSI Network		| 172.31.254.11/24		| 172.31.254.12/24	|
| IP Address for Mirroring		| 172.31.253.11/24		| 172.31.253.12/24	|
| MD - Cluster Partition		| Y:				| <-- |
| MD - Data Partition			| X:				| <-- |
| FIP for iSCSI Target			| 172.31.254.10			| <-- |
| WWN for iSCSI Target			| iqn.1996-10.com.ec		| <-- |

## Overall Setup Procedure
- Creating VMs (ec1 and ec2) on both ESXi, then installing Windows on them.
- Setting up ECX then iSCSI Target on them.
- Connecting ESXi iSCSI Initiator to iSCSI Target.

## Procedure

### Creating VMs on both ESXi

Put Windows iso file on `/vmfs/volumes/datastore1/iso/` in ESXi#1 and #2.

Login to the ESXi console shell by ssh > Run the below scripts.  

- On ESXi#1

	  #!/bin/sh -uex
	  
	  # NOTE:
	  # Specify the following parameters at least
	  # - Windows Server 2019 installation media (.iso file) at "ISO_FILE"
	  # - The disk size of the Mirror-disk which will be iSCSI Datastore at "VM_DISK_SIZE2"
	  
	  # Parameters
	  DATASTORE_PATH=/vmfs/volumes/datastore1
	  ISO_FILE=/vmfs/volumes/datastore1/iso/en-us_windows_server_2019_updated_aug_2021_x64_dvd_a6431a28.iso
	  VM_GUEST_OS="windows2019srv-64"
	  VM_NAME=ec1
	  VM_CPU_NUM=4
	  VM_MEM_SIZE=16384
	  VM_NETWORK_NAME1="VM Network"
	  VM_NETWORK_NAME2="Mirror_portgroup"
	  VM_NETWORK_NAME3="iSCSI_portgroup"
	  VM_DISK_SIZE1=50G
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
	  sed -i -e 's/lsilogic/lsisas1068/' $VM_VMX_FILE
	  cat << __EOF__ >> $VM_VMX_FILE
	  guestOS = "$VM_GUEST_OS"
	  numvcpus = "$VM_CPU_NUM"
	  memSize = "$VM_MEM_SIZE"
	  firmware = "efi"
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
	  sata0.present = "TRUE"
	  sata0:0.present = "TRUE"
	  sata0:0.startConnected = "TRUE"
	  sata0:0.deviceType = "cdrom-image"
	  sata0:0.fileName = "$ISO_FILE"
	  tools.syncTime = "TRUE"
	  __EOF__
	  
	  # (3) Extend disks
	  vmkfstools --extendvirtualdisk $VM_DISK_SIZE1 --diskformat eagerzeroedthick $VM_DISK_PATH1
	  vmkfstools --createvirtualdisk $VM_DISK_SIZE2 --diskformat eagerzeroedthick $VM_DISK_PATH2
	  
	  # (4) Reload VM information
	  vim-cmd vmsvc/reload $VM_ID

- On ESXi#2

	  #!/bin/sh -uex
	  
	  # NOTE:
	  # Specify the following parameters at least
	  # - Windows Server 2019 installation media (.iso file) at "ISO_FILE"
	  # - The disk size of the Mirror-disk which will be iSCSI Datastore at "VM_DISK_SIZE2"
	  
	  # Parameters
	  DATASTORE_PATH=/vmfs/volumes/datastore1
	  ISO_FILE=/vmfs/volumes/datastore1/iso/en-us_windows_server_2019_updated_aug_2021_x64_dvd_a6431a28.iso
	  VM_GUEST_OS="windows2019srv-64"
	  VM_NAME=ec2
	  VM_CPU_NUM=4
	  VM_MEM_SIZE=16384
	  VM_NETWORK_NAME1="VM Network"
	  VM_NETWORK_NAME2="Mirror_portgroup"
	  VM_NETWORK_NAME3="iSCSI_portgroup"
	  VM_DISK_SIZE1=50G
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
	  sed -i -e 's/lsilogic/lsisas1068/' $VM_VMX_FILE
	  cat << __EOF__ >> $VM_VMX_FILE
	  guestOS = "$VM_GUEST_OS"
	  numvcpus = "$VM_CPU_NUM"
	  memSize = "$VM_MEM_SIZE"
	  firmware = "efi"
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
	  sata0.present = "TRUE"
	  sata0:0.present = "TRUE"
	  sata0:0.startConnected = "TRUE"
	  sata0:0.deviceType = "cdrom-image"
	  sata0:0.fileName = "$ISO_FILE"
	  tools.syncTime = "TRUE"
	  __EOF__
	  
	  # (3) Extend disks
	  vmkfstools --extendvirtualdisk $VM_DISK_SIZE1 --diskformat eagerzeroedthick $VM_DISK_PATH1
	  vmkfstools --createvirtualdisk $VM_DISK_SIZE2 --diskformat eagerzeroedthick $VM_DISK_PATH2
	  
	  # (4) Reload VM information
	  vim-cmd vmsvc/reload $VM_ID

### Installing and configuring OS on both EC VMs

Open vSphere Host Client > Boot both EC VMs > Open the consoles of EC VMs > Install Windows.
During the installation, what to be specified are follows. Other things will be configured after the installation.

- Installation Destination > "50 GB HDD"
- Administrator's password

After the completion of reboot at the end of the Windows installation, Login to EC VMs, then install *VMware Tools* and reboot.

On ec1 and 2, Open powershell > Issue the below commands to set hostname, IP address, and to install iSCSI Target

- On ec1

	  Install-WindowsFeature FS-iSCSITarget-Server -IncludeManagementTools
	  netsh interface ip set address "Ethernet0" 172.31.255.11 255.255.255.0
	  netsh interface ip set address "Ethernet1" 172.31.254.11 255.255.255.0
	  netsh interface ip set address "Ethernet2" 172.31.253.11 255.255.255.0
	  wmic computersystem where name="%computername%" call rename name="ec1"
	  shutdown -r now

- On ec2

	  Install-WindowsFeature FS-iSCSITarget-Server -IncludeManagementTools
	  netsh interface ip set address "Ethernet0" 172.31.255.12 255.255.255.0
	  netsh interface ip set address "Ethernet1" 172.31.254.12 255.255.255.0
	  netsh interface ip set address "Ethernet2" 172.31.253.12 255.255.255.0
	  wmic computersystem where name="%computername%" call rename name="ec2"
	  shutdown -r now

On ec1 and 2, make ssh key and put publick key on both ESXi hosts for password free access from EC VMs.  
NOTE : On copying ssh key to ESXi, answering 'yes' to the prompt and inputting root password for ESXi are required.

	ssh-keygen.exe -t rsa -f "C:\Users\Administrator\.ssh\id_rsa" -N '""'
	scp "C:\Users\Administrator\.ssh\id_rsa.pub" root@172.31.255.2:/etc/ssh/keys-root/$env:COMPUTERNAME
	scp "C:\Users\Administrator\.ssh\id_rsa.pub" root@172.31.255.3:/etc/ssh/keys-root/$env:COMPUTERNAME

On ESX#1 and 2 shell console, issue the following commands to add the ec1 and 2 keys to authorized_keys.

	cd /etc/ssh/keys-root
	cat ec1 ec2 >> authorized_keys

On ec1 and 2, confirm that the ssh login to ESXi#1 and 2 is possible without password.

	ssh root@172.31.255.2
	ssh root@172.31.255.3

Making partitions on vHDD for Clustr Partition (Y:) and Data Prtition (X:) of MD resource

Put ECX installation file and license files (name them ECX4.x-[A-Z].key) on ec1 and ec2. Install EC and its licenses, then reboot.

On ec1 and 2 > Configur firewall for EC. 

	clpfwctrl --add

### Configuring EC

- Open Cluster WebUI ( http://172.31.255.11:29003/ )
- Change to [Config Mode] from [Operation Mode]
- Configure the cluster which have no failover-group.

	- [Cluster generation wizard]
	- Input `HCI-Cluster` as [Cluster Name], [English] as Language > [Next]
	- [Add] > input `172.31.255.12` as [Server Name or IP Address] of secondary server > [OK]
	- Confirm `ec2` was added > [Next]
	- Configure Interconnect

		| Priority	| MDC	| ec1		| ec2		|
		|--		|--	|--		|--		|
		| 1		|	|172.31.255.11	| 172.31.255.12	|
		| 2		| mdc1	|172.31.253.11	| 172.31.253.12	|
		| 3		|	|172.31.254.11	| 172.31.254.12	|

	- [Next] > [Next] > [Next] > [Finish] > [Yes]

<!--
#### Enabling primary node surviving on the dual-active detection
- [Recovery] tab > [Detailed Settings] in right hand of [Disable Shutdown When Multi-Failover-Service Detected] 
- Check [ec1] > [OK]
- [OK]
-->

#### Adding the failover-group
- click [Add group] button of [Groups]
- Set [Name] as [*failover-vm*] > [Next]
- [Next]
- [Next]
- [Finish]

<!--
#### Adding the EXEC resource for MD recovery automation

This resource is enabling more automated MD recovery by supposing the node which the failover group trying to start has latest data than the other node.

- Click [Add resource] button in right side of [failover-vm]
- Select [script resource] as [Type] > set `script-md-recovery` as [Name] > [Next]
- **Uncheck** [Follow the default dependency] > [Next]
- [Next]
- Select start.sh then click [Replace] > Select [*exec-md-recovery.pl*]
- [Tuning] > [Maintenance] tab > input */opt/nec/clusterpro/log/exec-md-recovery.log* as [Log Output Path] > check [Rotate Log] > [OK]
- [Finish]
-->

#### Adding floating IP resource for iSCSI Target
- Click [Add resource] button in right side of [failover-vm]
- Select [Floating IP resource] as [Type] > set `fip-iscsi` as [Name] > [Next]
- [Next]
- [Next]
- Set `172.31.254.10` as [IP Address] > [Finish]

#### Adding the MD resource
- Click [Add resource] button in right side of [failover-vm]
- Select [Mirror disk resource] as [Type] > set `md-iscsi` as [Name] >  [Next]
<!--
- **Uncheck** [Follow the default dependency] > click [script-md-recovery] > [Add] > [Next]
-->
- [Next]
- Set
	- [none] as [File System] 
	- `X:` as [Data Partition Device Name] 
	- `Y:` as [Cluster Partition Device Name]
- [Finish]

#### Adding the service resource for controlling iSCSI Target service
- Click [Add resource] button in right side of [failover-vm]
- Select [service resource] as [Type] > set `service-iscsi` as [Name] > [Next]
- [Next]
- [Next]
- Input/select `Microsoft iSCSI Target Server` > [Finish]

<!--
- Select start.bat > [Edit]
  - Change the tail of the script as below.

		echo "Starting iSCSI Target"
		systemctl start target
		echo "Started  iSCSI Target ($?)"
		exit 0

  - [OK]
- Select stop.sh > [Edit]
  - Change the tail of the script as below.

		echo "Stopping iSCSI Target"
		systemctl stop target
		echo "Stopped  iSCSI Target ($?)"
		exit 0

  - [OK]
- [Tuning] > [Maintenance] tab > input `/opt/nec/clusterpro/log/exec-target.log` as [Log Output Path] > check [Rotate Log] > [OK]
- [Finish]

#### Adding the first custom monitor resource for automatic MD recovery
- Click [Add monitor resource] button in right side of [Monitors]
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
- Click [Add monitor resource] button in right side of [Monitors]
  - [Info] section
  	- select [Custom monitor] as [Type] > input *genw-remote-node* as [Name]> [Next]
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
		- [OK]
	- input */opt/nec/clusterpro/log/genw-remote-node.log* as [Log Output Path] > check [Rotate Log] > [Next]
  - [Recovery Action] section
  	- select [Execute only the final action] as [Recovery Action]
	- [Browse]
		- [LocalServer] > [OK]
	- select [No operation] as [Final Action] > [Finish]

#### Adding the third custom monitor resource for updating arp table
- Click [Add monitor resource] button in right side of [Monitors]
  - [Info] section
  	- select [Custom monitor] as [type] > input *genw-arpTable* as [Name] > [Next]
  - [Monitor (common)] section
  	- input *30* as [Interval]
	- select [Active] as [Monitor Timing]
	- [Browse] button
		- select [fip1] > [OK]
	- [Next]
  - [Monitor (special)] section
  	- [Replace]
		- select *genw-arpTable.sh* > [Open] > [Yes]
	- input */opt/nec/clusterpro/log/genw-arpTable.log* as [Log Output Path] > check [Rotate Log] > [Next]
  - [Recovery Action] section
  	- select [Execute only the final action] as [Recovery Action]
	- [Browse]
		- [LocalServer] > [OK]
	- select [No operation] as [Final Action] > [Finish]
-->

#### Applying the configuration
- Click [Apply the Configuration File] > [OK] > [OK] > [OK]
- Reboot ec1, ec2 and wait for the completion of starting of the cluster *failover-vm*

### Configuring iSCSI Target on **ec1 and 2**

Open powershell on ec1, and issue the following commands.
<!--
 On the execution, replace the values of VMK1 and 2 according to the IP address of ESXi#1 and 2.
-->

	Set-IscsiServerTarget ec-iscsi -TargetIqn iqn.1996-10.com.ecx -InitiatorIds IPAddress:172.31.254.2, IPAddress:172.31.254.3
	New-IscsiVirtualDisk X:\iSCSIVirtualDisks\ec.vhdx 500GB
	Add-IscsiVirtualDiskTargetMapping ec-iscsi X:\iSCSIVirtualDisks\ec.vhdx
	Set-IscsiServerTarget ec-iscsi -Enable $True

Move the failover group `failover-vm` to ec2. Open powershell on ec2, and issue the following commands to enable the same iSCSI Target as ec1.

	Set-IscsiServerTarget ec-iscsi -TargetIqn iqn.1996-10.com.ecx -InitiatorIds IPAddress:172.31.254.2, IPAddress:172.31.254.3
	Import-IscsiVirtualDisk X:\iSCSIVirtualDisks\ec.vhdx
	Add-IscsiVirtualDiskTargetMapping ec-iscsi X:\iSCSIVirtualDisks\ec.vhdx
	Set-IscsiServerTarget ec-iscsi -Enable $True

<!--

	#!/bin/sh -eu

	# Parameters
	# IP address of ESXi#1 and 2
	VMK1=172.31.255.2
	VMK2=172.31.255.3

	# IP address of EC#2
	EC2=172.31.255.12

	#
	#----
	VMHBA1=`ssh $VMK1 esxcli iscsi adapter list | grep 'iSCSI Software Adapter' | sed -r 's/\s.*iSCSI Software Adapter$//'`
	VMHBA2=`ssh $VMK2 esxcli iscsi adapter list | grep 'iSCSI Software Adapter' | sed -r 's/\s.*iSCSI Software Adapter$//'`
	IQN1=`ssh $VMK1 esxcli iscsi adapter get --adapter=$VMHBA1 | grep '   Name:' | sed -r 's/[^:]*: //'`
	IQN2=`ssh $VMK2 esxcli iscsi adapter get --adapter=$VMHBA2 | grep '   Name:' | sed -r 's/[^:]*: //'`

	if [ -z "$IQN1" ]; then
		echo [E] IQN of ESXi1 not found.; exit 1
	elif [ -z "$IQN2" ]; then
		echo [E] IQN of ESXi2 not found.; exit 1
	else
		echo [D] ESXi1 : $IQN1
		echo [D] ESXi2 : $IQN2
	fi

	# Create fileio backstore (*idisk1*) on the mirror disk resource
	targetcli /backstores/block create name=idisk1 dev=/dev/NMP1

	# Creating IQN
	targetcli /iscsi create iqn.1996-10.com.ecx

	# Assigning LUN to IQN
	targetcli /iscsi/iqn.1996-10.com.ecx/tpg1/luns create /backstores/block/idisk1

	# Allow ESXi#1 and 2 (*IQN of iSCSI Initiator*) to scan the iSCSI target

	targetcli /iscsi/iqn.1996-10.com.ecx/tpg1/acls create $IQN1
	targetcli /iscsi/iqn.1996-10.com.ecx/tpg1/acls create $IQN2
	targetcli saveconfig
	
	# Copy the saved target configuration to EC#2
	scp /etc/target/saveconfig.json $EC2:/etc/target/

-->

### Connecting ESXi iSCSI Initiator to iSCSI Target

This procedure also mount the iSCSI Target as EC_iSCSI datastore and format it with VMFS6 file system.

Login to the ESXi console shell by Putty/Teraterm > Run the below commands.

- on ESXi#1

	  #!/bin/sh -eux

	  # IP Addresss(FIP):Port for iSCSI Target
	  ADDR='172.31.254.10:3260'

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
	  #
	
	  # Finding MSFT iSCSI Disk device
	  DEVICE=`esxcli storage core device list | grep "Display Name: MSFT iSCSI Disk" | sed -r 's/^.*\((.*)\)/\1/'`
	  echo [D] [$?] DEVICE = [${DEVICE}]

	  # Calculating end of sectors
	  END_SECTOR=$(eval expr $(partedUtil getptbl /vmfs/devices/disks/${DEVICE} | tail -1 | awk '{print $1 " \\* " $2 " \\* " $3}') - 1)
	  echo [D] [$?] END_SECTOR = [${END_SECTOR}]

	  # Createing partition
	  partedUtil setptbl "/vmfs/devices/disks/${DEVICE}" "gpt" "1 2048 ${END_SECTOR} AA31E02A400F11DB9590000C2911D1B8 0"
	  echo [D] [$?] partedUtil

	  # Formatting the partition and mount it as EC_iSCSI datastore
	  vmkfstools --createfs vmfs6 -S EC_iSCSI /vmfs/devices/disks/${DEVICE}:1
	  echo [D] [$?] vmkfstools

- On ESXi#2

	  #!/bin/sh -eux

	  # IP Addresss(FIP):Port of iSCSI Target
	  ADDR='172.31.254.10:3260'

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
[[1](https://kb.vmware.com/s/article/1036609)] Using partedUtil command line disk partitioning utility on ESXi  
[[2](https://www.virten.net/2015/10/usb-devices-as-vmfs-datastore-in-vsphere-esxi-6-0/)] USB Devices as VMFS Datastore in vSphere ESXi 6.0  
[[3](https://learn.microsoft.com/en-us/previous-versions/hh826097(v=technet.10))] iSCSI Target Cmdlets in Windows PowerShell

Now the setup of HCI is completed for two ESXi boxes having a virtual shared disk made of Software-Defined Storage by ECX.

Continue to [deploying VMs to be protected](VM-add-windows.md).
