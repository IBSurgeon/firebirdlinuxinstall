# Firebird Linux Installation Scripts
1-step installations scripts to install Firebird 5, 4, 3, 2.5 (vanilla or HQbird) for all popular Linux distros with OS optimizations

## What these scripts do:
* Download and install prerequisites libraries and packages
* Adjust necessary OS parameters (vm.max_map_count)
* Download the latest Firebird tarball or Firebird+HQbird archives from official sources
* Install Firebird or Firebird +HQbird
* Add necessary ports to firewalls


## How to use 1-step installation script

* Download script
* make it executable
* run it

### Example for Ubuntu 22, Firebird 2.5 HQbird
```
sudo wget https://raw.githubusercontent.com/IBSurgeon/firebirdlinuxinstall/main/ubuntu22/fb_hqbird_ub22-25.sh
sudo chmod +x fb_hqbird_ub22-25.sh
sudo ./fb_hqbird_ub22-25.sh
```

### Example for CentOS7, Firebird 3.0 vanilla
```
sudo wget https://raw.githubusercontent.com/IBSurgeon/firebirdlinuxinstall/main/centos7/fb_vanilla_centos7-30.sh
sudo chmod +x fb_vanilla_centos7-30.sh
sudo ./fb_vanilla_centos7-30.sh
```
