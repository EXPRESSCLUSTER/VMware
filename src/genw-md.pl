#!/usr/bin/perl -w

#
# "RED-Active RED" monitor
#
# This provides countermeasure for "RED-Active RED" situation in the MD resource.
# Issuung the MD force recovery command when the active MD resource gets RED status.
#

my $ret = 0;
my @lines = ();
my $name_md = "";

# Getting the MD name
&execution("clpmdstat -l");
foreach (@lines) {
	if (/<(.+)>/) {
		$name_md = $1;
		last
	}
}

# Checking the MD status
my $flag = 0;
&execution("clpmdstat -m \'$name_md\'");
foreach (@lines){
	if (/Mirror Color\s+?RED/){
		&Log("[D]\t$_");
		$flag = 1;
		last;
	}
}

# Forced Recovering the MD
if ($flag) {
	&execution("clpmdctrl -f $name_md");
	foreach (@lines) {
		chomp;
		&Log("[D]\t$_\n");
	}
}

exit $ret;

#-------------------------------------------------------------------------------
sub execution {
	my $cmd = shift;
	&Log("[D] executing [$cmd]\n");
	open(my $h, "$cmd 2>&1 |") or die;
	@lines = <$h>;
	#foreach (@lines) {
	#	chomp;
	#	&Log("[D]\t$_\n");
	#} 
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
