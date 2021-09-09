#!/usr/bin/perl -w
#
# Script for power off the Virtual Machine
#
use strict;
#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
# The path to VM configuration file. This must be absolute UUID-based path.
# like "/vmfs/volumes/<datastore-uuid>/vm1/vm1.vmx";
my $cfg_path = '%%VMX%%';
# The HBA name to connect to iSCSI Datastore.
my $vmhba1 = "%%VMHBA1%%";
my $vmhba2 = "%%VMHBA2%%";

# The Datastore name which the VM is stored.
my $datastore = "%%DATASTORE%%";

# IP addresses of VMkernel port.
my $vmk1 = "%%VMK1%%";
my $vmk2 = "%%VMK2%%";

# IP addresses of EC VMs
my $ec1 = "%%EC1%%";
my $ec2 = "%%EC2%%";
#-------------------------------------------------------------------------------
# The interval to check the vm status. (second)
my $interval = 6;
# The miximum count to check the vm status.
my $max_cnt = 50;
#-------------------------------------------------------------------------------
# Global values
my $vmname = $cfg_path;
$vmname =~ s/.*\/(.*)\/.*\.vmx/$1/;
my $vmid = "";
my $vmhba = "";
my $vmk = "";
my $vmx = $cfg_path;
$vmx =~ s/^.*?([^\/]*\/[^\/]*$)/$1/;
my @lines = ();

my $tmp = `ip address | grep $ec1/`;
if ($? == 0) {
	$vmk = $vmk1;
	$vmhba = $vmhba1;
} else {
	$tmp = `ip address | grep $ec2/`;
	if ($? == 0) {
		$vmk = $vmk2;
		$vmhba = $vmhba2;
	} else {
		&Log("[E] Invalid configuration (Mananegment host IP could not be found).\n");
		exit 1;
	}
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
&Log("[I] [$vmname][$vmx]\n");

if (&IsUnRegistered) {
	exit 0;
}

if (! &IsPoweredOff) {
	&PowerOff;
	&WaitPowerOff;
}
exit &UnRegisterVm();

#-------------------------------------------------------------------------------
# Functions
#-------------------------------------------------------------------------------
sub IsUnRegistered {
	$vmid = "";
	&execution("ssh $vmk vim-cmd vmsvc/getallvms");
	my @tmp = @lines;
	foreach (@tmp) {
		if (/^(\d+).*\s$vmname\s/) {
			$vmid = $1;
			&Log("[I][IsUnRegistered] [$vmname][$vmid] in inventory.\n");
		}
		elsif (/^Skipping invalid VM \'(\d+)\'$/) {
			&Log("[D][IsUnRegistered] unregistering invalid VM($1)\n");
			&execution("ssh $vmk vim-cmd vmsvc/unregister $1");
		}
	}
	if ($vmid eq "") {
		&Log("[I][IsUnRegistered] [$vmname] not in inventory\n");
		return 1;
	}
	return 0;
}
#-------------------------------------------------------------------------------
# power.getstate returns "Powered off" if the VM is invalid VM.
# 
sub IsPoweredOff{
	&execution("ssh $vmk vim-cmd vmsvc/power.getstate $vmid");
	foreach (@lines) {
		if (/Powered off/) {
			&Log("[D][IsPoweredOff] [$vmname] power state is OFF.\n");
			return 1;
		}
	}
	return 0;
}
#-------------------------------------------------------------------------------
sub PowerOff{
	my $ret;
	if (&PowerOffOpMode("shutdown")) {
		if (&PowerOffOpMode("off")) {
			return 1;
		}
	}
	return 0;
}
#-------------------------------------------------------------------------------
sub PowerOffOpMode{
	my $ret = -1;
	my $powerop_mode = shift;
	return 1 if ($powerop_mode !~ /^off|shutdown$/);
	$ret = &execution("ssh $vmk vim-cmd vmsvc/power.${powerop_mode} $vmid");
	if ($ret) {
		&Log("[E][PowerOffOpMode] [$vmk] failed to issue [$powerop_mode] for [$vmname].\n");
		foreach (@lines){
			if ( /vim.fault.QuestionPending/ ) {
				# Countermeasure for when iSCSI Cluster gets failover while
				# VM is running and become to have vmdk which is not locked.
				# The VM start to shutdown and get QuestionPending status.
				&ResolveVmStuck();
			}
		}
		$ret = 1;
	}else{
		&Log("[I][PowerOffOpMode] [$vmk] issued [$powerop_mode] for [$vmname].\n");
		$ret = 0;
	}
	return $ret;
}
#-------------------------------------------------------------------------------
sub WaitPowerOff{
	for (my $i = 0; $i < $max_cnt; $i++){

		if (&execution("ssh ${vmk} vim-cmd vmsvc/getallvms 2>&1 | grep '${vmx}'")) {
			&Log("[I][WaitPowerOff] [$vmname] not exist in inventory.\n");
			return 0;
		}

		if ( &StorageReady ) {
			&PowerOffOpMode("off");
			return 1;
		}

		if (&IsPoweredOff()){
			&Log("[I][WaitPowerOff] [$vmname] power off completed. (cnt=$i)\n");
			return 0;
		}
		&Log("[I][WaitPowerOff] [$vmname] waiting power off. (cnt=$i)\n");
		sleep $interval;
	}
	&Log("[E][WaitPowerOff] [$vmname] powered off not completed. (cnt=$max_cnt)\n");

	# There is a case that this script successfully issued "shutdown" for the VM
	# but the VM got stuck during shutdown.
	# The VM kept powere-on and retry exceeded $max_cnt then
	# thsi script failed to unregister the VM.
	# To avoid such a situation, issuing "off" for the VM here just in case.
	&Log("[D][WaitPowerOff] [$vmk] issued [off] for [$vmname] just in case.\n");
	&PowerOffOpMode("off");

	return 1;
}
#-------------------------------------------------------------------------------
sub UnRegisterVm{
	my $ret = 0;
	if ($ret = &execution("ssh $vmk vim-cmd vmsvc/unregister $vmid")) {
		&Log("[E][UnRegisterVm] [$vmname] at [$vmk] failed to unregister.\n");
	} else {
		&Log("[I][UnRegisterVm] [$vmname] at [$vmk] unregistered.\n");
	}
	return $ret;
}
#-------------------------------------------------------------------------------
sub StorageReady{
	my $device = "";
	&execution("ssh $vmk esxcli storage vmfs extent list");
	foreach (@lines) {
		if(/^$datastore\s+(.+?\s+){2}(.+?)\s.*/){
			$device = $2;
			&Log("[D][StorageReady] datastore [$datastore] found\n");
			last;
		}
	}
	if($device eq ""){
		&Log("[E][StorageReady] datastore [$datastore] not found\n");
		&execution("ssh $vmk esxcli storage core adapter rescan --adapter $vmhba");
		return 0;
	} elsif (&execution("ssh $vmk esxcli storage core path list -d $device | grep \"State\: active\"")){
		&Log("[E][StorageReady] datastore [$datastore] state not found.\n");
		return 1;
        } else {
                &Log("[D][StorageReady] datastore [$datastore] state found.\n");
        }
	return 0;
}
#-------------------------------------------------------------------------------
sub ResolveVmStuck{
	my $QID = 0;
	my $ret = 0;

	# Confirming question
	&execution("ssh $vmk vim-cmd vmsvc/message $vmid");
	foreach (@lines) {
		if (/Virtual machine message (\d+):/) {
			$QID = $1;
		}
		elsif (/No message./){
			&Log("[I][ResolveVmStuck] [$vmname] not questioned.\n");
			return 0;
		}
	}
	if ($QID) {
		&Log("[D][ResolveVmStuck] Answer to Question [$QID] by \"0) OK\"\n");
		&execution("ssh $vmk vim-cmd vmsvc/message $vmid $QID 0");
	}

	##
	## TBD : Check whether the stuck was resolved or not
	##

	#if (&IsEqualState($state{"VM_EXECUTION_STATE_STUCK"})){
	#	&Log("[E] [$vmname] at [$vmk]: VM stuck could not be resolved.\n");
	#}else{
	#	$ret = 1;
	#	&Log("[I] [$vmname] at [$vmk]: VM stuck is resolved.\n");
	#}
	#return $ret;

	return 0;
}

#-------------------------------------------------------------------------------
sub execution {
        my $cmd = shift;
        &Log("[D] executing [$cmd]\n");
        open(my $h, "$cmd 2>&1 |") or die "[E] execution [$cmd] failed [$!]";
        @lines = <$h>;
	foreach (@lines) {
		chomp;
		&Log("[D] | $_\n");
	}
	close($h);
	&Log(sprintf("[D] result ![%d] ?[%d] >> 8 = [%d]\n", $!, $?, $? >> 8));
	return $?;
}
#-------------------------------------------------------------------------------
sub Log{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$year += 1900;
	$mon += 1;
	my $date = sprintf "%d/%02d/%02d %02d:%02d:%02d", $year, $mon, $mday, $hour, $min, $sec;
	print "$date $_[0]";
	return 0;
}
