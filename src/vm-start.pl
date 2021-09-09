#!/usr/bin/perl -w
#
# Script for power on the Virtual Machine
#
# The VM can be in 3 situation before executing this script.
# 1. The VM is stoped status
# 2. The VM is running status
# 3. The VM is invalid status
#
use strict;
#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
# The path to VM configuration file. This must be absolute UUID-based path.
# like "/vmfs/volumes/<datastore-uuid>/vm1/vm1.vmx";
my @cfg_paths = (
'%%VMX%%'
);

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
# The interval to check the storage status. (second)
my $storage_check_interval = 3;
# The interval to check the vm power status. (second)
my $interval = 1;
# The maximum count to check the vm power status.
my $max_cnt = 100;
# The timeout to power on the vm. (second)
my $start_to = 10;
#-------------------------------------------------------------------------------
# Global values
my $vmk = "";
my $cfg_path = "";
my $vmname = "";
my $vmid = "";
my $vmhba = "";
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
my $r = 0;
foreach (@cfg_paths){
	$vmname = $_;
	$vmname =~ s/.*\/(.*)\/.*\.vmx/$1/;
	$cfg_path = $_;
	&Log("[I] [$vmname][$cfg_path]\n");

	if (&PreChk()) {
		next;
	}
	while (&StorageReady()) {
		sleep $storage_check_interval;
	}
	if (&Register()) {
		if (&Register()) {
			$r = 1;
		}
		next;
	}
	if (&PowerOn()) {
		$r = 1;
		next;
	}
	if (&WaitPowerOn()) {
		$r = 1;
	}
}
exit $r;
#-------------------------------------------------------------------------------
# Functions
#-------------------------------------------------------------------------------
sub PreChk {
	$vmid = "";
	&execution("ssh $vmk vim-cmd vmsvc/getallvms");
	my @tmp = @lines;
	foreach (@tmp) {
		if (/(\d+).*\s$vmname\s/) {
			$vmid = $1;
			&Log("[I][PreChk] [$vmname] in inventory.\n");
		}
		elsif (/^Skipping invalid VM \'(\d+)\'$/) {
			&Log("[D][PreChk] unregistering invalid VM($1)\n");
			&execution("ssh $vmk vim-cmd vmsvc/unregister $1");
		}
	}
	if ($vmid eq "") {
		&Log("[I][PreChk] [$vmname] not in inventory\n");
		return 0;
	} elsif (&IsPoweredOn()) {
		&Log("[I][PreChk] [$vmname] already powered on.\n");
		return 1;
	} else {
		&Log("[I][PreChk] [$vmname] not powered on.\n");
		return 0;
	}
}
#-------------------------------------------------------------------------------
sub StorageReady {
	my $device = "";
	&execution("ssh $vmk esxcli storage vmfs extent list");
	foreach (@lines) {
		if(/^$datastore\s+(.+?\s+){2}(.+?)\s.*/){
			$device = $2;
			&Log("[D][StorageReady] datastore [$datastore] found.\n");
			last;
		}
	}
	if($device eq ""){
		&Log("[E][StorageReady] datastore [$datastore] not found\n");
		&execution("ssh $vmk esxcli storage core adapter rescan --adapter $vmhba");
		return 0;
	}
	if(&execution("ssh $vmk esxcli storage core path list -d $device | grep \"State\: active\"")){
		&Log("[E][StorageReady] datastore [$datastore] state not found\n");
		return 1;
	} else {
		&Log("[E][StorageReady] datastore [$datastore] state found\n");
	}
	return 0;
}
#-------------------------------------------------------------------------------
# Registering VM
# There are two cases for invalid vm, That is existing or creating.
#
sub Register {
	$vmid = 0;
	my $ret = -1;
	&execution("ssh $vmk vim-cmd solo/registervm \'$cfg_path\'");
	foreach(@lines){
		if (/^(\d+)$/){
			$vmid = $1;
			&Log("[I][Register] [$vmname][$vmid] at [$vmk] registered\n");
			$ret = 0;
		}
		elsif (/msg = \"The specified key, name, or identifier '(\d+)' already exists.\"/) {
			$vmid = $1;
			if (&IsRegistered()) {
				&Log("[I][Register] [$vmname][$vmid] at [$vmk] registered.\n");
				$ret = 0;
			} else {
				# Unregistering the (invalid?) VM.
				&Log("[I][Register] unregister [$vmname]\n");
				&execution("ssh $vmk vim-cmd vmsvc/unregister $vmid");
				$vmid = 0;
				$ret = 1;
			}
		}
	}
	return $ret;
}
#-------------------------------------------------------------------------------
sub IsRegistered {
	if (&execution("ssh $vmk vim-cmd vmsvc/getallvms | grep ' $vmname '")) {
		&Log("[I][IsRegistered] [$vmname] not in inventory.\n");
		return 0;
	}
	&Log("[I][IsRegistered] [$vmname] in inventory.\n");
	return 1;
}
#-------------------------------------------------------------------------------
sub PowerOn{
	my $fh;
	my $ret = 0;
	my $cmd = "ssh $vmk vim-cmd vmsvc/power.on $vmid";

	&Log("[D] \texecuting [$cmd]\n");
	my $pid = open($fh, "$cmd 2>&1 |") or die "[E] execution [$cmd] failed [$!]";
	eval{
		local $SIG{ALRM} = sub { die "timeout" };
		alarm($start_to);

		@lines = <$fh>;

		alarm(0);
	};
	alarm(0);
	if ($@) {
		if($@ =~ /timeout/){
			kill 'TERM', $pid;
			close($fh); 
			&Log(sprintf("[D] \tresult ![%d] ?[%d] >> 8 = [%d]\n", $!, $?, $? >> 8));

			# Try resolving VM stuck
			&Log("[E][PowerOn] [$vmname] at [$vmk] could not start: timeout($start_to second)\n");
			$ret = &ResolveVmStuck();
		} else {
			&Log("[E][PowerOn] exception: $@\n");
			$ret = 1;
		}
	} else {
		# Both normal and abnormal cases enter here.
		# normal case: starting VM which is in stoped state.
		# abnormal case: starting VM which exists as invalid VM.
		close($fh); 
		&Log(sprintf("[D] \tresult ![%d] ?[%d] >> 8 = [%d]\n", $!, $?, $? >> 8));
		foreach (@lines) {
			chomp;
			&Log("[D] \t: $_\n");
			if (/^Power on failed/) {
				$ret = 1;
			} else {
				$ret = 0;
			}
		}
	}
	return $ret;
}
#-------------------------------------------------------------------------------
sub WaitPowerOn{
	for (my $i = 0; $i < $max_cnt; $i++){
		#
		# RegisterVm で Invalid VM を生んだ後、Invalid VM の PowerOn が失敗したまま
		# ここに突入するケースがあると max_cnt 回のループに陥る
		#
		if (&IsPoweredOn()) {
			&Log("[I][WaitPowerOn] [$vmname] power on completed. (cnt=$i)\n");
			return 0;
		}
		&Log("[I][WaitPowerOn] [$vmname] waiting power on. (cnt=$i)\n");
		sleep $interval;
	}
	&Log("[E][WaitPowerOn] [$vmname] powered on not completed. (cnt=$max_cnt)\n");
	return 1;
}
#-------------------------------------------------------------------------------
sub IsPoweredOn{
	&execution("ssh $vmk vim-cmd vmsvc/power.getstate $vmid");
	foreach (@lines) {
		if (/Powered on/) {
			&Log("[D][IsPoweredOn] [$vmname] power state is ON.\n");
			return 1;
		}
	}
	return 0;
}
#-------------------------------------------------------------------------------
sub ResolveVmStuck{
	my $QID = 0;
	my $ret = 0;

	# Confirming question
	$ret = &execution("ssh $vmk vim-cmd vmsvc/message $vmid");
	foreach (@lines) {
		if (/Virtual machine message (\d+):/) {
			$QID = $1;
		}
		elsif (/This virtual machine might have been moved or copied./) {
			&Log("[D][ResolveVmStuck] Answer to Question [$QID] by 1(I Moved It)\n");
			$ret = &execution("ssh $vmk vim-cmd vmsvc/message $vmid $QID 1");
			last;
		}
		elsif (/No message./){
			&Log("[I][ResolveVmStuck] [$vmname] not questioned.\n");
		}
	}
	return $ret;
}
#-------------------------------------------------------------------------------
sub execution {
	my $cmd = shift;
	&Log("[D] \texecuting [$cmd]\n");
	open(my $h, "$cmd 2>&1 |") or die "[E] execution [$cmd] failed [$!]";
	@lines = <$h>;
	foreach (@lines) {
		chomp;
		&Log("[D] | $_\n");
	}
	close($h); 
	&Log(sprintf("[D] \tresult ![%d] ?[%d] >> 8 = [%d]\n", $!, $?, $? >> 8));
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
