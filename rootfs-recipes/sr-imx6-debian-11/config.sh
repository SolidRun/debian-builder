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
deb http://security.debian.org/debian-security bullseye-security main
deb-src http://security.debian.org/debian-security bullseye-security main

deb https://repo.solid-run.com/v2/debian/imx6/v3 bullseye main non-free
deb-src https://repo.solid-run.com/v2/debian/imx6/v3 bullseye main non-free
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
sed -E -i "s;^LINUX_KERNEL_CMDLINE=.*$;LINUX_KERNEL_CMDLINE=\"deferred_probe_timeout=10 ahci_imx.hotplug=1 cma=128M log_level=7 net.ifnames=0\";g" "$buildroot/etc/default/flash-kernel"

# install boot-script and DTBs
env FK_MACHINE="SolidRun Cubox-i Solo/DualLite" flash-kernel
env FK_MACHINE="SolidRun Cubox-i Solo/DualLite (1.5som+emmc)" flash-kernel
env FK_MACHINE="SolidRun Cubox-i Solo/DualLite (1.5som)" flash-kernel
env FK_MACHINE="SolidRun Cubox-i Dual/Quad" flash-kernel
env FK_MACHINE="SolidRun Cubox-i Dual/Quad (1.5som+emmc)" flash-kernel
env FK_MACHINE="SolidRun Cubox-i Dual/Quad (1.5som)" flash-kernel
env FK_MACHINE="SolidRun HummingBoard2 Solo/DualLite" flash-kernel
env FK_MACHINE="SolidRun HummingBoard2 Solo/DualLite (1.5som+emmc)" flash-kernel
env FK_MACHINE="SolidRun HummingBoard2 Solo/DualLite (1.5som)" flash-kernel
env FK_MACHINE="SolidRun HummingBoard Solo/DualLite" flash-kernel
env FK_MACHINE="SolidRun HummingBoard Solo/DualLite (1.5som+emmc)" flash-kernel
env FK_MACHINE="SolidRun HummingBoard Solo/DualLite (1.5som)" flash-kernel
env FK_MACHINE="SolidRun HummingBoard2 Dual/Quad" flash-kernel
env FK_MACHINE="SolidRun HummingBoard2 Dual/Quad (1.5som+emmc)" flash-kernel
env FK_MACHINE="SolidRun HummingBoard2 Dual/Quad (1.5som)" flash-kernel
env FK_MACHINE="SolidRun HummingBoard Dual/Quad" flash-kernel
env FK_MACHINE="SolidRun HummingBoard Dual/Quad (1.5som+emmc)" flash-kernel
env FK_MACHINE="SolidRun HummingBoard Dual/Quad (1.5som)" flash-kernel
