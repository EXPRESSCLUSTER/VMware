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

Open vSphere Host Client > Boot both EC VMs > Open the consoles of EC VMs > Install CentOS. During the installation, what to be specified are follows. Other things are configured after the installation.

1. "Software Selsection" > "Minimal Install"
2. "Installation Destination" > "16 GiB sda"
3. Root Password

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

On ec1 and 2, put ECX rpm file and license files (name them ECX4.x-[A-Z].key) on the current directory (e.g. `/root`), then issue the below commands.

**Note** on the copying ssh key to ESXi, answering 'yes' to the prompt and inputting root password of ESXi#1 and 2 are required.

	#!/bin/sh -eux

	# Mount CentOS DVD
	mkdir /media/CentOS
	mount /dev/cdrom /media/CentOS

	# Installing required packages
	yum --disablerepo=* --enablerepo=c8-media-BaseOS,c8-media-AppStream install -y targetcli target-restore perl
	umount /media/CentOS

	# Disabling firewall, SELinux and dnf-makecache
	systemctl disable firewalld.service; systemctl disable dnf-makecache.timer
	sed -i -e 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

	# Making partitions on vHDD (sdb)
	parted -s /dev/sdb mklabel msdos mkpart primary 0% 1025MiB mkpart primary 1025MiB 100%

	# Installing EC and its license
	rpm -ivh expresscls*.rpm
	clplcnsc -i ECX4.x-*.key

	# Configuring SSH
	# Making ssh key and configuring password free access from
	# EC VMs to ESXi hosts. Note, on the copying ssh key to ESXi,
	# answering 'yes' to the prompt and inputting root password
	# of ESXi#1 and 2 are required.
	yes no | ssh-keygen -t rsa -f /root/.ssh/id_rsa -N ""
	scp ~/.ssh/id_rsa.pub 172.31.255.2:/etc/ssh/keys-root/$HOSTNAME
	scp ~/.ssh/id_rsa.pub 172.31.255.3:/etc/ssh/keys-root/$HOSTNAME

	reboot

On ESX#1 and 2 shell console, issue the following commands to add the ec1 and 2 keys to authorized_keys.

	cd /etc/ssh/keys-root
	cat ec1 ec2 >> authorized_keys

On ec1 and 2 console, confirm the ssh login from ec1 to ESXi#1 and 2 is possible without password, and confirm the same for ec2.

	ssh 172.31.255.2
	ssh 172.31.255.3

### Configuring EC

On ec1, put *exec-md-recovery.pl*, *genw-md.pl*, *genw-remote-node.pl* on the current directory (e.g. `/root`), then run the following commands.
This makes EC configuration file, copis the scripts to the apropriate directories and edits the script for genw-remote-node, applies the configurtion, then reboots ec1 and 2.

**Note** to edit IP addresses for heartbeat and FIP according to the system.

**Note** on issuing the reboot command to ec2, it is requried that answering 'yes' to the prompt and inputting root password of ec2.

	#!/bin/sh -xue
	
	# Parameters
	#-------
	# IP addresses of ESXi#1 and 2
	ESX1=172.31.255.2
	ESX2=172.31.255.3

	# IP addresses of ec1 heartbeat
	IP01=172.31.255.11
	IP11=172.31.254.11
	IP21=172.31.253.11
	
	# IP addresses of ec2 heartbeat
	IP02=172.31.255.12
	IP12=172.31.254.12
	IP22=172.31.253.12
	
	# FIP
	FIP=172.31.254.10
	#-------

	DIRS=(
	/tmp/ec/scripts/failover-vm/exec-md-recovery
	/tmp/ec/scripts/failover-vm/exec-iscsi
	/tmp/ec/scripts/monitor.s/genw-md
	/tmp/ec/scripts/monitor.s/genw-remote-node
	)

	for d in ${DIRS[@]}; do if [ ! -e ${d} ]; then mkdir -p ${d}; fi; done
	cp exec-md-recovery.pl /tmp/ec/scripts/failover-vm/exec-md-recovery/start.sh
	cp genw-md.pl          /tmp/ec/scripts/monitor.s/genw-md/genw.sh
	f=/tmp/ec/scripts/monitor.s/genw-remote-node/genw.sh
	cp genw-remote-node.pl $f
	sed -i -e 's/%%VMADN1%%/ec1/'   $f
	sed -i -e 's/%%VMADN2%%/ec2/'   $f
	sed -i -e 's/%%VMA1%%/${IP01}/' $f
	sed -i -e 's/%%VMA2%%/${IP02}/' $f
	sed -i -e 's/%%VMK1%%/${ESX1}/' $f
	sed -i -e 's/%%VMK2%%/${ESX2}/' $f

	pushd /tmp/ec
	
	clpcfset create HCI-Cluster ASCII
	clpcfset add clsparam cluster/heartbeat/timeout 50000
	clpcfset add srv ec1 0
	clpcfset add srv ec2 1
	clpcfset add device ec1 lan 0 $IP01
	clpcfset add device ec1 lan 1 $IP11
	clpcfset add device ec1 lan 2 $IP21
	clpcfset add device ec1 mdc 0 $IP21
	clpcfset add device ec2 lan 0 $IP02
	clpcfset add device ec2 lan 1 $IP12
	clpcfset add device ec2 lan 2 $IP22
	clpcfset add device ec2 mdc 0 $IP22
	clpcfset add hb lankhb 0 0
	clpcfset add hb lankhb 1 1
	clpcfset add hb lankhb 2 2
	
	clpcfset add clsparam server@ec1/survive 1
	
	clpcfset add grp failover failover-vm
	
	clpcfset add rsc failover-vm fip fip-iscsi
	clpcfset add rscparam fip fip-iscsi parameters/ip $FIP
	
	clpcfset add rsc failover-vm exec exec-md-recovery
	clpcfset add rscparam exec exec-md-recovery parameters/act/path start.sh
	clpcfset add rscparam exec exec-md-recovery parameters/deact/path stop.sh
	clpcfset add rscparam exec exec-md-recovery parameters/userlog /opt/nec/clusterpro/log/exec-md-recovery.log
	clpcfset add rscparam exec exec-md-recovery parameters/logrotate/use 1
	clpcfset add rscdep exec exec-md-recovery fip-iscsi
	
	clpcfset add rsc failover-vm md md-iscsi
	clpcfset add rscparam md md-iscsi parameters/netdev@0/priority 0
	clpcfset add rscparam md md-iscsi parameters/netdev@0/device 0
	clpcfset add rscparam md md-iscsi parameters/netdev@0/mdcname mdc1
	clpcfset add rscparam md md-iscsi parameters/nmppath /dev/NMP1
	clpcfset add rscparam md md-iscsi parameters/diskdev/dppath /dev/sdb2
	clpcfset add rscparam md md-iscsi parameters/diskdev/cppath /dev/sdb1
	clpcfset add rscparam md md-iscsi parameters/fs none
	clpcfset add rscparam md md-iscsi act/timeout 190
	clpcfset add rscparam md md-iscsi deact/timeout 190
	clpcfset add rscdep md md-iscsi exec-md-recovery
	
	clpcfset add rsc failover-vm exec exec-iscsi
	clpcfset add rscparam exec exec-iscsi parameters/act/path start.sh
	clpcfset add rscparam exec exec-iscsi parameters/deact/path stop.sh
	clpcfset add rscparam exec exec-iscsi parameters/userlog /opt/nec/clusterpro/log/exec-iscsi.log
	clpcfset add rscparam exec exec-iscsi parameters/logrotate/use 1
	clpcfset add rscdep exec exec-iscsi md-iscsi
	
	clpcfset add mon genw genw-md
	clpcfset add monparam genw genw-md parameters/path genw.sh
	clpcfset add monparam genw genw-md parameters/userlog /opt/nec/clusterpro/log/genw-md.log
	clpcfset add monparam genw genw-md parameters/logrotate/use 1
	clpcfset add monparam genw genw-md polling/timing 1
	clpcfset add monparam genw genw-md target md-iscsi
	clpcfset add monparam genw genw-md relation/type cls
	clpcfset add monparam genw genw-md relation/name LocalServer
	clpcfset add monparam genw genw-md emergency/threshold/restart 0
	clpcfset add monparam genw genw-md emergency/threshold/fo 0
	clpcfset add monparam genw genw-md firstmonwait 30
	
	clpcfset add mon genw genw-remote-node
	clpcfset add monparam genw genw-remote-node parameters/path genw.sh
	clpcfset add monparam genw genw-remote-node parameters/userlog /opt/nec/clusterpro/log/genw-remote-node.log
	clpcfset add monparam genw genw-remote-node parameters/logrotate/use 1
	clpcfset add monparam genw genw-remote-node target md-iscsi
	clpcfset add monparam genw genw-remote-node relation/type cls
	clpcfset add monparam genw genw-remote-node relation/name LocalServer
	clpcfset add monparam genw genw-remote-node emergency/threshold/restart 0
	clpcfset add monparam genw genw-remote-node emergency/threshold/fo 0
	
	clpcfset add mon genw genw-arpTable
	clpcfset add monparam genw genw-arpTable parameters/path genw.sh
	clpcfset add monparam genw genw-arpTable parameters/userlog /opt/nec/clusterpro/log/genw-arpTable.log
	clpcfset add monparam genw genw-arpTable parameters/logrotate/use 1
	clpcfset add monparam genw genw-arpTable polling/timing 1
	clpcfset add monparam genw genw-arpTable target fip-iscsi
	clpcfset add monparam genw genw-arpTable relation/type cls
	clpcfset add monparam genw genw-arpTable relation/name LocalServer
	clpcfset add monparam genw genw-arpTable emergency/threshold/restart 0
	clpcfset add monparam genw genw-arpTable emergency/threshold/fo 0
	
	clpcfset add mon fipw fipw-iscsi
	clpcfset add monparam fipw fipw-iscsi target fip-iscsi
	clpcfset add monparam fipw fipw-iscsi relation/type rsc
	clpcfset add monparam fipw fipw-iscsi relation/name fip-iscsi
	
	clpcfset add mon mdnw mdnw-iscsi
	clpcfset add monparam mdnw mdnw-iscsi parameters/object md-iscsi
	clpcfset add monparam mdnw mdnw-iscsi relation/type cls
	clpcfset add monparam mdnw mdnw-iscsi relation/name LocalServer
	
	clpcfset add mon mdw mdw-iscsi
	clpcfset add monparam mdw mdw-iscsi relation/type cls
	clpcfset add monparam mdw mdw-iscsi relation/name LocalServer
	clpcfset add monparam mdw mdw-iscsi parameters/object md-iscsi
	
	clpcfset add mon userw userw
	clpcfset add monparam userw userw relation/type cls
	clpcfset add monparam userw userw relation/name LocalServer

	clpcfctrl --push -l -x .
	popd

	read -p "Hit enter to reboot ec2 then ec1. Answer ec2 root password." 
	ssh %IP02 reboot
	reboot

Wait for the completion of starting of the cluster *failover-vm*

### Configuring iSCSI Target on **ec1 and 2**

On ec1, create block backstore on NMP1 and configure it as backstore for the iSCSI Target.

Login to the console of ec1, and issue the following commands. On the execution, replace the values of VMK1 and 2 with the IP ddress of ESXi#1 and 2.

	#!/bin/sh -eux

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

### Connecting ESXi iSCSI Initiator to iSCSI Target

This procedure mount the iSCSI Target as EC_iSCSI datastore and format it with VMFS6 file system.

Login to the ESXi console shell by Putty/Teraterm > Run the below commands.

- on ESXi#1 and 2

	  #!/bin/sh -eux

	  #
	  # Configuring iSCSI Initiator
	  #

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

- On ESXi#1

	  #!/bin/sh -eux

	  #
	  # Formatting and creating new datastore EC_iSCSI on ECX virtual-iSCSI-shared disk.
	  #
	
	  # Finding LIO iSCSI device
	  DEVICE=`esxcli storage core device list | grep "Display Name: LIO-ORG" | sed -r 's/^.*\((.*)\)/\1/'`
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

Reference:
[[1](https://kb.vmware.com/s/article/1036609)]
[[2](https://www.virten.net/2015/10/usb-devices-as-vmfs-datastore-in-vsphere-esxi-6-0/)]


Now the setup of HCI is completed for two ESXi boxes having a virtual shared disk made of Software-Defined Storage by ECX.

Continue to [deploying VMs to be protected](VM-add.md).
