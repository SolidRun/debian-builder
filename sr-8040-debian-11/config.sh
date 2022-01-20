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
systemctl enable serial-getty@ttyS0.service

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

# configure all NICs (which one a customer chooses is unpredictable)
cat > /etc/network/interfaces.d/eth0 << EOF
allow-hotplug eth0
iface eth0 inet dhcp
iface eth0 inet6 auto
EOF
cat > /etc/network/interfaces.d/eth1 << EOF
allow-hotplug eth1
iface eth1 inet dhcp
iface eth1 inet6 auto
EOF
cat > /etc/network/interfaces.d/eth2 << EOF
allow-hotplug eth2
iface eth2 inet dhcp
iface eth2 inet6 auto
EOF

# populate cnf db
apt-file update && update-command-not-found

# configure bootargs
sed -E -i "s;^LINUX_KERNEL_CMDLINE=.*$;LINUX_KERNEL_CMDLINE=\"log_level=7 net.ifnames=0\";g" "$buildroot/etc/default/flash-kernel"

# install boot-script and DTBs
env FK_MACHINE="Marvell 8040 MACCHIATOBin Double-shot" flash-kernel
env FK_MACHINE="Marvell 8040 MACCHIATOBin Single-shot" flash-kernel
env FK_MACHINE="SolidRun ClearFog GT 8K" flash-kernel
