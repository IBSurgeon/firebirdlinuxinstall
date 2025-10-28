#!/usr/bin/env bash

# Please contact IBSurgeon with any question regarding this script: support@ib-aid.com
# This script is provided AS IS, without any warranty.
# This script is licensed under IDPL https://firebirdsql.org/en/initial-developer-s-public-license-version-1-0/

FB_VER=2.5
FTP_URL="https://cc.ib-aid.com/download/distr"

TMP_DIR=$(mktemp -d)
OLD_DIR=$(pwd -P)
DBG_INFO=0
ENOUGH_MEM=7168000
MAX_MAP_COUNT=1000000

MOD_SCRIPT=$TMP_DIR/fb/scripts/postinstall.sh
#------------------------------------------------------------------------
#  register/start/stop server using systemd

SYSTEMCTL=systemctl
SYSTEMD_DIR=/usr/lib/systemd/system
[ -d $SYSTEMD_DIR ] || SYSTEMD_DIR=/lib/systemd/system

PROC_SKT_CTRL=firebird.socket
PROC_SVC_CTRL=firebird@.service
THRD_SVC_CTRL=firebird.service

# Determine linux distro
detectDistro() {
    if [ -f /etc/os-release ]; then
        # Читаем информацию из os-release
        . /etc/os-release
        DISTRO_NAME="$ID"
        DISTRO_VERSION="$VERSION_ID"
        DISTRO_PRETTY_NAME="$PRETTY_NAME"
    elif [ -f /etc/lsb-release ]; then
        # Для старых версий Ubuntu
        . /etc/lsb-release
        DISTRO_NAME="${DISTRIB_ID,,}" # преобразуем в нижний регистр
        DISTRO_VERSION="$DISTRIB_RELEASE"
        DISTRO_PRETTY_NAME="$DISTRIB_DESCRIPTION"
    elif [ -f /etc/redhat-release ]; then
        # Для RedHat-based систем
        DISTRO_NAME="rhel"
        DISTRO_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release)
        DISTRO_PRETTY_NAME=$(cat /etc/redhat-release)
    else
        echo "Could not determine your linux distro!"
        exit 1
    fi
}

downloadFile(){
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
        "404") exitScript 1 "File not found on server";;
           * ) exitScript 1 "HTTP error ($m)";;
    esac
    case $r in
       0) echo "OK";;
      23) exitScript $r "Write error";;
      67) exitScript $r "Wrong login / password";;
      78) exitScript $r "File $url does not exist on server";;
       *) exitScript $r "Error downloading file ($r)";;
    esac
}

exitScript(){
        p1=$1
        p2=$2
        if [[ -z "$p1" ]]; then
                p1=0                            # p1 was empty
        fi
        # cleanup
        if [ -d $TMP_DIR ]; then rm -rf $TMP_DIR; fi
        if [ $p1 -eq 0 ]; then          # normal termination
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
    param=$(echo "$str" | sed -E 's/^\s*([^[:space:]]+)\s*=.*$/\1/') # '
    if grep -q $param $SYSCTL; then
        echo "Parameter $param already set in $SYSCTL"
    else
        echo $str >> $SYSCTL
        sysctl -p
    fi
}

configureCentosFW(){
	if [[ "$(firewall-cmd --state)" -eq "running" ]]; then
		ports=$1
		IFS=',' read -ra port_array <<< "$ports"
		for p in "${port_array[@]}"; do
			if firewall-cmd --permanent --query-port="$p/tcp" >/dev/null 2>&1; then
                        	echo "Port $p/tcp already opened"
			else
				echo "Opening port $p"
				if firewall-cmd --zone=public --permanent --add-port="$p/tcp"; then
					echo ""
				else
					echo "Error opening port $p/tcp"
				fi
			fi
		done
		echo "Reloading firewall..."
		firewall-cmd --reload
	fi
}

prepareAlma9(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y epel-release || exitScript 1 "Error installing software"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc java-1.8.0-openjdk || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 8082,8083,8721,3050,40000
}

prepareAlma10(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y epel-release || exitScript 1 "Error installing software"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0

	echo Installing Adoptium Java 8 ===============================================
	cat <<EOF > /etc/yum.repos.d/adoptium.repo
[Adoptium]
name=Adoptium
baseurl=https://packages.adoptium.net/artifactory/rpm/centos/10/x86_64
enabled=1
gpgcheck=1
gpgkey=https://packages.adoptium.net/artifactory/api/gpg/key/public
EOF
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y temurin-8-jre || exitScript 1 "Error installing Java"
	chcon -t bin_t /usr/lib/jvm/temurin-8-jre/bin/java
	configureCentosFW 8082,8083,8721,3050,40000
}

prepareCentos7(){
	yum update -y || exitScript 1 "Error updating OS"
	yum install -y epel-release || exitScript 1 "Error installing software"
	yum install -y wget ncurses libtommath icu lsof mc java tar || exitScript 1 "Error installing software"

	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 8082,8083,8721,3050,40000
}

prepareCentos8(){
	yum update -y || exitScript 1 "Error updating OS"
	yum install -y epel-release || exitScript 1 "Error installing software"
	yum install -y wget ncurses ncurses-compat-libs libtommath icu lsof mc java tar || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 8082,8083,8721,3050,40000
}

prepareCentos9(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y epel-release || exitScript 1 "Error installing software"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc java-1.8.0-openjdk
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 8082,8083,8721,3050,40000
}

prepareCentos10(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y epel-release || exitScript 1 "Error installing software"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc 
	ln -s libtommath.so.1 /lib64/libtommath.so.0

	echo Installing Adoptium Java 8 ===============================================
	cat <<EOF > /etc/yum.repos.d/adoptium.repo
[Adoptium]
name=Adoptium
baseurl=https://packages.adoptium.net/artifactory/rpm/centos/10/x86_64
enabled=1
gpgcheck=1
gpgkey=https://packages.adoptium.net/artifactory/api/gpg/key/public
EOF

	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y temurin-8-jre || exitScript 1 "Error installing Java"
	chcon -t bin_t /usr/lib/jvm/temurin-8-jre/bin/java
	configureCentosFW 8082,8083,8721,3050,40000	
}

prepareDebian11(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y net-tools libtommath1 libicu67 wget unzip gettext libncurses5 curl tar tzdata locales sudo mc xz-utils file apt-transport-https gpg || exitScript 1 "Error installing software"
	wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null
	echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list
	apt update || exitScript 1 "Error updating OS"
	apt install -y temurin-8-jre || exitScript 1 "Error installing Java"
	ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
	locale-gen "en_US.UTF-8"
}

prepareDebian12(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y net-tools libtommath1 libicu72 wget unzip gettext libncurses5 curl tar tzdata locales sudo mc xz-utils file apt-transport-https gpg || exitScript 1 "Error installing software"
	wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null
	echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list
	apt update || exitScript 1 "Error updating OS"
	apt install -y temurin-8-jre || exitScript 1 "Error installing Java"
	ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
	locale-gen "en_US.UTF-8"
}

prepareSuse15(){
	zypper -n update || exitScript 1 "Error updating OS"
	zypper -n install insserv sysvinit-tools wget libtommath1 libicu73_2 lsof tar mc java-1_8_0-openjdk || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /usr/lib64/libtommath.so.0
	configureCentosFW 8082,8083,8721,3050,40000
}

prepareOracle8(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y oracle-epel-release-el8 || exitScript 1 "Error installing software"
	dnf install -y tar wget mc ncurses-compat-libs libicu libtommath java-1.8.0-openjdk-headless || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 8082,8083,8721,3050,40000
}

prepareOracle9(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y oracle-epel-release-el9 || exitScript 1 "Error installing software"
	dnf config-manager --enable ol9_developer_EPEL
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y tar wget mc ncurses-compat-libs libicu libtommath java-1.8.0-openjdk-headless || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 8082,8083,8721,3050,40000
}

prepareOracle10(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm  -y || exitScript 1 "Error installing software"
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y tar wget mc ncurses-compat-libs libicu libtommath || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	echo Installing Adoptium Java 8 ===============================================
	cat <<EOF > /etc/yum.repos.d/adoptium.repo
[Adoptium]
name=Adoptium
baseurl=https://packages.adoptium.net/artifactory/rpm/centos/10/x86_64
enabled=1
gpgcheck=1
gpgkey=https://packages.adoptium.net/artifactory/api/gpg/key/public
EOF
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y temurin-8-jre || exitScript 1 "Error installing Java"
	chcon -t bin_t /usr/lib/jvm/temurin-8-jre/bin/java
	configureCentosFW 8082,8083,8721,3050,40000
}

prepareRocky8(){
	dnf -y update || exitScript 1 "Error updating OS"
	dnf -y install epel-release
	dnf -y install findutils libtommath libicu xz mc ncurses-libs ncurses-compat-libs
	dnf -y install java-1.8.0-openjdk-headless
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 8082,8083,8721,3050,40000
}

prepareRocky9(){
	dnf -y update || exitScript 1 "Error updating OS"
	dnf -y install epel-release
	dnf -y install findutils libtommath libicu xz mc ncurses-libs ncurses-compat-libs tar
	dnf -y install java-1.8.0-openjdk-headless
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 8082,8083,8721,3050,40000	
}

prepareRocky10(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y epel-release
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc 
	ln -s libtommath.so.1 /lib64/libtommath.so.0

	echo Installing Adoptium Java 8 ===============================================
	cat <<EOF > /etc/yum.repos.d/adoptium.repo
[Adoptium]
name=Adoptium
baseurl=https://packages.adoptium.net/artifactory/rpm/centos/10/x86_64
enabled=1
gpgcheck=1
gpgkey=https://packages.adoptium.net/artifactory/api/gpg/key/public
EOF

	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y temurin-8-jre
	chcon -t bin_t /usr/lib/jvm/temurin-8-jre/bin/java
	configureCentosFW 8082,8083,8721,3050,40000
}

prepareUbuntu20(){
	apt update -y # Updating Ubuntu 20 will definitely give an error
	apt install --no-install-recommends -y net-tools libtommath1 libicu66 wget unzip gettext libncurses5 curl tar openjdk-8-jre tzdata locales sudo mc xz-utils file bsdmainutils || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0
	locale-gen "en_US.UTF-8"
}

prepareUbuntu22(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y net-tools libtommath1 libicu70 wget unzip gettext libncurses5 curl tar openjdk-8-jre tzdata locales sudo mc xz-utils file || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0
	locale-gen "en_US.UTF-8"
}

prepareUbuntu24(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y ca-certificates net-tools wget unzip gettext libncurses6 curl tar tzdata locales sudo mc xz-utils file libtommath1 libicu74 openjdk-8-jre || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0
	ln -s libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5
	locale-gen "en_US.UTF-8"
}

prepareOS(){
	echo "Distro: $DISTRO_PRETTY_NAME"
	echo "ID/Version: $DISTRO_NAME/$DISTRO_VERSION"
	case $DISTRO_NAME in
		almalinux)
			case $DISTRO_VERSION in
				9.0) prepareAlma9;;
				10.0) prepareAlma10;;
				*) exitScript 1 "This version ($DISTRO_VERSION) of Alma Linux is not supported";;
			esac
			;;
		centos)
			case $DISTRO_VERSION in
				7) prepareCentos7;;
				8) prepareCentos8;;
				9) prepareCentos9;;
				10) prepareCentos10;;
				*) exitScript 1 "This version ($DISTRO_VERSION) of CentOS Linux is not supported";;
			esac
			;;
		debian)
			case $DISTRO_VERSION in
				11) prepareDebian11;;
				12) prepareDebian12;;
				*) exitScript 1 "This version ($DISTRO_VERSION) of Debian Linux is not supported";;
			esac
			;;
		opensuse-leap)
			case $DISTRO_VERSION in
				15.6) prepareSuse15;;
				*) exitScript 1 "This version ($DISTRO_VERSION) of OpenSuSE Linux is not supported";;
			esac
			;;
		ol)
			case $DISTRO_VERSION in
				8.10) prepareOracle8;;
				9.6) prepareOracle9;;
				10.0) prepareOracle10;;
				*) exitScript 1 "This version ($DISTRO_VERSION) of Oracle Linux is not supported";;
			esac
			;;
		rocky)
			case $DISTRO_VERSION in
				8.0) prepareRocky8;;
				9.0) prepareRocky9;;
				10.0) prepareRocky10;;
				*) exitScript 1 "This version ($DISTRO_VERSION) of Rocky Linux is not supported";;
			esac
			;;
		ubuntu)
			case $DISTRO_VERSION in
				20.04)	prepareUbuntu20;;
				22.04)	prepareUbuntu22;;
				24.04)	prepareUbuntu24;;
				*)	echo "This version ($DISTRO_VERSION) of Ubuntu Linux is not supported";;
			esac
			;;
		*) exitScript 1 "Your Linux distro is not supported";;
	esac
	append_str_to_sysctl "vm.max_map_count = $MAX_MAP_COUNT"
}

downloadFiles(){
	## Firebird & Hqbird download
	downloadFile $FTP_URL/$FB_VER/fb.tar.xz $TMP_DIR "FB installer"
	downloadFile $FTP_URL/$FB_VER/conf.tar.xz $TMP_DIR "FB config files"
	if [ $DBG_INFO -ne 0 ]; then
		downloadFile $FTP_URL/$FB_VER/dbg.tar.xz $TMP_DIR "FB debug files"
	fi	
	downloadFile $FTP_URL/amv2.tar.xz $TMP_DIR "AMV2 installer"
	downloadFile $FTP_URL/mon.tar.xz $TMP_DIR "MON installer"
	downloadFile $FTP_URL/distrib.tar.xz $TMP_DIR "DG installer"
	downloadFile $FTP_URL/hqbird.tar.xz $TMP_DIR "HQbird installer"
	downloadFile $FTP_URL/$FB_VER/systemd-files.tar.xz $TMP_DIR "Systemd support"
}

installFB(){
	echo Extracting FB installer ==================================================

		mkdir $TMP_DIR/fb $TMP_DIR/conf $TMP_DIR/systemd-files
		tar xvf $TMP_DIR/fb.tar.xz -C $TMP_DIR/fb --strip-components=1 > /dev/null || exitScript 1 "Error unpacking FB archive"
		tar xvf $TMP_DIR/conf.tar.xz -C $TMP_DIR/conf  > /dev/null || exitScript 1 "Error unpacking conf archive"
		tar xvf $TMP_DIR/systemd-files.tar.xz -C $TMP_DIR/systemd-files  > /dev/null || exitScript 1 "Error unpacking systemd files"
		echo "Extraction OK"

	echo Running FB installer =====================================================

	if [ -e $SYSTEMD_DIR/$PROC_SKT_CTRL -a -e $SYSTEMD_DIR/$PROC_SVC_CTRL -a -e $SYSTEMD_DIR/$THRD_SVC_CTRL ]; then
		echo "All systemd control files found."
	else
		echo "One or more systemd control files not found. Copying to $SYSTEMD_DIR"
		cp $TMP_DIR/systemd-files/{$PROC_SKT_CTRL,$PROC_SVC_CTRL,$THRD_SVC_CTRL} $SYSTEMD_DIR
		echo "Reloading systemd units"
		systemctl daemon-reload
	fi

	sed -i 's/^startService classic$/#startService classic/g' $MOD_SCRIPT
	sed -i 's/^updateInetdServiceEntry$/#updateInetdServiceEntry/g' $MOD_SCRIPT
	sed -i 's|replaceLineInFile /etc/services|#replaceLineInFile /etc/services|g' $MOD_SCRIPT

	cd $TMP_DIR/fb

	yes "masterkey" | ./install.sh
	cp $TMP_DIR/systemd-files/changeSystemdMode.sh /opt/firebird/bin/
	if [ $DBG_INFO -ne 0 ]; then
		echo "Extracting debug info..."
		tar xvf $TMP_DIR/dbg.tar.xz --directory=/opt/firebird/ --strip-components=3 > /dev/null || exit_script 1 "Error unpacking debug info archive"
	fi	

	cd $OLD_DIR
	cp -rf $TMP_DIR/conf/*.conf /opt/firebird
	/opt/firebird/bin/changeSystemdMode.sh thread
	chown -R firebird:firebird /opt/firebird/examples/empbuild
}

installHQ(){
	echo Installing HQbird ========================================================
	if [ ! -d /opt/hqbird ]; then
		echo "Creating directory /opt/hqbird"
		mkdir /opt/hqbird
	else
		echo "Directory /opt/hqbird already exists"
	fi
	tar xvf $TMP_DIR/amv2.tar.xz -C /opt/hqbird > /dev/null || exitScript 1 "Error unpacking AMV archive"
	tar xvf $TMP_DIR/mon.tar.xz -C /opt/hqbird > /dev/null || exitScript 1 "Error unpacking MON archive"
	tar xvf $TMP_DIR/distrib.tar.xz -C /opt/hqbird > /dev/null || exitScript 1 "Error unpacking DG archive"
	tar xvf $TMP_DIR/hqbird.tar.xz -C /opt/hqbird > /dev/null || exitScript 1 "Error unpacking HQ archive"

	cp /opt/hqbird/{amv2/fbccamv2.service,mon/init/systemd/fbcclauncher.service,mon/init/systemd/fbcctracehorse.service,init/systemd/hqbird.service} $SYSTEMD_DIR
	chmod -x $SYSTEMD_DIR/fbcc*.service
	systemctl daemon-reload

	if [ ! -d /opt/hqbird/outdataguard ]; then
		mkdir --parents /opt/hqbird/outdataguard/mon/logs
	fi
	mv /opt/hqbird/amv2/graphschema.json /opt/hqbird/outdataguard/mon/logs
	echo "Running HQbird setup"
	sh /opt/hqbird/hqbird-setup
	rm -f /opt/firebird/plugins/libfbtrace2db.so 2 > /dev/null
	# Store info for uninstall
	echo "/opt/firebird/" > /opt/hqbird/fb-instances.txt
}

registerHQ(){
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
	chown -R firebird:firebird /opt/hqbird
}

registerDB(){
	echo Registering test database =================================================
	mkdir -p /opt/hqbird/conf/agent/servers/hqbirdsrv/databases/test_employee_fdb/
	cp -R /opt/hqbird/conf/.defaults/database2/* /opt/hqbird/conf/agent/servers/hqbirdsrv/databases/test_employee_fdb/
	java -jar /opt/hqbird/dataguard.jar -regdb="/opt/firebird/examples/empbuild/employee.fdb" -srvver=2 -config-directory="/opt/hqbird/conf" -default-output-directory="/opt/hqbird/outdataguard"
	rm -rf /opt/hqbird/conf/agent/servers/hqbirdsrv/databases/test_employee_fdb/

	sed -i 's/db.replication_role=.*/db.replication_role=switchedoff/g' /opt/hqbird/conf/agent/servers/hqbirdsrv/databases/*/database.properties
	sed -i 's/job.enabled.*/job.enabled=false/g' /opt/hqbird/conf/agent/servers/hqbirdsrv/databases/*/jobs/replmon/job.properties
	sed -i 's/^#\s*RemoteAuxPort.*$/RemoteAuxPort = 3059/g' /opt/firebird/firebird.conf
	#sed -i 's/ftpsrv.homedir=/ftpsrv.homedir=\/opt\/database/g' /opt/hqbird/conf/ftpsrv.properties
	sed -i 's/ftpsrv.passivePorts=40000-40005/ftpsrv.passivePorts=40000-40000/g' /opt/hqbird/conf/ftpsrv.properties
	chown -R firebird:firebird /opt/hqbird /opt/firebird/firebird.conf /opt/firebird/aliases.conf
}

startServices(){
	echo Enabling HQbird services  ==================================================
	# How much physical memory do we have?
	m=$(cat /proc/meminfo | grep MemTotal | awk '{print $2}')

	if [ "$m" -ge "$ENOUGH_MEM" ]; then
		echo "Enabling ALL HQbird services"                     # Enough memory
		svc_list="hqbird fbccamv2 fbcclauncher fbcctracehorse"
	else
		echo "Not enough memory to run all HQbird services"     # Not enough memory
		echo "At least 8GB system memory required"
		echo "Enabling only core service"
		svc_list="hqbird"
	fi

	echo Restarting services ========================================================
	systemctl stop firebird
	systemctl enable $svc_list
	systemctl restart $svc_list
	sleep 5
	systemctl start firebird 
}

# Main program actions

detectDistro

# Версионно-зависимые действия
prepareOS

downloadFiles
installFB
installHQ
registerHQ
registerDB
startServices
exitScript 0
