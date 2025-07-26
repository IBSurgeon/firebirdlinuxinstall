#!/usr/bin/env bash

# Please contact IBSurgeon with any question regarding this script: support@ib-aid.com
# This script is provided AS IS, without any warranty. 
# This script is licensed under IDPL https://firebirdsql.org/en/initial-developer-s-public-license-version-1-0/

FB_VER=3.0
FB_URL="https://github.com/FirebirdSQL/firebird/releases/download/v3.0.13/Firebird-3.0.13.33818-0.amd64.tar.gz"
DBG_URL="https://github.com/FirebirdSQL/firebird/releases/download/v3.0.13/Firebird-debuginfo-3.0.13.33818-0.amd64.tar.gz"
FTP_URL="https://cc.ib-aid.com/download/distr/"
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

ask_question() {
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

prepare_os(){
	if grep -q $SYS_STR $SYSCTL; then
		echo "Parameter $SYS_STR already set in $SYSCTL"
	else
		echo "$SYS_STR = 256000" >> $SYSCTL
		sysctl -p
	fi
	apt update
	# bsdmainutils -- install colrm, used in main install.sh
	# libssl-dev -- library required by crypto plugin
	apt install --no-install-recommends -y net-tools libtommath1 libicu70 wget unzip gettext libncurses5 curl tar tzdata locales sudo mc xz-utils file bsdmainutils libssl-dev
	ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0
	ln -s libcrypto.so.3 /usr/lib/x86_64-linux-gnu/libcrypto.so.1.1
	locale-gen "en_US.UTF-8"
}

download_files(){
	download_file $FB_URL $TMP_DIR "FB installer"
	download_file $FTP_URL/$FB_VER/confv.tar.xz $TMP_DIR "FB config files"
}

extract_fb(){
	echo Extracting FB installer ==================================================
	mkdir $TMP_DIR/fb $TMP_DIR/conf
	tar xvf $TMP_DIR/Firebird-3*.gz -C $TMP_DIR/fb --strip-components=1 > /dev/null || exit_script 1 "Error unpacking FB archive"
	tar xvf $TMP_DIR/confv.tar.xz -C $TMP_DIR/conf > /dev/null || exit_script 1 "Error unpacking conf archive"
	echo "OK"
}

install_fb(){
	cd $TMP_DIR/fb
	echo Running FB installer =====================================================
	yes 'masterkey' | ./install.sh
	cd $OLD_DIR
	cp -rf $TMP_DIR/conf/*.conf /opt/firebird
}

install_crypt_plugin(){
	if [ ! -d $FB_ROOT/plugins ]; then
		echo "Firebird plugins directory $FB_ROOT/plugins not found, exiting."
		exit_script 1
	fi
	download_file $FTP_URL/crypt/$CRYPT_ARC $TMP_DIR "FB crypt plugin"
	mkdir $TMP_DIR/crypt
	tar xvf $TMP_DIR/$CRYPT_ARC -C $TMP_DIR/crypt --strip-components=1 > /dev/null || exit_script 1 "Error unpacking FB crypto plugin"
	cp -r $TMP_DIR/crypt/Server/{bin,plugins} $FB_ROOT
	KH_STR="KeyHolderPlugin"
	systemctl restart firebird-superserver
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
		echo "Encrypting database Employee with Red key"
		$FB_ROOT/bin/isql localhost:employee -user SYSDBA -pas masterkey <<EOF
alter database encrypt with "DbCrypt" key red;
show database;
EOF
	else
		echo "Example database $EMP_DB not found."
		echo "You can use employee database section in $DB_CONF as an example to encrypt your own database."
	fi
}

display_help(){
	echo "This program will install Firebird $FB_VER on this computer
    Command line switches:
    --debug - also install debug information, takes more traffic;
    --crypt - also install and configure crypto plugin;
    --crypt-only[=/path/to/firebird] - install and configure ONLY crypto plugin to existing Firebird installation. If no path given, script will try to install plugin to existing installation in /opt/firebird, otherwise script will install plugin to Firebird installation in specified path."
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
		"-i"|"--info"	) display_help; exit_script 0 ;;
	esac
	if [ $old_count -eq $# ]; then
		echo "Unknown parameter passed: $1"
		display_help
		exit_script 1
	fi
done

if [ $param_count -eq 0 ]; then
	display_help
	ask_question "Press Enter to start installation or ^C to abort"
fi
if [ $CRYPT_ONLY -eq 1 ]; then
	install_crypt_plugin
else
	prepare_os
	download_file $FB_URL $TMP_DIR "FB installer"
	download_file $FTP_URL/$FB_VER/confv.tar.xz $TMP_DIR "FB config files"
	extract_fb
	install_fb
	if [ $DEBUG -eq 1 ]; then
		download_file $DBG_URL $TMP_DIR "FB debug info"
		echo "Installing FB debug files"
		mkdir $TMP_DIR/debug
		tar xvf $TMP_DIR/Firebird-debuginfo-3.*.amd64.tar.gz -C $TMP_DIR/debug > /dev/null || exit_script 1 "Error unpacking FB debug info"
		cp -R $TMP_DIR/debug/opt/firebird/* $FB_ROOT
	fi
	if [ $CRYPT -eq 1 ]; then
		install_crypt_plugin
	fi
fi

exit_script 0

