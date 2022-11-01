# Setting up EXPRESSCLUSTER to controll VMs

## Deploying VM

Deploy the VM to be protected on the ESXi running "EC VM having active failover-vm".
Note that the VMs are deployed on the EC_iSCSI datastore.

## Configuring EC

Obtain the scripts (start.bat stop.bat vm-start.pl vm-stop.pl) from this [repository](https://github.com/EXPRESSCLUSTER/VMware/tree/main/src).

Open Cluster WebUI ( http://172.31.255.11:29003/ ).

Change to [Config Mode] from [Operation Mode].

### Adding the EXEC resource for controlling the VM

This resource controls to start/stop VM
- [Add resource] at the right side of [failover-vm]
- Select [script resource] as [Type] > set `script-[VMNAME]` as [Name] (e.g. `script-vm1`)> [Next]
- **Uncheck** [Follow the default dependency] > select `service-iscsi` > [Add] > [Next]
- [Next]
- Select start.bat > [Replace] > Select [`start.bat`] > [Open] > [Yes] > [Edit]

	  rem ***************************************
	  rem *              start.bat              *
	  rem ***************************************
	  
	  IF "%CLP_EVENT%" == "START" GOTO NORMAL
	  IF "%CLP_EVENT%" == "FAILOVER" GOTO FAILOVER
	  IF "%CLP_EVENT%" == "RECOVER" GOTO RECOVER
	  GOTO no_arm
	  
	  :NORMAL
	  :FAILOVER
	  perl vm-start.pl > vm1.log 2>&1
	  GOTO EXIT
	  
	  :RECOVER
	  :no_arm
	  :EXIT

- Select start.bat > [Replace] > Select [`stop.bat`] > [Open] > [Yes] > [Edit]

	  rem ***************************************
	  rem *              stop.bat               *
	  rem ***************************************

	  IF "%CLP_EVENT%" == "START" GOTO NORMAL
	  IF "%CLP_EVENT%" == "FAILOVER" GOTO FAILOVER
	  GOTO no_arm
	  
	  :NORMAL
	  :FAILOVER
	  perl vm-stop.pl >> vm1.log 2>&1
	  GOTO EXIT

	  :no_arm
	  :EXIT
	  

- [Add] > Select `vm-start.pl` > [Open] > [Yes] > [Edit]

	- overwrite `%%VMX%%`       by the path to VM configuration file such as `/vmfs/volumes/EC_iSCSI/vm1/vm1.vmx`
	- overwrite `%%VMHBA1%%`    by the name of Software iSCSI HBA on ESXi#1 such as `vmhba65`
	- overwrite `%%VMHBA2%%`    by the name of Software iSCSI HBA on ESXi#2 such as `vmhba65`
	- overwrite `%%DATASTORE%%` by the name of the iSCSI datastore `EC_iSCSI`
	- overwrite `%%VMK1%%`      by the IP address of ESXi#1 such as `172.31.255.2`
	- overwrite `%%VMK2%%`      by the IP address of ESXi#2 such as `172.31.255.3`
	- overwrite `%%EC1%%`       by the IP address of ec1 which have the same network address with %%VMK1%% and %%VMK2%% such as `172.31.255.11`
	- overwrite `%%EC2%%`       by the IP address of ec2 which have the same network address with %%VMK1%% and %%VMK2%% such as `172.31.255.12`
	- [OK]

- [Add] > Select `vm-stop.pl` > [Open] > [Yes] > [Edit] just same as `vm-start.pl` > [OK]

- [Tuning] > select `administrator` as [Exec User] > [OK]

- [Finish]


### Adding the Custom Monitor resource for VM to be monitored

- [Add monitor resource] at the right side of [Monitors]
- select [Custom monitor] as [Type] > input `genw-[VMNAME]` as [Name] > [Next]

- select [Active] as [Monitor Timing] > [Browse] > select `exec-[VMNAME]` > [OK] > [Next]
- [Replace] > select [genw-vm.pl] > [Open] > [Yes] > [Edit] > edit the parameter in the script

	- overwrite `%%VMX%%`       by the path to VM configuration file such as `/vmfs/volumes/EC_iSCSI/vm1/vm1.vmx`
	- overwrite `%%VMK1%%`      by the IP address of ESXi#1 such as `172.31.255.2`
	- overwrite `%%VMK2%%`      by the IP address of ESXi#2 such as `172.31.255.3`
	- overwrite `%%EC1%%`       by the IP address of ec1 which have the same network address with %%VMK1%% and %%VMK2%% such as `172.31.255.11`
	- overwrite `%%EC2%%`       by the IP address of ec2 which have the same network address with %%VMK1%% and %%VMK2%% such as `172.31.255.12`
	- [OK]

- Input `/opt/nec/clusterpro/log/genw-[VMNAME].log` as [Log Output Path] > check [Rotate Log] > [Next]
- select [Executing failover to the recovery target] as [Recovery Action] > [Browse] >  select [failover-vm] > [OK] > [Finish]

- [Apply the Configuration File] > [OK] > [OK]

# Testing

- Move *failover-vm* from ec1 to ec2
- Move *failover-vm* from ec2 to ec1
- Power off ESXi#1 > Wait for completion of the failover 
- Power on ESXi#1 > Wait for completion of the mirror-recoery
- Power off ESXi#2 > Wait for completion of the failover
- Power on ESXi#2 > Wait for completion of the mirror-recoery
- Power off ESXi#1 and 2 > Power on ESXi#1 and 2 > Wait for completion of starting the target VM