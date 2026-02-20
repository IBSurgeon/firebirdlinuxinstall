#!/usr/bin/env bash

# Please contact IBSurgeon with any question regarding this script: support@ib-aid.com
# This script is provided AS IS, without any warranty.
# This script is licensed under IDPL https://firebirdsql.org/en/initial-developer-s-public-license-version-1-0/

FB_VER=3.0
FB_URL="https://github.com/FirebirdSQL/firebird/releases/download/v3.0.13/Firebird-3.0.13.33818-0.amd64.tar.gz"
DBG_URL="https://github.com/FirebirdSQL/firebird/releases/download/v3.0.13/Firebird-debuginfo-3.0.13.33818-0.amd64.tar.gz"
FTP_URL="https://cc.ib-aid.com/download/distr"

CRYPT_ARC=CryptPlugin-FB_30_LINUX_64bit.tar.xz

SYSCTL=/etc/sysctl.conf
SYS_STR="vm.max_map_count"
FB_ROOT=/opt/firebird
DB_CONF=$FB_ROOT/databases.conf
EMP_DB=$FB_ROOT/examples/empbuild/employee.fdb
KH_STR="KeyHolderPlugin"

DEBUG=0
CRYPT=0
CRYPT_ONLY=0

TMP_DIR=$(mktemp -d)
OLD_DIR=$(pwd -P)

MAX_MAP_COUNT=1000000

#------------------------------------------------------------------------
#  register/start/stop server using systemd

SYSTEMCTL=systemctl
SYSTEMD_DIR=/usr/lib/systemd/system
[ -d $SYSTEMD_DIR ] || SYSTEMD_DIR=/lib/systemd/system

askQuestion() {
	Test=$1
	DefaultAns=$2
	printf %s "$Test"
	Answer="$DefaultAns"
	read Answer
	if [ -z "$Answer" ]
	then
		Answer="$DefaultAns"
	fi
}

# Determine linux distro
detectDistro() {
    if [ -f /etc/os-release ]; then
        # read info from os-release
        . /etc/os-release
        DISTRO_NAME="$ID"
        DISTRO_VERSION="$VERSION_ID"
        DISTRO_PRETTY_NAME="$PRETTY_NAME"
    elif [ -f /etc/lsb-release ]; then
        # old Ubuntus
        . /etc/lsb-release
        DISTRO_NAME="${DISTRIB_ID,,}" # convert to lower
        DISTRO_VERSION="$DISTRIB_RELEASE"
        DISTRO_PRETTY_NAME="$DISTRIB_DESCRIPTION"
    elif [ -f /etc/redhat-release ]; then
        # Для RedHat-based систем
        DISTRO_NAME="rhel"
        DISTRO_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release)
        DISTRO_PRETTY_NAME=$(cat /etc/redhat-release)
    else
        exitScript 1 "Could not determine your linux distro!"
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
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareAlma10(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y epel-release || exitScript 1 "Error installing software"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareAstra1_7(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y net-tools libtommath1 libicu63 wget unzip gettext libncurses6 curl tar tzdata locales sudo mc xz-utils file apt-transport-https gpg || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
	locale-gen "en_US.UTF-8"
}

prepareAstra1_8(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y net-tools libtommath1 libicu72 wget unzip gettext libncurses6 curl tar tzdata locales sudo mc xz-utils file apt-transport-https gpg  || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
	locale-gen "en_US.UTF-8"
}

prepareCentos7(){
	yum update -y || exitScript 1 "Error updating OS"
	yum install -y epel-release
	yum install -y wget ncurses libtommath icu lsof mc java tar 
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareCentos8(){
	yum update -y
	yum install -y epel-release || exitScript 1 "Error installing software"
	yum install -y wget ncurses ncurses-compat-libs libtommath icu lsof mc java tar || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareCentos9(){
	dnf update -y
	dnf install -y epel-release || exitScript 1 "Error installing software"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareCentos10(){
	dnf update -y
	dnf install -y epel-release || exitScript 1 "Error installing software"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc || exitScript 1 "Error installing software" 
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareDebian11(){
	apt update 
	apt install --no-install-recommends -y net-tools libtommath1 libicu67 wget unzip gettext libncurses5 curl tar tzdata locales sudo mc xz-utils file apt-transport-https gpg || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
	locale-gen "en_US.UTF-8"
}

prepareDebian12(){
	apt update 
	apt install --no-install-recommends -y net-tools libtommath1 libicu72 wget unzip gettext libncurses5 curl tar tzdata locales sudo mc xz-utils file apt-transport-https gpg
	ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
	locale-gen "en_US.UTF-8"
}

prepareSuse15(){
	zypper -n update
	zypper -n install insserv sysvinit-tools wget libtommath1 libicu73_2 lsof tar mc
	ln -s libtommath.so.1 /usr/lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareOracle8(){
	dnf update -y
	dnf install -y oracle-epel-release-el8
	dnf install -y tar wget mc ncurses-compat-libs libicu libtommath
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareOracle9(){
	dnf update -y
	dnf install -y oracle-epel-release-el9
	dnf config-manager --enable ol9_developer_EPEL
	dnf update -y
	dnf install -y tar wget mc ncurses-compat-libs libicu libtommath
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareOracle10(){
	dnf update -y
	dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm  -y
	dnf update -y
	dnf install -y tar wget mc ncurses-compat-libs libicu libtommath
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareRocky8(){
	dnf -y update || exitScript 1 "Error updating OS"
	dnf -y install epel-release
	dnf -y install findutils libtommath libicu xz mc ncurses-libs ncurses-compat-libs tar
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareRocky9(){
	dnf -y update || exitScript 1 "Error updating OS"
	dnf -y install epel-release
	dnf -y install findutils libtommath libicu xz mc ncurses-libs ncurses-compat-libs tar
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareRedOS7(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
}

prepareRedOS8(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareRocky10(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y epel-release
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc 
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareUbuntu20(){
	apt update -y # Updating Ubuntu 20 will definitely give an error
	apt install --no-install-recommends -y net-tools libtommath1 libicu66 wget unzip gettext libncurses5 curl tar tzdata locales sudo mc xz-utils file bsdmainutils || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0
	locale-gen "en_US.UTF-8"
}

prepareUbuntu22(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y net-tools libtommath1 libicu70 wget unzip gettext libncurses5 curl tar tzdata locales sudo mc xz-utils file bsdmainutils || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0
	locale-gen "en_US.UTF-8"
}

prepareUbuntu24(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y ca-certificates net-tools wget unzip gettext libncurses6 curl tar tzdata locales sudo mc xz-utils file libtommath1 libicu74 bsdmainutils || exitScript 1 "Error installing software"
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
				9.*) prepareAlma9;;
				10.*) prepareAlma10;;
				*) exitScript 1 "This version ($DISTRO_VERSION) of Alma Linux is not supported";;
			esac
			;;
		astra)
			case $DISTRO_VERSION in
				1.7_x86-64) prepareAstra1_7;;
				1.8_x86-64) prepareAstra1_8;;
				*) exitScript 1 "This version ($DISTRO_VERSION) of ($DISTRO_PRETTY_NAME) is not supported";;
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
				8.*) prepareOracle8;;
				9.*) prepareOracle9;;
				10.*) prepareOracle10;;
				*) exitScript 1 "This version ($DISTRO_VERSION) of Oracle Linux is not supported";;
			esac
			;;
		redos)
			case $DISTRO_VERSION in
				7.*) prepareRedOS7;;
				8.*) prepareRedOS8;;
				*) exitScript 1 "This version ($DISTRO_VERSION) of RedOS Linux is not supported";;
			esac
			;;
		rocky)
			case $DISTRO_VERSION in
				8.*) prepareRocky8;;
				9.*) prepareRocky9;;
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
	## Firebird download
	downloadFile $FB_URL $TMP_DIR "FB installer"
	downloadFile $FTP_URL/$FB_VER/confv.tar.xz $TMP_DIR "FB config files"
}

installFB(){
	echo Extracting FB installer ==================================================

	mkdir $TMP_DIR/fb $TMP_DIR/conf
	tar xvf $TMP_DIR/Firebird-3*.gz -C $TMP_DIR/fb --strip-components=1 > /dev/null || exit_script 1 "Error unpacking FB archive"
	tar xvf $TMP_DIR/confv.tar.xz -C $TMP_DIR/conf > /dev/null || exit_script 1 "Error unpacking conf archive"
	echo "Extraction OK"

	echo Running FB installer =====================================================

	cd $TMP_DIR/fb
	yes 'masterkey' | ./install.sh
	cd $OLD_DIR
	cp -rf $TMP_DIR/conf/*.conf /opt/firebird
	chown -R firebird:firebird /opt/firebird/examples/empbuild
}

installCryptPlugin(){
	if [ ! -d $FB_ROOT ]; then
		echo "Firebird root directory $FB_ROOT not found, exiting."
		exit_script 1
	fi
	downloadFile $FTP_URL/crypt/$CRYPT_ARC $TMP_DIR "FB crypt plugin"
	mkdir $TMP_DIR/crypt
	tar xvf $TMP_DIR/$CRYPT_ARC -C $TMP_DIR/crypt --strip-components=1 > /dev/null || exit_script 1 "Error unpacking FB crypto plugin"
	cp -r $TMP_DIR/crypt/Server/{bin,plugins} $FB_ROOT
	KH_STR="KeyHolderPlugin"

	if grep -q $KH_STR $DB_CONF; then
		echo "Parameter $KH_STR already set in $DB_CONF"
	else
		if grep -q $KH_STR $DB_CONF; then
			echo "Found Employee database in $DB_CONF"
		else
			echo "Employee database alias not found in $DB_CONF, appending..."
			printf "\nemployee = $EMP_DB" >> $DB_CONF
		fi
		echo "Setting plugin in $DB_CONF..."
		sed -i '/^employee =/a\{\n KeyHolderPlugin = KeyHolder\n}' $DB_CONF
	fi
	if [ -f $EMP_DB ]; then
		$FB_ROOT/bin/isql localhost:employee -user SYSDBA -pas masterkey <<EOF
alter database encrypt with "DbCrypt" key red;
show database;
EOF
	else
		echo "Example database $EMP_DB not found."
		echo "You can use employee database section in $DB_CONF as an example to encrypt your own database."
	fi
}

startServices(){
	echo Restarting services ========================================================
	systemctl stop firebird-superserver
	systemctl start firebird-superserver
}

# Main program actions

displayHelp(){
	echo "This program will install Firebird $FB_VER on this computer
    Command line switches:
    --debug - also install debug information, takes more traffic;
    --crypt - install and configure crypto plugin
    --crypt-only[=/path/to/firebird] - install and configure ONLY crypto plugin without Firebird"
}

old_count=0
param_count=$#
while [[ "$#" -gt 0 ]]; do
        old_count=$#
        case "$1" in
		"--debug"	) DEBUG=1; shift ;;
		"--crypt"	) CRYPT=1; shift;;
		"--crypt-only"	) CRYPT_ONLY=1; FB_ROOT="/opt/firebird"; shift;;
                "--crypt-only="*) CRYPT_ONLY=1; FB_ROOT=$(echo "$1" | sed 's/.*=//'); shift ;;
		"-i"|"--info"	) displayHelp; shift;;
	esac
	if [ $old_count -eq $# ]; then
		echo "Unknown parameter passed: $1"
		displayHelp
		exit_script 1
	fi
done

if [ $param_count -eq 0 ]; then
	displayHelp
	askQuestion "Press Enter to start installation or ^C to abort"
fi
if [ $CRYPT_ONLY -eq 1 ]; then
	installCryptPlugin
else
	detectDistro
	prepareOS
	downloadFiles
	installFB
	if [ $CRYPT -eq 1 ]; then
		installCryptPlugin
	fi
	if [ $DEBUG -eq 1 ]; then
		downloadFile $DBG_URL $TMP_DIR "FB debug files"
		echo "Installing FB debug files"
		mkdir $TMP_DIR/debug
		tar xvf $TMP_DIR/Firebird-debuginfo-3.*.amd64.tar.gz -C $TMP_DIR/debug > /dev/null || exit_script 1 "Error unpacking FB debug info"
		cp -R $TMP_DIR/debug/opt/firebird/* $FB_ROOT
	fi
	startServices
fi

exitScript 0
