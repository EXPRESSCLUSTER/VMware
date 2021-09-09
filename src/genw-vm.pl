#!/usr/bin/perl -w
#
# Script for monitoring the Virtual Machine
#
use strict;

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
# The path to VM configuration file. This must be absolute UUID-based path.
# like "/vmfs/volumes/<datastore-uuid>/vm1/vm1.vmx";
my $cfg_path = '%%VMX%%';

# IP addresses of VMkernel port.
my $vmk1 = "%%VMK1%%";
my $vmk2 = "%%VMK2%%";

# IP addresses of EC VMs
my $ec1 = "%%EC1%%";
my $ec2 = "%%EC2%%";

#-------------------------------------------------------------------------------
my $vmk = "";
my $tmp = `ip address | grep $ec1/`;
if ($? == 0) {
	$vmk = $vmk1;
} else {
	$tmp = `ip address | grep $ec2/`;
	if ($? == 0) {
		$vmk = $vmk2;
	} else {
		&Log("[E] Invalid configuration (Mananegment host IP could not be found).\n");
		exit 1;
	}
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
my @lines = ();
my $vmname = $cfg_path;
$vmname =~ s/.*\/(.*)\/.*$/$1/;
my $vmx = $cfg_path;
$vmx =~ s/^.*\/(.*\/.*$)/$1/;

exit &Monitor();

#-------------------------------------------------------------------------------
# Functions
#-------------------------------------------------------------------------------
sub Monitor {
	my $vmid = 0;

	&execution("ssh $vmk vim-cmd vmsvc/getallvms | grep '$vmx'");
	foreach (@lines) {
		if (/^(\d+)/) {
			$vmid = $1;
		}
	}
	if ($vmid == 0) { return 1 };
		
	&execution("ssh $vmk vim-cmd vmsvc/get.summary $vmid | grep 'guestHeartbeatStatus'");
	foreach (@lines) {
		if (/green|yellow/) {
			return 0;
		} elsif (/red/) {
			return 1;
		}
	}

	if (&execution("ssh $vmk vim-cmd vmsvc/power.getstate $vmid | grep 'Powered on'")) {
		&Log("[E][Monitor] [$vmname] is not powered on\n");
		return 1;
	}
	return 0;
}
#-------------------------------------------------------------------------------
sub execution {
	my $cmd = shift;
	&Log("[D] \texecuting [$cmd]\n");
	open(my $h, "$cmd 2>&1 |") or die "[E] execution [$cmd] failed [$!]";
	@lines = <$h>;
	close($h);
	my $ret = $?;
	&Log(sprintf("[D] \tresult ![%d] ?[%d] >> 8 = [%d]\n", $!, $?, $? >> 8));
	foreach (@lines) {
		chomp;
		&Log("[D] \t: $_\n");
	}
	return $ret;
}
#-------------------------------------------------------------------------------
sub Log {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$year += 1900;
	$mon += 1;
	my $date = sprintf "%d/%02d/%02d %02d:%02d:%02d", $year, $mon, $mday, $hour, $min, $sec;
	print "$date $_[0]";
	return 0;
}