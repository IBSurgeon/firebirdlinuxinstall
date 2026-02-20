#!/usr/bin/env bash

# Please contact IBSurgeon with any question regarding this script: support@ib-aid.com
# This script is provided AS IS, without any warranty.
# This script is licensed under IDPL https://firebirdsql.org/en/initial-developer-s-public-license-version-1-0/

FB_VER=2.5
FB_URL="https://github.com/FirebirdSQL/firebird/releases/download/R2_5_9/FirebirdCS-2.5.9.27139-0.amd64.tar.gz"
FTP_URL="https://cc.ib-aid.com/download/distr"

TMP_DIR=$(mktemp -d)
OLD_DIR=$(pwd -P)
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
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050
}

prepareAlma10(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y epel-release || exitScript 1 "Error installing software"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050
}

prepareAstra1_7(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y net-tools libtommath1 libicu63 wget unzip gettext libncurses6 curl tar tzdata locales sudo mc xz-utils file apt-transport-https gpg || exitScript 1 "Error installing software"
	ln -s libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5
	ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
	locale-gen "en_US.UTF-8"
}

prepareAstra1_8(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y net-tools libtommath1 libicu72 wget unzip gettext libncurses6 curl tar tzdata locales sudo mc xz-utils file apt-transport-https gpg  || exitScript 1 "Error installing software"
	ln -s libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5
	ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
	locale-gen "en_US.UTF-8"
}


prepareCentos7(){
	yum update -y || exitScript 1 "Error updating OS"
	yum install -y epel-release || exitScript 1 "Error installing software"
	yum install -y wget ncurses libtommath icu lsof mc tar || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050
}

prepareCentos8(){
	yum update -y || exitScript 1 "Error updating OS"
	yum install -y epel-release || exitScript 1 "Error installing software"
	yum install -y wget ncurses ncurses-compat-libs libtommath icu lsof mc tar || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050
}

prepareCentos9(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y epel-release || exitScript 1 "Error installing software"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050
}

prepareCentos10(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y epel-release || exitScript 1 "Error installing software"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc  || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050
}

prepareDebian11(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y net-tools libtommath1 libicu67 wget unzip gettext libncurses5 curl tar tzdata locales sudo mc xz-utils file apt-transport-https gpg || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
	locale-gen "en_US.UTF-8"
}

prepareDebian12(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y net-tools libtommath1 libicu72 wget unzip gettext libncurses5 curl tar tzdata locales sudo mc xz-utils file apt-transport-https gpg || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
	locale-gen "en_US.UTF-8"
}

prepareSuse15(){
	zypper -n update
	zypper -n install insserv sysvinit-tools wget libtommath1 libicu73_2 lsof tar mc || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /usr/lib64/libtommath.so.0
	configureCentosFW 3050
}

prepareOracle8(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y oracle-epel-release-el8 || exitScript 1 "Error installing software"
	dnf install -y tar wget mc ncurses-compat-libs libicu libtommath  || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050
}

prepareOracle9(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y oracle-epel-release-el9 || exitScript 1 "Error installing software"
	dnf config-manager --enable ol9_developer_EPEL
	dnf update -y
	dnf install -y tar wget mc ncurses-compat-libs libicu libtommath  || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050
}

prepareOracle10(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm  -y || exitScript 1 "Error installing software"
	dnf update -y
	dnf install -y tar wget mc ncurses-compat-libs libicu libtommath || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050
}

prepareRocky8(){
	dnf -y update || exitScript 1 "Error updating OS"
	dnf -y install epel-release || exitScript 1 "Error installing software"
	dnf -y install findutils libtommath libicu xz mc ncurses-libs ncurses-compat-libs || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050
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
	configureCentosFW 3050	
}

prepareRocky9(){
	dnf -y update || exitScript 1 "Error updating OS"
	dnf -y install epel-release || exitScript 1 "Error installing software"
	dnf -y install findutils libtommath libicu xz mc ncurses-libs ncurses-compat-libs tar || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050
}

prepareRocky10(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y epel-release || exitScript 1 "Error installing software"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc  || exitScript 1 "Error installing software"
	ln -s libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050
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
				10.*) prepareRocky10;;
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
	downloadFile $FB_URL $TMP_DIR "FB installer"
	downloadFile $FTP_URL/$FB_VER/conf.tar.xz $TMP_DIR "FB config files"
	downloadFile $FTP_URL/$FB_VER/systemd-files.tar.xz $TMP_DIR "Systemd support"
}

installFB(){
	echo Extracting FB installer ==================================================

	mkdir $TMP_DIR/fb $TMP_DIR/conf $TMP_DIR/systemd-files
	tar xvf $TMP_DIR/*.gz -C $TMP_DIR/fb --strip-components=1 > /dev/null || exitScript 1 "Error unpacking FB archive"
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

	cd $OLD_DIR
	cp -rf $TMP_DIR/conf/*.conf /opt/firebird
	/opt/firebird/bin/changeSystemdMode.sh thread
	chown -R firebird:firebird /opt/firebird/examples/empbuild
}

startServices(){
	systemctl stop firebird
	systemctl start firebird 
}

# Main program actions

detectDistro

# Версионно-зависимые действия
prepareOS

downloadFiles
installFB
startServices
exitScript 0
