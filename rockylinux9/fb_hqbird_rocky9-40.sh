#!/usr/bin/env bash

# Please contact IBSurgeon with any question regarding this script: support@ib-aid.com
# This script is provided AS IS, without any warranty. 
# This script is licensed under IDPL https://firebirdsql.org/en/initial-developer-s-public-license-version-1-0/

FB_VER=4.0
FTP_URL="https://cc.ib-aid.com/download/distr"
TMP_DIR=$(mktemp -d)
OLD_DIR=$(pwd -P)
ENOUGH_MEM=7168000

download_file(){
    url=$1
    tmp=$2
    name=$3
    fname=$(basename -- "$url")

    echo "Downloading $name..."
    curl $url --output $tmp/$fname --progress-bar

    case $? in
      0)  echo "OK";;	  
      23) echo "Write error"
          exit 0;;
      67) echo "Wrong login / password"
              exit 0;;
      78) echo "File $fb_url/$fb_file $does not exist on server"
          exit 0;;
    esac
}

dnf -y update
dnf -y install epel-release

dnf -y install findutils libtommath libicu xz mc ncurses-libs ncurses-compat-libs tar
dnf -y install java-1.8.0-openjdk-headless

echo "vm.max_map_count = 256000" >> /etc/sysctl.conf
sysctl -p

ln -s libtommath.so.1 /lib64/libtommath.so.0

## Firebird & Hqbird download
download_file $FTP_URL/$FB_VER/fb.tar.xz $TMP_DIR "FB installer"
#download_file $FTP_URL/$FB_VER/conf.tar.xz $TMP_DIR "FB config files"
download_file $FTP_URL/amvmon.tar.xz $TMP_DIR "AMV & MON installer"
download_file $FTP_URL/distrib.tar.xz $TMP_DIR "DG installer"
download_file $FTP_URL/hqbird.tar.xz $TMP_DIR "HQbird installer"

echo Extracting FB installer ==================================================

mkdir $TMP_DIR/fb $TMP_DIR/conf
tar xvf $TMP_DIR/fb.tar.xz -C $TMP_DIR/fb --strip-components=1 > /dev/null
#tar xvf $TMP_DIR/conf.tar.xz -C $TMP_DIR/conf  > /dev/null
cd $TMP_DIR/fb

echo Running FB installer =====================================================

yes 'masterkey' | ./install.sh
#./install.sh -silent
cd $OLD_DIR
#cp -rf $TMP_DIR/conf/*.conf /opt/firebird

echo Installing HQbird ========================================================

if [ ! -d /opt/hqbird ]; then 
	echo "Creating directory /opt/hqbird"
        mkdir /opt/hqbird
    else
	echo "Directory /opt/hqbird already exists"
fi

tar xvf $TMP_DIR/amvmon.tar.xz -C /opt/hqbird > /dev/null
tar xvf $TMP_DIR/distrib.tar.xz -C /opt/hqbird > /dev/null
tar xvf $TMP_DIR/hqbird.tar.xz -C /opt/hqbird > /dev/null

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

java -Djava.net.preferIPv4Stack=true -Djava.awt.headless=true -Xms128m -Xmx192m -XX:+UseG1GC -jar /opt/hqbird/dataguard.jar -config-directory=/opt/hqbird/conf -default-output-directory=/opt/hqbird/outdataguard/ > /dev/null &
sleep 5
java -jar /opt/hqbird/dataguard.jar -register -regemail="linuxauto@ib-aid.com" -regpaswd="L8ND44AD" -installid=/opt/hqbird/conf/installid.bin -unlock=/opt/hqbird/conf/unlock -license="T"

pkill -f dataguard.jar
sleep 5

echo Registering test database =================================================

mkdir -p /opt/hqbird/conf/agent/servers/hqbirdsrv/databases/test_employee_fdb/
cp -R /opt/hqbird/conf/.defaults/database4/* /opt/hqbird/conf/agent/servers/hqbirdsrv/databases/test_employee_fdb/
java -jar /opt/hqbird/dataguard.jar -regdb="/opt/firebird/examples/empbuild/employee.fdb" -srvver=4 -config-directory="/opt/hqbird/conf" -default-output-directory="/opt/hqbird/outdataguard"
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
systemctl stop firebird
systemctl enable $svc_list
systemctl restart $svc_list
sleep 10

echo Modifying firewall ports  ==================================================

firewall-cmd --permanent --zone=public --add-port=8082/tcp  # 1) admin console
firewall-cmd --permanent --zone=public --add-port=8083/tcp  # 2) trace monitoring
firewall-cmd --permanent --zone=public --add-port=8721/tcp  # 3) internal ftp server
firewall-cmd --permanent --zone=public --add-port=3050/tcp  # 4) FB RemoteServicePort
firewall-cmd --permanent --zone=public --add-port=3059/tcp  # 5) FB RemoteAuxPort
firewall-cmd --permanent --zone=public --add-port=40000/tcp # 6) internal ftp server additional port
firewall-cmd --reload

echo Finally restarting services ===============================================
systemctl restart firebird

# cleanup
if [ -d $TMP_DIR ]; then rm -rf $TMP_DIR; fi
