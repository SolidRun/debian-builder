#!/bin/bash -e
#
# Copyright 2020-2021 Josua Mayer <josua@solid-run.com>
#

test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

# create ssh keys only on first boot
rm -fv /etc/ssh/*_key*
runonce-helper add generate-ssh-keys /usr/sbin/dpkg-reconfigure openssh-server

# enable watchdog
sed -i "s;^#?RuntimeWatchdogSec=.*;RuntimeWatchdogSec=60;g" /etc/systemd/system.conf

# enable serial getty
systemctl enable serial-getty@ttymxc0.service

# choose default runlevel
systemctl set-default multi-user.target

# configure repositories
cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian/ bullseye main non-free
deb-src http://deb.debian.org/debian/ bullseye main non-free
deb http://deb.debian.org/debian-security/ bullseye-security main non-free
deb-src http://deb.debian.org/debian-security/ bullseye-security main non-free
deb http://deb.debian.org/debian/ bullseye-updates main non-free
deb-src http://deb.debian.org/debian/ bullseye-updates main non-free
EOF

# configure first nic
cat > /etc/network/interfaces.d/eth0 << EOF
allow-hotplug eth0
iface eth0 inet dhcp
iface eth0 inet6 auto
EOF

# configure missing flash-kernel entries
cat > /etc/flash-kernel/db << EOF
Machine: SolidRun Clearfog GTR L8
Kernel-Flavors: armmp
Boot-Script-Path: /boot/boot.scr
DTB-Id: armada-385-clearfog-gtr-l8.dtb
U-Boot-Script-Name: bootscr.uboot-generic
Required-Packages: u-boot-tools

Machine: SolidRun Clearfog GTR S4
Kernel-Flavors: armmp
Boot-Script-Path: /boot/boot.scr
DTB-Id: armada-385-clearfog-gtr-s4.dtb
U-Boot-Script-Name: bootscr.uboot-generic
Required-Packages: u-boot-tools
EOF

# populate cnf db
apt-file update && update-command-not-found

# configure bootargs
sed -E -i "s;^LINUX_KERNEL_CMDLINE=.*$;LINUX_KERNEL_CMDLINE=\"log_level=7 net.ifnames=0\";g" "$buildroot/etc/default/flash-kernel"

# install boot-script and DTBs
env FK_MACHINE="SolidRun Clearfog A1" flash-kernel
env FK_MACHINE="SolidRun Clearfog Base A1" flash-kernel
env FK_MACHINE="SolidRun Clearfog GTR L8" flash-kernel
env FK_MACHINE="SolidRun Clearfog GTR S4" flash-kernel
env FK_MACHINE="SolidRun Clearfog Pro A1" flash-kernel
