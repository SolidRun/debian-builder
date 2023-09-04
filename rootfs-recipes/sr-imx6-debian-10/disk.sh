#!/bin/bash -e
#
# Copyright 2020-2021 Josua Mayer <josua@solid-run.com>
#

# kiwi state
test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

# MAIN

# configure rootfs uuid
echo "PARTUUID=$kiwi_rootpartuuid / ext4 defaults 0 1" > /etc/fstab

# regenerate initramfs to include rootfs part-uuid
# (requires final fstab, must run in disk.sh)
KVER=$(readlink /boot/vmlinuz | sed -e "s;^vmlinuz-;;g")
update-initramfs -u -k $KVER

sync
