#!/bin/bash -e
#
# Copyright 2020-2022 Josua Mayer <josua@solid-run.com>
#

test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

# create ssh keys only on first boot
rm -fv /etc/ssh/*_key*
runonce-helper add generate-ssh-keys /usr/sbin/dpkg-reconfigure openssh-server

# enable watchdog
sed -i "s;^#?RuntimeWatchdogSec=.*;RuntimeWatchdogSec=60;g" /etc/systemd/system.conf

# choose default runlevel
systemctl set-default multi-user.target

# configure repositories
cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian/ bookworm main
deb-src http://deb.debian.org/debian/ bookworm main
deb http://security.debian.org/debian-security bookworm-security main
deb-src http://security.debian.org/debian-security bookworm-security main

deb https://repo.solid-run.com/v2/debian/imx8/v3 bookworm main
deb-src https://repo.solid-run.com/v2/debian/imx8/v3 bookworm main
EOF

# configure all NICs
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
env FK_MACHINE="SolidRun CN9130 based COM Express type 7" flash-kernel
env FK_MACHINE="SolidRun CN9130 based SOM Clearfog Base" flash-kernel
env FK_MACHINE="SolidRun CN9130 based SOM Clearfog Pro" flash-kernel
env FK_MACHINE="SolidRun CN9131 based COM Express type 7" flash-kernel
env FK_MACHINE="SolidRun CN9132 based COM Express type 7" flash-kernel
