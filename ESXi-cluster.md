 # VMware Host Clustering

Configure an HA Cluster of Hypervisor to protect VMs running on VMware with Windows iSCSI Target.

## Architecture

- ECX of data mirroring configuration provides virtual shared disk for ESXi boxes by iSCSI Target clustering.
- ECX protects VMs on ESXi, means start / stop / monitor and realizes failover of VMs across ESXi boxes.

	![Architecture](vmware-cluster-architecture.png)

## Network

- Separating network for VM / management of VM and cluster / mirroring / iSCSI.

	![Network](vmware-cluster-network.png)

## Setting up ESXi - Base

Install vSphere ESXi and configure its *Management Network* as follows.

- Login to ESXi console > [Configure Management Network] > [IPv4 Configuration] >

  |			| Primary ESXi	| Secondary ESXi	|
  |:---			|:---		|:---			|
  | IPv4 Address	| 172.31.255.2	| 172.31.255.3		|
  | Subnet Mask		| 255.255.255.0 | 255.255.255.0		|
  | Default gateway	| 0.0.0.0	| 0.0.0.0		|

Install the licenses

- Obtain the license keys for both ESXi
- On vSphere Host Client for ESXi#1 (http://172.31.255.2/) and ESXi#2 (http://172.31.255.3/).
  - [Manage] in [Navigator] pane > [Licensing] tab > [Actions] > [Assign license]
  - enter the license key > [Check license] > [Assign license]

## Setting up ESXi - Datastore

Add a new datastore and give it a common name across the ESXi boxes (*datastore1*).

- Open vSphere Host Client for both ESXi,
  - [Storage] in [Navigator] pane > [Datastores] tab > [New datastore]
    - Select [Create new VMFS datastore] > [Next] > Input `datastore1` as [name] > Select the storage device for VMs.

## Setting up ESXi - Network

Start ssh service and configure it to start on boot.

- On vSphere Host Client for both ESXi,
  - [Manage] in [Navigator] pane > [Services] tab
    - [TSM-SSH] > [Actions] > [Start]
    - [TSM-SSH] > [Actions] > [Policy] > [Start and stop with host]

Configure NTP servers

- On vSphere Host Client for both ESXi,
  - [Manage] in [Navigator] pane > [System] tab
    - [Time and date] > [Edit settings]
      - Select [Use Network Time Protocol (enable NTP client)] > Select [Start and stop with host] as [NTP service startup policy] > input IP address of NTP server for the configuring environment as [NTP servers]

Configure vSwitch, Port groups, VMkernel NIC (for iSCSI Initiator) as described in the Network picture in above.

- Using ssh, connect to ESXi#1 (172.31.255.2) and ESXi#2 (172.31.255.3) then issue the below commands for each ESXi.  
  These disable TSO (TCP Segmentation Offload), LRO (Large Receive Offload), T10 SCSI WRITE_SAME (Zeroing out large portions of a disk), ATS (Atomic Test and Set) for HB, these are for the case of low iSCSI performance. And last, suppress the warning for disabling SSH on vSphere Host Client.

	  #!/bin/sh -eux

	  # Add vSwitch
	  esxcfg-vswitch --add Mirror_vswitch
	  esxcfg-vswitch --add iSCSI_vswitch
	  esxcfg-vswitch --add user_vswitch

	  # Configure vSwitch to have vmnic
	  esxcfg-vswitch --link=vmnic1 Mirror_vswitch
	  esxcfg-vswitch --link=vmnic2 iSCSI_vswitch
	  esxcfg-vswitch --link=vmnic3 user_vswitch

	  # Configure vSwitch to have port group
	  esxcfg-vswitch --add-pg=Mirror_portgroup Mirror_vswitch
	  esxcfg-vswitch --add-pg=iSCSI_portgroup iSCSI_vswitch
	  esxcfg-vswitch --add-pg=iSCSI_Initiator iSCSI_vswitch
	  esxcfg-vswitch --add-pg=user_portgroup user_vswitch

	  # Disable TSO, LRO, T10 SCSI WRITE_SAME, ATS HB (optiona)
	  #esxcli system settings advanced set --option=/Net/UseHwTSO --int-value=0
	  #esxcli system settings advanced set --option=/Net/UseHwTSO6 --int-value=0
	  #esxcli system settings advanced set --option=/Net/TcpipDefLROEnabled --int-value=0
	  #esxcli system settings advanced set --option=/DataMover/HardwareAcceleratedInit --int-value=0
	  #esxcli system settings advanced set --option=/VMFS3/UseATSForHBOnVMFS5 --int-value=0

	  # Suppress shell warning
	  esxcli system settings advanced set --option=/UserVars/SuppressShellWarning --int-value=1

- Configure VMkernel NIC for iSCSI Initiator and enable iSCSI Software Adapter

  - for ESXi#1

	    #!/bin/sh -eux
	    esxcfg-vmknic --add --ip 172.31.254.2 --netmask 255.255.255.0 iSCSI_Initiator
	    esxcli iscsi software set --enabled=true
	    /etc/init.d/hostd restart

  - for ESXi#2

	    #!/bin/sh -eux
	    esxcfg-vmknic --add --ip 172.31.254.3 --netmask 255.255.255.0 iSCSI_Initiator
	    esxcli iscsi software set --enabled=true
	    /etc/init.d/hostd restart

Continue to [Setting up iSCSI Target Cluster on VMware](iSCSI-cluster-windows.md)