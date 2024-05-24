#!/bin/bash

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

apt update
apt install --no-install-recommends -y net-tools wget unzip gettext libncurses6 curl tar tzdata locales sudo xz-utils file libtommath1 libicu74
ln -s libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0
ln -s libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5
locale-gen "en_US.UTF-8"

download_file $FB_URL $TMP_DIR "FB installer"

echo Extracting FB installer ==================================================

mkdir $TMP_DIR/fb
tar xvf $TMP_DIR/*.gz -C $TMP_DIR/fb --strip-components=1 > /dev/null
cd $TMP_DIR/fb

echo Running FB installer =====================================================

yes 'masterkey' | ./install.sh
cd $OLD_DIR
echo -ne 'thread' | /opt/firebird/bin/changeMultiConnectMode.sh
service firebird restart 
sleep 5

# cleanup
if [ -d $TMP_DIR ]; then rm -rf $TMP_DIR; fi
