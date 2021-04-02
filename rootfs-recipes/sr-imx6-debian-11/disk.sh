#!/bin/bash -e
#
# Copyright 2020-2021 Josua Mayer <josua@solid-run.com>
#

# functions
cpio_create_at() {
	local root
	root="$1"

	cd "$root"
	cpio -H newc -o
	return $?
}

patch_initrd_uuid() {
	local INITRD=$1
	local UUID=$2
	local TEMP=`mktemp -d`
	mkdir -p "$TEMP/conf/conf.d"
	printf "ROOT=\"%s\"\n" "PARTUUID=$UUID" > "$TEMP/conf/conf.d/default_root"
	echo conf/conf.d/default_root | cpio_create_at "$TEMP" 2>/dev/null | gzip >> $INITRD
	test $? != 0 && exit 1
	rm -rf "$TEMP"
}

# kiwi state
test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

# MAIN

# configure rootfs uuid
echo "PARTUUID=$kiwi_rootpartuuid / ext4 defaults 0 1" > /etc/fstab
patch_initrd_uuid /boot/initrd.img-* $kiwi_rootpartuuid
