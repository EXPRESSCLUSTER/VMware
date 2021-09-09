#!/usr/bin/perl -w

#
# Gambling recovery for MD resource
#
# This resource is intended to help MD recovery before activation of the MD resource.
# Issuing MD force recovery command for the primary MD resource which is in RED status
# due to "both nodes crash".
#

my $SLEEP = 10;	# seconds for sleep in loop
my $name_md = "";
my @lines = ();
my $ret   = 0;

&Log("CLP_EVENT = [" . $ENV{"CLP_EVENT"} . "]\n");
if ($ENV{"CLP_EVENT"} ne "START") {
	exit $ret;
}

&Log("CLP_SERVER = [" . $ENV{"CLP_SERVER"} . "]\n");
#if ($ENV{"CLP_SERVER"} ne "HOME") {
#	exit $ret;
#}

# Here CLP_EVENT is START
&execution("clpmdstat -l");
foreach (@lines) {
	if (/<(.*)>/) {
		$name_md = $1;
		last;
	}
}
&Log("name_md = [$name_md]\n");

while(1){
	my $flag = 0;
	&execution("clpmdstat -m $name_md");
	foreach (@lines) {
		if (/Mirror Status: No Construction/) {
			&Log("[W] Skip, since mirror is not constructed\n");
			$flag = 1;
			last;
		}
		if (/Mirror Color\s+?RED\s+(RED|GRAY)/) {
			&execution("yes | clpmdctrl -f $name_md");
			&execution("clplogcmd -m \"[exec-md-recovery] changed [$name_md] from RED-[$1] to GREEN-[$1] $1\"");
			last;
		}
		elsif (/Mirror Color\s+?RED\s+GREEN/) {
			# Giving up recovery then failover
			&execution("clplogcmd -m \"[exec-md-recovery] MD status is RED - GREEN\"");
			$flag = 1;
			$ret = 1;
			last;
		}
		elsif (/Mirror Color\s+?GREEN\s+(\S+)/) {
			&execution("clplogcmd -m \"[exec-md-recovery] MD status is GREEN - [$1]\"");
			$flag = 1;
			last;
		}
	}
	last if ($flag);
	sleep $SLEEP;	
}
exit $ret;

#-------------------------------------------------------------------------------
sub execution {
	my $cmd = shift;
	&Log("[D] executing [$cmd]\n");
	open(my $h, "$cmd 2>&1 |") or die;
	@lines = <$h>;
	foreach (@lines) {
		chomp;
		&Log("[D]\t$_\n");
	} 
	close($h); 
	&Log(sprintf("[D] result ![%d] ?[%d] >> 8 = [%d]\n", $!, $?, $? >> 8));
}

sub Log{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$year += 1900;
	$mon += 1;
	my $date = sprintf "%d/%02d/%02d %02d:%02d:%02d", $year, $mon, $mday, $hour, $min,
	   $sec;
	print "$date $_[0]";
	return 0;
}
