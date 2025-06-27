#!/bin/bash

# Please contact IBSurgeon with any question regarding this script: support@ib-aid.com
# This script is provided AS IS, without any warranty. 
# This script is licensed under IDPL https://firebirdsql.org/en/initial-developer-s-public-license-version-1-0/

FB_VER=2.5
FB_URL="https://github.com/FirebirdSQL/firebird/releases/download/R2_5_9/FirebirdCS-2.5.9.27139-0.amd64.tar.gz"
FTP_URL="https://cc.ib-aid.com/download/distr"

SYSCTL=/etc/sysctl.conf
SYS_STR="vm.max_map_count"

TMP_DIR=$(mktemp -d)
OLD_DIR=$(pwd -P)

MOD_SCRIPT=$TMP_DIR/fb/scripts/postinstall.sh
#------------------------------------------------------------------------
#  register/start/stop server using systemd

SYSTEMCTL=systemctl
SYSTEMD_DIR=/usr/lib/systemd/system
[ -d $SYSTEMD_DIR ] || SYSTEMD_DIR=/lib/systemd/system

PROC_SKT_CTRL=firebird.socket
PROC_SVC_CTRL=firebird@.service
THRD_SVC_CTRL=firebird.service

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
       0) echo "OK";;	  
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

apt update 
apt install --no-install-recommends -y net-tools libtommath1 libicu67 wget unzip gettext libncurses5 curl tar tzdata locales sudo xz-utils file apt-transport-https gpg

ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0 
locale-gen "en_US.UTF-8"

download_file $FB_URL $TMP_DIR "FB installer"
download_file $FTP_URL/$FB_VER/confv.tar.xz $TMP_DIR "FB config files"
download_file $FTP_URL/$FB_VER/systemd-files.tar.xz $TMP_DIR "Systemd support"

echo Extracting FB installer ==================================================

mkdir $TMP_DIR/fb $TMP_DIR/conf $TMP_DIR/systemd-files
tar xvf $TMP_DIR/*.gz -C $TMP_DIR/fb --strip-components=1 > /dev/null || exit_script 1 "Error unpacking FB archive"
tar xvf $TMP_DIR/confv.tar.xz -C $TMP_DIR/conf > /dev/null || exit_script 1 "Error unpacking conf archive"
tar xvf $TMP_DIR/systemd-files.tar.xz -C $TMP_DIR/systemd-files  > /dev/null || exit_script 1 "Error unpacking systemd files"

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
chown firebird:firebird /opt/firebird/firebird.conf /opt/firebird/aliases.conf
/opt/firebird/bin/changeSystemdMode.sh thread

echo Postinstall actions ======================================================

exit_script 0

