# VMware Host Clustering

Configur an HA Cluster of Hypervisor to protect VMs running on VMware.

## Architecture

- ECX of data mirroring configuration provides virtual shared disk for ECXi boxes by iSCSI Target clustering.
- ECX protects VMs on ESXi, means start / stop / monitor and realizing failover of VMs across ECXi boxes.

	![Architecture](vmware-cluster-architecture.png)

## Network

- Separating network for VM / management of VM and cluster / mirroring / iSCSI.

	![Network](vmware-cluster-network.png)

## Setting up ESXi - Base

Install vSphere ESXi then set up IP address of Management Network as following.

- Login to ESXi console > [Configure Management Network] > [IPv4 Configuration] >

  |			| Primary ESXi	| Secondary ESXi	|
  |:---			|:---		|:---			|
  | IPv4 Address	| 172.31.255.2	| 172.31.255.3		|
  | Subnet Mask		| 255.255.255.0 | 255.255.255.0		|
  | Default gateway	| 0.0.0.0	| 0.0.0.0		|

Install the licenses

- Obtain the license keys for both ESXi
- Open vSphere Host Client for ESXi#1 (http://172.31.255.2/) and ESXi#2 (http://172.31.255.3/).
  - [Manage] in [Navigator] pane > [Licensing] tab > [Actions] > [Assign license]
  - enter the license key > [Check license] > [Assign license]

## Setting up ESXi - Datastore

Add a new datastore and give it a common name across the ESXi boxes (*datastore1*).

- On vSphere Host Client for both ESXi,
  - [Storage] in [Navigator] pane > [Datastores] tab > [New datastore]
    - Select [Create new VMFS datastore] > [Next] > Input [datastore1] as [name] > Select the storege device for VMs.

## Setting up ESXi - Network

Start ssh service and configure it to start on boot.

- On vSphere Host Client for both ESXi,
  - [Manage] in [Navigator] pane > [Services] tab
    - [TSM-SSH] > [Actions] > [Start]
    - [TSM-SSH] > [Actions] > [Polilcy] > [Start and stop with host]

Configure NTP servers

- On vSphere Host Client for both ESXi,
  - [Manage] in [Navigator] pane > [System] tab
    - [Time and date] > [Edit settings]
      - Select [Use Network Time Protocol (enable NTP client)] > Select [Start and stop with host] as [NTP service startup policy] > input IP address of NTP server for the configuring environment as [NTP servers]

Configure vSwitch, Port groups, VMkernel NIC (for iSCSI Initiator) as descrived in the Network picture in above.
