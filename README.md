# Firebird Linux Installation Scripts (update 07-MAY-2026)

1-step installations scripts to install Firebird 5, 4, 3, 2.5 (vanilla or HQbird) for all popular Linux distros with OS optimizations

## Currently supported on the following distros:
AlmaLinux 10, AlmaLinux 9, Astra Linux SE 1.7, Astra Linux SE 1.8, CentOS 10, CentOS 7, CentOS 8, CentOS 9, Debian 11, Debian 12, Debian 13, openSUSE 15, Oracle Linux 10, Oracle Linux 8, Oracle Linux 9, Red OS 7, Red OS, Rocky Linux 10, Rocky Linux 8, Rocky Linux 9, Ubuntu 20, Ubuntu 22, Ubuntu 24, Ubuntu 26.
 
Do you need script for some specific distro? Contact IBSurgeon support@ib-aid.com.

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

## Continuous Integration

GitHub Actions (`.github/workflows/ci.yml`) tests the vanilla installation scripts on every push and weekly on a schedule:

* **shellcheck** — every `fb_*.sh` and `ci/*.sh` script; fails on error-level findings, reports warnings non-blocking
* **Ubuntu** — all 4 scripts on `ubuntu-26.04` (latest supported distro) and `ubuntu-latest` (currently 24.04) runners
* **Debian 13** — all 4 scripts inside a privileged `jrei/systemd-debian:13` container with systemd (no Debian runners exist)

Each install job runs the script unattended and then verifies: Firebird systemd service is active, port 3050 accepts connections, and `isql` can create, query and drop a database over TCP (SYSDBA/masterkey).

HQbird scripts are not tested in CI automatically: they download proprietary archives and register against the HQbird licensing server, so they are intended for a manually-triggered workflow.
