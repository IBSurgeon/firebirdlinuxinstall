#!/usr/bin/env bash

# Please contact IBSurgeon with any question regarding this script: support@ib-aid.com
# This script is provided AS IS, without any warranty. 
# This script is licensed under IDPL https://firebirdsql.org/en/initial-developer-s-public-license-version-1-0/

FB_VER=4.0
FB_URL="https://github.com/FirebirdSQL/firebird/releases/download/v4.0.5/Firebird-4.0.5.3140-0.amd64.tar.gz"
FTP_URL="https://cc.ib-aid.com/download/distr"

SYSCTL=/etc/sysctl.conf
SYS_STR="vm.max_map_count"

TMP_DIR=$(mktemp -d)
OLD_DIR=$(pwd -P)

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

if grep -q $SYS_STR $SYSCTL; then
	echo "Parameter $SYS_STR already set in $SYSCTL"
else
	echo "$SYS_STR = 256000" >> $SYSCTL
	sysctl -p
fi

dnf update -y
dnf install -y oracle-epel-release-el9
dnf install -y tar wget mc ncurses-compat-libs libicu libtommath

ln -s libtommath.so.1 /lib64/libtommath.so.0

download_file $FB_URL $TMP_DIR "FB installer"
download_file $FTP_URL/$FB_VER/confv.tar.xz $TMP_DIR "FB config files"

echo Extracting FB installer ==================================================

mkdir $TMP_DIR/fb $TMP_DIR/conf
tar xvf $TMP_DIR/*.gz -C $TMP_DIR/fb --strip-components=1 > /dev/null || exit_script 1 "Error unpacking FB archive"
tar xvf $TMP_DIR/confv.tar.xz -C $TMP_DIR/conf > /dev/null || exit_script 1 "Error unpacking conf archive"
cd $TMP_DIR/fb

echo Running FB installer =====================================================

yes 'masterkey' | ./install.sh
cd $OLD_DIR
cp -rf $TMP_DIR/conf/*.conf /opt/firebird

firewall-cmd --permanent --zone=public --add-port=3050/tcp  # 4) FB RemoteServicePort
firewall-cmd --permanent --zone=public --add-port=3059/tcp  # 5) FB RemoteAuxPort
firewall-cmd --reload

exit_script 0

