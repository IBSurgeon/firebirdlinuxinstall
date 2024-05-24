#!/usr/bin/env bash

# Please contact IBSurgeon with any question regarding this script: support@ib-aid.com
# This script is provided AS IS, without any warranty. 
# This script is licensed under IDPL https://firebirdsql.org/en/initial-developer-s-public-license-version-1-0/

FB_VER=2.5
FB_URL="https://github.com/FirebirdSQL/firebird/releases/download/R2_5_9/FirebirdCS-2.5.9.27139-0.amd64.tar.gz"
TMP_DIR=$(mktemp -d)
OLD_DIR=$(pwd -P)

download_file(){
    url=$1
    tmp=$2
    name=$3
    fname=$(basename -- "$url")

    echo "Downloading $name..."
    curl --location $url --output $tmp/$fname --progress-bar

    case $? in
      0)  echo "OK";;	  
      23) echo "Write error"
          exit 0;;
      67) echo "Wrong login / password"
              exit 0;;
      78) echo "File $url does not exist on server"
          exit 0;;
    esac
}

echo "vm.max_map_count = 256000" >> /etc/sysctl.conf
sysctl -p

yum update -y
yum install -y epel-release
yum install -y wget ncurses ncurses-compat-libs libtommath icu lsof

ln -s libtommath.so.1 /lib64/libtommath.so.0

download_file $FB_URL $TMP_DIR "FB installer"

echo Extracting FB installer ==================================================

mkdir $TMP_DIR/fb
tar xvf $TMP_DIR/*.gz -C $TMP_DIR/fb --strip-components=1 > /dev/null
cd $TMP_DIR/fb

echo Running FB installer =====================================================

yes 'masterkey' | ./install.sh
#./install.sh -silent
cd $OLD_DIR
echo -ne 'thread' | /opt/firebird/bin/changeMultiConnectMode.sh

firewall-cmd --permanent --zone=public --add-port=3050/tcp  # 4) FB RemoteServicePort
firewall-cmd --permanent --zone=public --add-port=3059/tcp  # 5) FB RemoteAuxPort
firewall-cmd --reload

# cleanup
if [ -d $TMP_DIR ]; then rm -rf $TMP_DIR; fi
