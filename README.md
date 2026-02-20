# Firebird Linux Installation Scripts (update 20-FEB-2026)

1-step installations scripts to install Firebird 5, 4, 3, 2.5 (vanilla or HQbird) for all popular Linux distros with OS optimizations

## Currently supported on the following distros:
AlmaLinux 10, AlmaLinux 9, Astra Linux SE 1.7, Astra Linux SE 1.8, CentOS 10, CentOS 7, CentOS 8, CentOS 9, Debian 11, Debian 12, openSUSE 15, Oracle Linux 10, Oracle Linux 8, Oracle Linux 9, Red OS 7, Red OS, Rocky Linux 10, Rocky Linux 8, Rocky Linux 9, Ubuntu 20, Ubuntu 22, Ubuntu 24.
 
Do you need script for some specific distro? Contact IBSurgeon support@iv-aid.com.

## What these scripts do:
* Download and install prerequisites libraries and packages
* Adjust necessary OS parameters
* Download the latest Firebird tarball or Firebird+HQbird archives from official sources
* Install Firebird or Firebird +HQbird
* Add necessary ports to firewalls


## How to use 1-step installation script

* Download script
* make it executable
* run it

### Example for Firebird 5.0 HQbird (for all supported Linux versions)
```
sudo wget https://raw.githubusercontent.com/IBSurgeon/firebirdlinuxinstall/refs/heads/main/fb_hqbird-50.sh
sudo chmod +x fb_hqbird-50.sh
sudo ./fb_hqbird-50.sh
```

### Example for Firebird 3.0 vanilla  (for all supported Linux versions)
```
sudo wget https://raw.githubusercontent.com/IBSurgeon/firebirdlinuxinstall/refs/heads/main/fb_vanilla-30.sh
sudo chmod +x fb_vanilla-30.sh
sudo ./fb_vanilla-30.sh
```

## Where are old versions?
They are in old_version folder https://github.com/IBSurgeon/firebirdlinuxinstall/tree/main/old_version
