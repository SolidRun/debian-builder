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
deb http://deb.debian.org/debian/ bullseye main
deb-src http://deb.debian.org/debian/ bullseye main
deb http://security.debian.org/debian-security bullseye/updates main
deb-src http://security.debian.org/debian-security bullseye/updates main
deb http://deb.debian.org/debian/ bullseye-updates main
deb-src http://deb.debian.org/debian/ bullseye-updates main

deb https://repo.solid-build.xyz/debian/bullseye/bsp-any /
deb-src https://repo.solid-build.xyz/debian/bullseye/bsp-any /
deb https://repo.solid-build.xyz/debian/bullseye/bsp-imx8v2 /
deb-src https://repo.solid-build.xyz/debian/bullseye/bsp-imx8v2 /
EOF

# configure first nic
cat > /etc/network/interfaces.d/eth0 << EOF
allow-hotplug eth0
iface eth0 inet dhcp
iface eth0 inet6 auto
EOF

# populate cnf db
apt-file update && update-command-not-found

# configure bootargs
sed -E -i "s;^LINUX_KERNEL_CMDLINE=.*$;LINUX_KERNEL_CMDLINE=\"log_level=7 net.ifnames=0\";g" "$buildroot/etc/default/flash-kernel"

# install boot-script and DTBs
env FK_MACHINE="SolidRun i.MX8MM HummingBoard Pulse" flash-kernel
env FK_MACHINE="SolidRun i.MX8MP CuBox Pulse" flash-kernel
env FK_MACHINE="SolidRun i.MX8MP HummingBoard Pulse" flash-kernel
env FK_MACHINE="SolidRun i.MX8MQ HummingBoard Pulse" flash-kernel
