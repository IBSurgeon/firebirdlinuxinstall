#!/bin/bash

# Please contact IBSurgeon with any question regarding this script: support@ib-aid.com
# This script is provided AS IS, without any warranty. 
# This script is licensed under IDPL https://firebirdsql.org/en/initial-developer-s-public-license-version-1-0/

FB_VER=3.0
FTP_URL="https://cc.ib-aid.com/download/distr"

TMP_DIR=$(mktemp -d)
OLD_DIR=$(pwd -P)
ENOUGH_MEM=7168000
MAX_MAP_COUNT=1000000

download_file(){
    url=$1
    tmp=$2
    name=$3
    fname=$(basename -- "$url")

    echo "Downloading $name..."
    m=$(curl -w "%{http_code}" --location $url --output $tmp/$fname --progress-bar)
    r=$?
    s=""
    case $m in
	"200") s="OK";;
	"404") exit_script 1 "File not found on server";;
	   * ) exit_script 1 "HTTP error ($m)";;
    esac
    case $r in
       0)  echo "OK";;	  
      23) exit_script $r "Write error";;
      67) exit_script $r "Wrong login / password";;
      78) exit_script $r "File $url does not exist on server";;
       *) exit_script $r "Error downloading file ($r)";;
    esac
}

exit_script(){
	p1=$1
	p2=$2
	if [[ -z "$p1" ]]; then
		p1=0				# p1 was empty
	fi
	# cleanup
	if [ -d $TMP_DIR ]; then rm -rf $TMP_DIR; fi
	if [ $p1 -eq 0 ]; then		# normal termination
		if [[ -z "$p2" ]]; then
			p2="Script terminated normally"
		fi
		echo $p2
		exit 0
	else
		if [[ -z "$p2" ]]; then
			p2="An error occured during script execution ($p1)"
		fi
		echo $p2
		exit $p1
	fi
}

append_str_to_sysctl(){
    SYSCTL=/etc/sysctl.conf
    str=$1
    param=$(echo "$str" | sed -E 's/^\s*([^[:space:]]+)\s*=.*$/\1/')
    if grep -q $param $SYSCTL; then
	echo "Parameter $param already set in $SYSCTL"
    else
	echo $str >> $SYSCTL
	sysctl -p
    fi
}

append_str_to_sysctl "vm.max_map_count = $MAX_MAP_COUNT"

apt update 
apt install --no-install-recommends -y net-tools libtommath1 libicu67 wget unzip gettext libncurses5 curl tar tzdata locales sudo mc xz-utils file apt-transport-https gpg

wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null
echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list
apt update
apt install -y temurin-8-jre

ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
locale-gen "en_US.UTF-8"

## Firebird & Hqbird download
download_file $FTP_URL/$FB_VER/fb.tar.xz $TMP_DIR "FB installer"
download_file $FTP_URL/$FB_VER/conf.tar.xz $TMP_DIR "FB config files"
download_file $FTP_URL/amvmon.tar.xz $TMP_DIR "AMV & MON installer"
download_file $FTP_URL/distrib.tar.xz $TMP_DIR "DG installer"
download_file $FTP_URL/hqbird.tar.xz $TMP_DIR "HQbird installer"

echo Extracting FB installer ==================================================

mkdir $TMP_DIR/fb $TMP_DIR/conf
tar xvf $TMP_DIR/fb.tar.xz -C $TMP_DIR/fb --strip-components=1 > /dev/null || exit_script 1 "Error unpacking FB archive"
tar xvf $TMP_DIR/conf.tar.xz -C $TMP_DIR/conf  > /dev/null || exit_script 1 "Error unpacking conf archive"
cd $TMP_DIR/fb

echo Running FB installer =====================================================

yes 'masterkey' | ./install.sh
#./install.sh -silent
cd $OLD_DIR
cp -rf $TMP_DIR/conf/*.conf /opt/firebird

echo Installing HQbird ========================================================

if [ ! -d /opt/hqbird ]; then 
	echo "Creating directory /opt/hqbird"
        mkdir /opt/hqbird
    else
	echo "Directory /opt/hqbird already exists"
fi

tar xvf $TMP_DIR/amvmon.tar.xz -C /opt/hqbird > /dev/null || exit_script 1 "Error unpacking AMV archive"
tar xvf $TMP_DIR/distrib.tar.xz -C /opt/hqbird > /dev/null || exit_script 1 "Error unpacking DG archive"
tar xvf $TMP_DIR/hqbird.tar.xz -C /opt/hqbird > /dev/null || exit_script 1 "Error unpacking HQ archive"

cp /opt/hqbird/amv/fbccamv.service /opt/hqbird/mon/init/systemd/fbcclauncher.service /opt/hqbird/mon/init/systemd/fbcctracehorse.service /opt/hqbird/init/systemd/hqbird.service /lib/systemd/system
chmod -x /lib/systemd/system/fbcc*.service
systemctl daemon-reload

if [ ! -d /opt/hqbird/outdataguard ]; then 
	echo "Creating directory /opt/hqbird/outdataguard"
	mkdir /opt/hqbird/outdataguard
    else
        echo "Directory /opt/hqbird/outdataguard already exists"
fi
echo "Running HQbird setup"
sh /opt/hqbird/hqbird-setup
rm -f /opt/firebird/plugins/libfbtrace2db.so 2 > /dev/null

echo Registering HQbird ========================================================

mkdir -p /opt/hqbird/conf/agent/servers/hqbirdsrv
cp -R /opt/hqbird/conf/.defaults/server/* /opt/hqbird/conf/agent/servers/hqbirdsrv
sed -i 's#server.installation =.*#server.installation=/opt/firebird#g' /opt/hqbird/conf/agent/servers/hqbirdsrv/server.properties
sed -i 's#server.bin.*#server.bin = ${server.installation}/bin#g' /opt/hqbird/conf/agent/servers/hqbirdsrv/server.properties
sed -i 's#server.id = .*#server.id = hqbirdsrv#g' /opt/hqbird/conf/agent/servers/hqbirdsrv/server.properties

java -Djava.net.preferIPv4Stack=true -Djava.awt.headless=true -Xms128m -Xmx192m -XX:+UseG1GC -jar /opt/hqbird/dataguard.jar -config-directory=/opt/hqbird/conf -default-output-directory=/opt/hqbird/outdataguard/ > /dev/null &
sleep 5
java -jar /opt/hqbird/dataguard.jar -register -regemail="linuxauto@ib-aid.com" -regpaswd="L8ND44AD" -installid=/opt/hqbird/conf/installid.bin -unlock=/opt/hqbird/conf/unlock -license="M"
sleep 5
pkill -f dataguard.jar
sleep 3

echo Registering test database =================================================

mkdir -p /opt/hqbird/conf/agent/servers/hqbirdsrv/databases/test_employee_fdb/
cp -R /opt/hqbird/conf/.defaults/database3/* /opt/hqbird/conf/agent/servers/hqbirdsrv/databases/test_employee_fdb/
java -jar /opt/hqbird/dataguard.jar -regdb="/opt/firebird/examples/empbuild/employee.fdb" -srvver=3 -config-directory="/opt/hqbird/conf" -default-output-directory="/opt/hqbird/outdataguard"
rm -rf /opt/hqbird/conf/agent/servers/hqbirdsrv/databases/test_employee_fdb/

sed -i 's/db.replication_role=.*/db.replication_role=switchedoff/g' /opt/hqbird/conf/agent/servers/hqbirdsrv/databases/*/database.properties
sed -i 's/job.enabled.*/job.enabled=false/g' /opt/hqbird/conf/agent/servers/hqbirdsrv/databases/*/jobs/replmon/job.properties
sed -i 's/^#\s*RemoteAuxPort.*$/RemoteAuxPort = 3059/g' /opt/firebird/firebird.conf
#sed -i 's/ftpsrv.homedir=/ftpsrv.homedir=\/opt\/database/g' /opt/hqbird/conf/ftpsrv.properties
sed -i 's/ftpsrv.passivePorts=40000-40005/ftpsrv.passivePorts=40000-40000/g' /opt/hqbird/conf/ftpsrv.properties
chown -R firebird:firebird /opt/hqbird /opt/firebird/firebird.conf /opt/firebird/databases.conf

echo Enabling HQbird services  ==================================================
# How much physical memory do we have?
m=$(cat /proc/meminfo | grep MemTotal | awk '{print $2}')

if [ "$m" -ge "$ENOUGH_MEM" ]; then
	echo "Enabling ALL HQbird services"			# Enough memory
        svc_list="hqbird fbccamv fbcclauncher fbcctracehorse"
else
        echo "Not enough memory to run all HQbird services"	# Not enough memory
        echo "At least 8GB system memory required"
        echo "Enabling only core service"	
        svc_list="hqbird"
fi

echo Restarting services ========================================================
systemctl stop firebird-superserver
systemctl enable $svc_list
systemctl restart $svc_list
sleep 15
systemctl restart firebird-superserver

exit_script 0

