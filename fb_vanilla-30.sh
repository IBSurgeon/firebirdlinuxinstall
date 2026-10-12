#!/usr/bin/env bash

# Please contact IBSurgeon with any question regarding this script: support@ib-aid.com
# This script is provided AS IS, without any warranty.
# This script is licensed under IDPL https://firebirdsql.org/en/initial-developer-s-public-license-version-1-0/

FB_VER=3.0
FB_URL="https://github.com/FirebirdSQL/firebird/releases/download/v3.0.14/Firebird-3.0.14.33856-0.amd64.tar.gz"
DBG_URL="https://github.com/FirebirdSQL/firebird/releases/download/v3.0.14/Firebird-debuginfo-3.0.14.33856-0.amd64.tar.gz"
FTP_URL="https://cc.ib-aid.com/download/distr"

CRYPT_ARC=CryptPlugin-FB_30_LINUX_64bit.tar.xz

SYSCTL=/etc/sysctl.conf
SYS_STR="vm.max_map_count"
FB_ROOT=/opt/firebird
DB_CONF=$FB_ROOT/databases.conf

# server firebird.conf 
FB_CONF=""
# client firebird.conf
CL_CONF=""
EMP_DB=$FB_ROOT/examples/empbuild/employee.fdb
KH_STR="KeyHolderPlugin"

DEBUG=0
CRYPT=0
CRYPT_ONLY=0

TMP_DIR=$(mktemp -d)
OLD_DIR=$(pwd -P)
CRYPT_CLIENT_DIR=""

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
	ln -sf libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareAlma10(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y epel-release || exitScript 1 "Error installing software"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc || exitScript 1 "Error installing software"
	ln -sf libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareAstra1_7(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y net-tools libtommath1 libicu63 wget unzip gettext libncurses6 curl tar tzdata locales sudo mc xz-utils file apt-transport-https gpg || exitScript 1 "Error installing software"
	ln -sf libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
	locale-gen "en_US.UTF-8"
}

prepareAstra1_8(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y net-tools libtommath1 libicu72 wget unzip gettext libncurses6 curl tar tzdata locales sudo mc xz-utils file apt-transport-https gpg  || exitScript 1 "Error installing software"
	ln -sf libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
	locale-gen "en_US.UTF-8"
}

prepareCachyOS(){
	pacman -Syu || exitScript 1 "Error updating OS"
	pacman -S libtommath ncurses icu wget curl tar xz lsof --noconfirm || exitScript 1 "Error installing software"
	configureUFW 8082 8083 8721 3050 3059 40000
}

prepareCentos7(){
	yum update -y || exitScript 1 "Error updating OS"
	yum install -y epel-release
	yum install -y wget ncurses libtommath icu lsof mc tar 
	ln -sf libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareCentos8(){
	yum update -y
	yum install -y epel-release || exitScript 1 "Error installing software"
	yum install -y wget ncurses ncurses-compat-libs libtommath icu lsof mc tar || exitScript 1 "Error installing software"
	ln -sf libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareCentos9(){
	dnf update -y
	dnf install -y epel-release || exitScript 1 "Error installing software"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc || exitScript 1 "Error installing software"
	ln -sf libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareCentos10(){
	dnf update -y
	dnf install -y epel-release || exitScript 1 "Error installing software"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc || exitScript 1 "Error installing software" 
	ln -sf libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareDebian11(){
	apt update 
	apt install --no-install-recommends -y net-tools libtommath1 libicu67 wget unzip gettext libncurses5 curl tar tzdata locales sudo mc xz-utils file apt-transport-https gpg || exitScript 1 "Error installing software"
	ln -sf libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
	locale-gen "en_US.UTF-8"
}

prepareDebian12(){
	apt update 
	apt install --no-install-recommends -y net-tools libtommath1 libicu72 wget unzip gettext libncurses5 curl tar tzdata locales sudo mc xz-utils file apt-transport-https gpg
	ln -sf libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
	locale-gen "en_US.UTF-8"
}

prepareDebian13(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y net-tools libtommath1 libicu76 wget unzip gettext libncurses6 curl tar tzdata locales sudo mc xz-utils file apt-transport-https gpg || exitScript 1 "Error installing software"
	ln -sf libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
	locale-gen "en_US.UTF-8"
}

prepareSuse15(){
	zypper -n update
	zypper -n install insserv sysvinit-tools wget libtommath1 libicu73_2 lsof tar mc
	ln -sf libtommath.so.1 /usr/lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareOracle8(){
	dnf update -y
	dnf install -y oracle-epel-release-el8
	dnf install -y tar wget mc ncurses-compat-libs libicu libtommath
	ln -sf libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareOracle9(){
	dnf update -y
	dnf install -y oracle-epel-release-el9
	dnf config-manager --enable ol9_developer_EPEL
	dnf update -y
	dnf install -y tar wget mc ncurses-compat-libs libicu libtommath
	ln -sf libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareOracle10(){
	dnf update -y
	dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm  -y
	dnf update -y
	dnf install -y tar wget mc ncurses-compat-libs libicu libtommath
	ln -sf libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareRocky8(){
	dnf -y update || exitScript 1 "Error updating OS"
	dnf -y install epel-release
	dnf -y install findutils libtommath libicu xz mc ncurses-libs ncurses-compat-libs tar
	ln -sf libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareRocky9(){
	dnf -y update || exitScript 1 "Error updating OS"
	dnf -y install epel-release
	dnf -y install findutils libtommath libicu xz mc ncurses-libs ncurses-compat-libs tar
	ln -sf libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareRedOS7(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc || exitScript 1 "Error installing software"
	ln -sf libtommath.so.1 /lib64/libtommath.so.0
}

prepareRedOS8(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc || exitScript 1 "Error installing software"
	ln -sf libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareRocky10(){
	dnf update -y || exitScript 1 "Error updating OS"
	dnf install -y epel-release
	dnf install -y wget ncurses ncurses-compat-libs libtommath icu lsof tar mc 
	ln -sf libtommath.so.1 /lib64/libtommath.so.0
	configureCentosFW 3050,3059
}

prepareUbuntu20(){
	apt update -y # Updating Ubuntu 20 will definitely give an error
	apt install --no-install-recommends -y net-tools libtommath1 libicu66 wget unzip gettext libncurses5 curl tar tzdata locales sudo mc xz-utils file bsdmainutils || exitScript 1 "Error installing software"
	ln -sf libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0
	locale-gen "en_US.UTF-8"
}

prepareUbuntu22(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y net-tools libtommath1 libicu70 wget unzip gettext libncurses5 curl tar tzdata locales sudo mc xz-utils file bsdmainutils || exitScript 1 "Error installing software"
	ln -sf libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0
	locale-gen "en_US.UTF-8"
}

prepareUbuntu24(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y ca-certificates net-tools wget unzip gettext libncurses6 curl tar tzdata locales sudo mc xz-utils file libtommath1 libicu74 bsdmainutils || exitScript 1 "Error installing software"
	ln -sf libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0
	ln -sf libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5
	locale-gen "en_US.UTF-8"
}

prepareUbuntu26(){
	apt update || exitScript 1 "Error updating OS"
	apt install --no-install-recommends -y ca-certificates net-tools wget unzip gettext libncurses6 curl tar tzdata locales sudo mc xz-utils file libtommath1 libicu78 bsdmainutils || exitScript 1 "Error installing software"
	ln -sf libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0
	ln -sf libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5
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
		cachyos)	prepareCachyOS;;		# Hmmm... Seems, cache os has no version(s)
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
				13) prepareDebian13;;
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
				20.*)	prepareUbuntu20;;
				22.*)	prepareUbuntu22;;
				24.*)	prepareUbuntu24;;
				26.*)	prepareUbuntu26;;
				*)	echo "This version ($DISTRO_VERSION) of Ubuntu Linux is not supported";;
			esac
			;;
		zorin)
			case $VERSION in	# Ubuntu scenarios work here too
				16.*,17.1,17.2)	prepareUbuntu20;;
				17.3)		prepareUbuntu22;;
				18.*)		prepareUbuntu24;;
				*)		exitScript 1 "This version ($DISTRO_VERSION) of Ubuntu Linux is not supported";;
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
	echo "================================================================"
	echo "Extracting FB installer"
	echo "================================================================"

	mkdir $TMP_DIR/fb $TMP_DIR/conf
	tar xvf $TMP_DIR/Firebird-3*.gz -C $TMP_DIR/fb --strip-components=1 > /dev/null || exit_script 1 "Error unpacking FB archive"
	tar xvf $TMP_DIR/confv.tar.xz -C $TMP_DIR/conf > /dev/null || exit_script 1 "Error unpacking conf archive"
	echo "Extraction OK"

	echo "================================================================"
	echo "Running FB installer"
	echo "================================================================"

	cd $TMP_DIR/fb
	yes 'masterkey' | ./install.sh
	cd $OLD_DIR
	cp -rf $TMP_DIR/conf/*.conf /opt/firebird
	chown -R firebird:firebird /opt/firebird/examples/empbuild
}

setParameter(){
        local config_file=$1
        local param=$2
        local value=$3

        if [ ! -f "$config_file" ]; then
                touch "$config_file"
                echo "File $config_file not found, creating..."
        fi

        par_re="^[[:space:]]*#*[[:space:]]*${param}[[:space:]]*="

        if grep -qE "$par_re" "$config_file"; then
                sed -i "s/${par_re}.*/${param} = ${value}/" "$config_file"
                echo "Setting $param = $value"
        else
                echo "$param = ${value}" >> "$config_file"
                echo "$param parameter not found, adding..."
        fi
}

checkRoot() {
    if [ "$(id -u)" -eq 0 ]; then
        echo "Running from root."
        return 0
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        echo "User can sudo without password."
        return 0
    fi
    echo "Running from unprivileged user (UID=$(id -u))"
    return 1
}

canFirebirdWrite() {
    local dir="$1"
    # check if $dir exists
    [ -d "$dir" ] || return 1
    # Пытаемся от имени firebird создать тестовый каталог
    sudo -u firebird mkdir "$dir/.firebird_write_test_$$" 2>/dev/null && {
        sudo -u firebird rmdir "$dir/.firebird_write_test_$$" 2>/dev/null
        return 0
    }
    return 1
}

installCryptPlugin(){
	if [ ! -d $FB_ROOT ]; then
		echo "Firebird root directory $FB_ROOT not found, exiting."
		exitScript 1
	fi
	downloadFile $FTP_URL/crypt/$CRYPT_ARC $TMP_DIR "FB crypt plugin"
	mkdir $TMP_DIR/crypt
	tar xvf $TMP_DIR/$CRYPT_ARC -C $TMP_DIR/crypt --strip-components=1 > /dev/null || exitScript 1 "Error unpacking FB crypto plugin"
	# server part of the plugin (some builds have no Server/bin)
	cp -r $TMP_DIR/crypt/Server/plugins $FB_ROOT/
	
	# assemble client environment from the same archive into CryptClient
	TEMP_BASE=""

	if canFirebirdWrite "$OLD_DIR"; then
		TEMP_BASE="$OLD_DIR"
		echo "User firebird can write to '$OLD_DIR', using it..."
	else
		TEMP_BASE="${TMPDIR:-/tmp}"
		echo "User firebird can NOT write to '$OLD_DIR', using '$TEMP_BASE'..."
	fi
	# at last create client dir
	CRYPT_CLIENT_DIR="$(sudo -u firebird mktemp -d "$TEMP_BASE/crypt_client.XXXXXX")"
	echo "================================================================"
	echo "Temporary dir $CRYPT_CLIENT_DIR created"
	echo "Assembling client environment to $CRYPT_CLIENT_DIR"
	echo "================================================================"
	if [ -d $TMP_DIR/crypt/Client ]; then                                  
		rm -rf $CRYPT_CLIENT_DIR                                       
		mkdir $CRYPT_CLIENT_DIR                                        
		cp -r $TMP_DIR/crypt/Client/. $CRYPT_CLIENT_DIR               
		echo "Client environment assembled in $CRYPT_CLIENT_DIR"       
	else                                                                   
		echo "WARNING: no Client directory in crypt archive, CryptClient skipped." # <<< NEW
	fi
	echo "Setting parameter KeyHolder=$KH_STR in $FB_CONF"
	setParameter "$FB_CONF" $KH_STR KeyHolder
	startServices
	
	# deploy client test environment from the same archive and run the tests
	if [ -f "$CRYPT_CLIENT_DIR/db-crypt/run-tests.sh" ]; then
		bash "$CRYPT_CLIENT_DIR/db-crypt/run-tests.sh" || echo "WARNING: DbCrypt test run was not successful, see output above."
	else
		echo "$CRYPT_CLIENT_DIR/db-crypt/run-tests.sh not found, tests skipped."
	fi
	echo "================================================================"
	echo "Cryptoclient environment assembled in $CRYPT_CLIENT_DIR"
	echo "================================================================"
}

startServices(){
	echo "================================================================"
	echo "Restarting services"
	echo "================================================================"
	systemctl stop firebird-superserver
	systemctl start firebird-superserver
}

displayHelp(){
	echo "This program will install Firebird $FB_VER on this computer
    Command line switches:
    --debug - also install debug information, takes more traffic;
    --crypt - install and configure crypto plugin
    --crypt-only[=/path/to/firebird] - install and configure ONLY crypto plugin without Firebird"
}

# Main program actions

checkRoot || exitScript 1 "Run this script as root!"

old_count=0
param_count=$#
while [[ "$#" -gt 0 ]]; do
        old_count=$#
        case "$1" in
		"--debug"	) DEBUG=1; shift ;;
		"--crypt"	) CRYPT=1; FB_ROOT="/opt/firebird"; FB_CONF=$FB_ROOT/firebird.conf; shift;;
		"--crypt-only"	) CRYPT_ONLY=1; FB_ROOT="/opt/firebird"; FB_CONF=$FB_ROOT/firebird.conf; shift;;
                "--crypt-only="*) CRYPT_ONLY=1; FB_ROOT=$(echo "$1" | sed 's/.*=//'); FB_CONF=$FB_ROOT/firebird.conf; echo "FB_CONF=$FB_CONF"; shift ;;
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
	if [ $DEBUG -eq 1 ]; then
		downloadFile $DBG_URL $TMP_DIR "FB debug files"
		echo "Installing FB debug files"
		mkdir $TMP_DIR/debug
		tar xvf $TMP_DIR/Firebird-debuginfo-3.*.amd64.tar.gz -C $TMP_DIR/debug > /dev/null || exit_script 1 "Error unpacking FB debug info"
		cp -R $TMP_DIR/debug/opt/firebird/* $FB_ROOT
	fi
	if [ $CRYPT -eq 1 ]; then
		installCryptPlugin	# this will restart firebird itself
	else
		startServices		# or we shell restart it here 
	fi
fi

exitScript 0
