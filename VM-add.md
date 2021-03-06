# Setting up EXPRESSCLUSTER to controll VMs

### Deploying VM

Deploy the VM to be protected on the ESXi running "EC VM having active failover-vm".
Note that the VM need to be deployed on the EC_iSCSI datastore.

### Configuring EC

On the client PC,

- Open Cluster WebUI ( http://172.31.255.11:29003/ )
- Change to [Config Mode] from [Operation Mode]

#### Adding the EXEC resource for controlling the VM

This resource is controlling start/stop VM

- [Add resource] at the right side of [failover-vm]
- Select [EXEC resource] as [Type] > set `exec-[VMNAME]` as [Name] e.g. `exec-VM1`> [Next]
- **Uncheck** [Follow the default dependency] > select `exec-target` > [Add] > [Next]

- [Next]
- Select start.sh > [Replace] > Select [*vm-start.pl*] > [Open] > [Yes] > [Edit]

	- overwrite `%%VMX%%`       by the path to VM configuration file such as `/vmfs/volumes/EC_iSCSI/vm1/vm1.vmx`
	- overwrite `%%VMHBA1%%`    by the name of Software iSCSI HBA on ESXi#1 such as `vmhba64`
	- overwrite `%%VMHBA2%%`    by the name of Software iSCSI HBA on ESXi#2 such as `vmhba64`
	- overwrite `%%DATASTORE%%` by the name of the iSCSI datastore `EC_iSCSI`
	- overwrite `%%VMK1%%`      by the IP address of ESXi#1 such as `172.31.255.2`
	- overwrite `%%VMK2%%`      by the IP address of ESXi#2 such as `172.31.255.3`
	- overwrite `%%EC1%%`       by the IP address of ec1 such as `172.31.255.11` which have the same network address with `%%VMK1%%` and `%%VMK2%%`
	- overwrite `%%EC2%%`       by the IP address of ec2 such as `172.31.255.12` which have the same network address with `%%VMK1%%` and `%%VMK2%%`
	- [OK]

- Select stop.sh > [Replace] > Select [*vm-stop.pl*] > [Open] > [Yes] > [Edit] just same as start.sh > [OK]
- [Tuning] > [Maintenance] tab > input `/opt/nec/clusterpro/log/exec-[VMNAME].log` as [Log Output Path] > check [Rotate Log] > [OK]
- [Finish]

#### Adding the Custom Monitor resource for VM to be monitored

- [Add monitor resource] at the right side of [Monitors]
- Select [Custom monitor] as [Type] > input `genw-[VMNAME]` as [Name] > [Next]
- Input `1` as [Retry Count] > select [Active] as [Monitor Timing] > [Browse] > select `exec-[VMNAME]` > [OK] > [Next]
- [Replace] > select [genw-vm.pl] > [Open] > [Yes] > [Edit] > edit the parameter in the script

	- overwrite `%%VMX%%`       by the path to VM configuration file such as `/vmfs/volumes/EC_iSCSI/vm1/vm1.vmx`
	- overwrite `%%VMK1%%`      by the IP address of ESXi#1 such as `172.31.255.2`
	- overwrite `%%VMK2%%`      by the IP address of ESXi#2 such as `172.31.255.3`
	- overwrite `%%EC1%%`       by the IP address of ec1 such as `172.31.255.11` which have the same network address with `%%VMK1%%` and `%%VMK2%%`
	- overwrite `%%EC2%%`       by the IP address of ec2 such as `172.31.255.12` which have the same network address with `%%VMK1%%` and `%%VMK2%%`
	- [OK]

- Input `/opt/nec/clusterpro/log/genw-[VMNAME].log` as [Log Output Path] > check [Rotate Log] > [Next]
- Select [Executing failover to the recovery target] as [Recovery Action] > [Browse] >  select [failover-vm] > [OK] > [Finish]

- [Apply the Configuration File] > [OK] > [OK]

# Testing

Move
- Move *failover-vm* from ec1 to ec2
- Move *failover-vm* from ec2 to ec1


Power
- Power off ESXi#1 > Wait for completion of the failover
- Power on ESXi#1 > Wait for completion of the mirror-recovery
- Power off ESXi#2 > Wait for completion of the failover
- Power on ESXi#2 > Wait for completion of the mirror-recovery
- Power off ESXi#1 and 2 > Power on ESXi#1 and 2 > Wait for completion of starting the target VM

NP

- case 1

	1. Disconnect all network from ESXi#1  
	ec2 detects HBTO and starts FOG, and getting into dual active.

		In this situation,
		- **ESXi#1** uses iSCSI Target provided from **ec1** and has running target VM.
		- **ESXi#2** uses iSCSI Target provided from **ec2** and has running target VM.

	2. Connect all network of ESXi#1  
	 On dual active detection, ec2 suicides without stopping the target VM on ESXi#2  >  ESXi#2 lost iSCSI Target on ec2 and get to use iSCSI Target on ec1 > The target VM on ESXi#2 loses Lock Protection for the .vmdk, and gets into *invalid* status on vSphere Host Client > genw-remote-node on ec1 starts ec2

	3. On vSphere Host Client connecting to ESXi#2, unregister the target VM to clear the invalid status. In other way, moving failover-vm to ec2 also clear the invalid VM.

- case 2

	1. Disconnect all network from ec1  
	ec2 detects HBTO and starts FOG. FIP, MD, iSCSI Target and adding the target VM into the ESXi#2 inventory complete successfully, but the target VM is failed to start because the Lock Protection forthe .vmdk by ESX#1.

		In this situation,
		- **ESXi#1** uses iSCSI Target provided from **ec2** and has running target VM and owns Lock Protection for the .vmdk.
		- **ESXi#2** uses iSCSI Target provided from **ec2** and does not have running target VM.

	2. Connect all network of ec1  
	ec2 suicides on dual active detection > ESXi#2 becomes to use iSCSI Target on **ec1** > the target VM on ESXi#2 become *Invalid*, *Normal* then *Powered off" status on vSphere Host Client due to losing Lock Protection > genw-remote-node on ec1 starts ec2 > back to initial situation

- case 3

	1. Disconnect all network from ESXi#2

	Behaviour is just same as case 1

- case4 (with Witness)

	1. Make vSwitch and port-group for NP test

	2. Change all NW of ec2 to the vSwitch for NP test  
	ec2 executes ESD (Emergency Shut Down) due to NP detection  >  ec1 (genw-remote-node) powers on ec2. ec1's genw-remote-node powers on ec2. from ec1's genw-remote-node perspective, ec2 looks online as a VM, ECX on ec2 looks offline, so it keeps trying to boot the cluster by issusing clpcl  >  Although ec2 is started by ec1, it cannot communicate with ec1 and Witness, then gives up starting ECX.

	3. Restore all NW of ec2 to original vSwitch  
	ec1's genw-remote-node launches ec2's ECX  >  mdw performs mirror recovery and returns to the initial state.

	4. Move failover-vm from ec1 to ec2  
	(*) Due to an issue in *LIO iSCSI Target*, stopping exec-iscsi on ec1 delayed, timeout then ESD >  
	ec2 executes FO (FailOver) >  ec2 (genw-remote-node) starts ec1 > ec1 returns to the cluster

		(*) The cause of the stop failure of exec-iscsi is that the execution of `systemctrl stop target.service` is not completed.
		In the process, the log that the login attempt to the iSCSI target portal fails is repeatedly recorded in `/var/log/messages` until ESD by the failure of stopping exec-iscsi.

		The specific log sample is as follows
		```
		Nov 22 01:01:29 ec1 kernel: Unable to locate Target Portal Group on iqn.1996-10.com.ecx
		Nov 22 01:01:29 ec1 kernel: iSCSI Login negotiation failed.
		```

	5. Move back failover-vm to ec1  
	The cluster back to initial state.
