#! /bin/sh
#***********************************************
#*       genw.sh for updating arp table        *
#***********************************************

ulimit -s unlimited

fip=`clpstat --rsc fip1 | grep IP | awk -F: '{print $2}' | sed -e 's/ //g'`
svnames=`clpstat --sv | grep "Server"`
host1=`echo "$svnames" | awk 'NR==1' | awk '{print $3}' | sed -e '{s/]//g}'`
host2=`echo "$svnames" | awk 'NR==2' | awk '{print $3}' | sed -e '{s/]//g}'`
myHostname=`hostname | awk -F. '{print $1}'`

if [ $myHostname = $host1 ];
then
  otherHostname=$host2
else
  otherHostname=$host1
fi

echo "----- Monitor start -----"
echo fip=$fip
echo myHostname=$myHostname
echo otherHostname=$otherHostname

clpstat | grep $otherHostname | grep Online >/dev/null
if [ $? -ne 0 ];
then
  echo "`date +"%Y/%m/%d %H:%M:%S"`: Other host is not Online."
  exit
fi

clpstat --local | grep current | grep $myHostname >/dev/null
if [ $? -ne 0 ];
then
  echo "`date +"%Y/%m/%d %H:%M:%S"`: Failover Gourp is not Active on this server."
  exit
fi

clpstat -h $otherHostname | grep current | grep $otherHostname
if [ $? -eq 0 ];
then
  echo "`date +"%Y/%m/%d %H:%M:%S"`: Error! Both Activation occurs."
  exit
fi

echo `date +"%Y/%m/%d %H:%M:%S": `
arping -A -c 1 -I `ip -o addr show | grep $fip | awk '{print $2}'` -s $fip $fip
exit 0
