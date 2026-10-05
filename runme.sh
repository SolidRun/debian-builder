#!/bin/bash

# we don't have status code checks for each step - use "-e" with a trap instead
function error() {
	status=$?
	printf "ERROR: Line %i failed with status %i: %s\n" $BASH_LINENO $status "$BASH_COMMAND" >&2
	exit $status
}
trap error ERR
set -eo pipefail

BASEDIR=$(pwd)

# extend path for systems where mke2fs is in sbin
PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"

#
# Download file form URL if does not exist locally.
# Optionally with renaming.
#
# Note: Use a regular function (braces) instead of a subshell so that
# exit statuses and traps propagate to the main shell. This ensures
# `set -e` (errexit) correctly stops the script on download failures
function download() {
	local filename="$1"
	local url="$2"
	local rename="$3"

	if [ -z "${rename}" ]; then
		rename="${filename}"
	fi

	if [ -f "${BASEDIR}/download/${rename}" ]; then
		# file exists, skip
		return 0
	fi

	# download
	mkdir -p "${BASEDIR}/download"
	if ! wget -O "${BASEDIR}/download/${rename}" "${url}/${filename}"; then
		echo "Download Failed ..." >&2
		rm -f "${BASEDIR}/download/${rename}"
		return 1
	fi

	return 0
}

#
# Build installer image from hd-media tarball and iso
#
function build_hdmedia() {
	local name="$1"
	local fsname="$2"
	local size=$3
	local hdmedia="$4"
	local iso="$5"
	local rdpatch="$6"
	local offset=$((4*1024*1024)) # partition at 4M offset

	# create empty workdir
	rm -rf "${BASEDIR}/tmp"
	mkdir -p "${BASEDIR}/tmp/fs"

	# add files
	tar -C "${BASEDIR}/tmp/fs" -xf "${BASEDIR}/download/${hdmedia}"
	cp --reflink=auto "${BASEDIR}/download/${iso}" "${BASEDIR}/tmp/fs"

	# patch initrd
	if [ -n "${rdpatch}" ]; then
		cat "${rdpatch}" >> "${BASEDIR}/tmp/fs/initrd.gz"
	fi

	# create ext2 fs, size - 4M
	truncate -s $((size-offset)) "${BASEDIR}/tmp/installer.ext2"
	mke2fs -t ext2 -E root_owner=0:0 -E no_copy_xattrs -L "${fsname}" -d "${BASEDIR}/tmp/fs" "${BASEDIR}/tmp/installer.ext2"

	# create disk image, ext2 at offset 4M
	truncate -s ${offset} "${BASEDIR}/tmp/installer.img"
	cat "${BASEDIR}/tmp/installer.ext2" >> "${BASEDIR}/tmp/installer.img"

	# create partition table
	parted -s "${BASEDIR}/tmp/installer.img" -- mklabel msdos mkpart primary ext4 ${offset}B $((size-1))B

	# export result
	mkdir -p "${BASEDIR}/output"
	cp -v --reflink=auto "${BASEDIR}/tmp/installer.img" "${BASEDIR}/output/${name}"

	# clean workdir
	rm -rf "${BASEDIR}/tmp"
}

#
# Build installer image from netboot tarball and iso
# Used with arm64 port where debian is not offering hd-media tarballs.
#
function build_hdmedia_from_netboot() {
	local name="$1"
	local fsname="$2"
	local size=$3
	local netboot="$4"
	local dtbs_pkg=$5
	local offset=$((4*1024*1024)) # partition at 4M offset

	# create empty workdir
	rm -rf "${BASEDIR}/tmp"
	mkdir -p "${BASEDIR}/tmp/fs"

	# add files
	tar -C "${BASEDIR}/tmp/fs" -xf "${BASEDIR}/download/${netboot}"

	# add DTBs
	mkdir -p "${BASEDIR}/tmp/fs/dtb"
	tar -C "${BASEDIR}/tmp/fs/dtb" -xf "${dtbs_pkg}"

	# create boot-script
	mkimage -A arm -T script -C none -a 0 -e 0 -d "${BASEDIR}/src/arm64-hdmedia-boot.txt" "${BASEDIR}/tmp/fs/boot.scr"

	# create ext2 fs, size - 4M
	truncate -s $((size-offset)) "${BASEDIR}/tmp/installer.ext2"
	mke2fs -t ext2 -E root_owner=0:0 -E no_copy_xattrs -L "${fsname}" -d "${BASEDIR}/tmp/fs" "${BASEDIR}/tmp/installer.ext2"

	# create disk image, ext2 at offset 4M
	truncate -s ${offset} "${BASEDIR}/tmp/installer.img"
	cat "${BASEDIR}/tmp/installer.ext2" >> "${BASEDIR}/tmp/installer.img"

	# create partition table
	parted -s "${BASEDIR}/tmp/installer.img" -- mklabel msdos mkpart primary ext4 ${offset}B $((size-1))B

	# export result
	mkdir -p "${BASEDIR}/output"
	cp -v --reflink=auto "${BASEDIR}/tmp/installer.img" "${BASEDIR}/output/${name}"

	# clean workdir
	rm -rf "${BASEDIR}/tmp"
}

# generate device-tree tarball from kernel deb
function build_dtb_pkg() {
	local deb="$1"
	local pkg="$2"

	# create empty workdir
	rm -rf "${BASEDIR}/tmp"
	mkdir -p "${BASEDIR}/tmp"
	pushd "${BASEDIR}/tmp"

	dpkg -x "${deb}" .
	cd usr/lib/linux-image-*
	tar -cf "${pkg}" *

	# clean workdir
	popd
	rm -rf "${BASEDIR}/tmp"
}

# generate initrd withlisted kernel modules, for appenidng to installer initrd
# can e.g. supply watchdog driver into debian-installer
function build_initrd_kmod_patch() {
	local kernel="$1"
	local patch="$2"
	shift 2

	# create empty workdir
	rm -rf "${BASEDIR}/tmp"
	mkdir -p "${BASEDIR}/tmp"
	pushd "${BASEDIR}/tmp"

	dpkg -x $kernel .

	rm -f "$patch"
	mkdir -p lib/debian-installer-startup.d
	printf "#!/bin/sh\n" > lib/debian-installer-startup.d/S09-sr-modules
	for mod in $*; do
		dirname $mod >> index
		echo $mod >> index
		echo "insmod /$mod" >> lib/debian-installer-startup.d/S09-sr-modules
	done
	echo lib/debian-installer-startup.d/S09-sr-modules >> index
	cat index | cpio -R 0:0 -H newc -o | gzip > "$patch"

	# clean workdir
	popd
	rm -rf "${BASEDIR}/tmp"
}

# generate initrd withlisted kernel modules, for appenidng to installer initrd
# can e.g. supply watchdog driver into debian-installer
# variant for debian 13 or later, with /usr/ directory in initrd
function build_initrd_kmod_patch_usr() {
	local kernel="$1"
	local patch="$2"
	shift 2

	# create empty workdir
	rm -rf "${BASEDIR}/tmp"
	mkdir -p "${BASEDIR}/tmp"
	pushd "${BASEDIR}/tmp"

	dpkg -x $kernel .

	rm -f "$patch"
	mkdir -p usr/lib/debian-installer-startup.d
	printf "#!/bin/sh\n" > usr/lib/debian-installer-startup.d/S09-sr-modules
	for mod in $*; do
		dirname $mod >> index
		echo $mod >> index
		echo "insmod /$mod" >> usr/lib/debian-installer-startup.d/S09-sr-modules
	done
	echo usr/lib/debian-installer-startup.d/S09-sr-modules >> index
	cat index | cpio -R 0:0 -H newc -o | gzip > "$patch"

	# clean workdir
	popd
	rm -rf "${BASEDIR}/tmp"
}

# Debian 12 for armhf, net-install, for USB flash-drive (no bootloader)
# - Armada 388:
#   - Clearfog Base
#   - Clearfog Pro
#   - Helios-4
# - i.MX6
#   - Cubox-i
#   - HummingBoard Base
#   - HummingBoard Pro
#   - HummingBoard Gate
#   - HummingBoard Edge
#   - TODO: HummingBoard CBi
#   - TODO: SolidSense N6
function build_debian_12_armhf() {
	download linux-image-6.1.0-50-armmp_6.1.176-1_armhf.deb http://ftp.debian.org/debian/pool/main/l/linux linux-image-armmp-12.15.0.deb || return $?
	download hd-media.tar.gz http://ftp.debian.org/debian/dists/bookworm/main/installer-armhf/20230607+deb12u15/images/hd-media hd-media-12.15.0-armhf.tar.gz || return $?
	download debian-12.15.0-armhf-netinst.iso https://cdimage.debian.org/cdimage/archive/12.15.0/armhf/iso-cd debian-12.15.0-armhf-netinst.iso || return $?

	# generate initrd patch with watchdog driver
	mkdir -p ${BASEDIR}/generate
	build_initrd_kmod_patch "${BASEDIR}/download/linux-image-armmp-12.15.0.deb" "${BASEDIR}/generate/linux-image-armmp-12.15.0-kmod.cpio.gz" lib/modules/6.1.0-50-armmp/kernel/drivers/watchdog/imx2_wdt.ko || return $?

	build_hdmedia debian-12.15.0-armhf-netinst.img d-i-12.15.0-armhf $((1024*1024*1024)) hd-media-12.15.0-armhf.tar.gz debian-12.15.0-armhf-netinst.iso "${BASEDIR}/generate/linux-image-armmp-12.15.0-kmod.cpio.gz" || return $?
}

# Debian trixie for armhf, net-install, for USB flash-drive (no bootloader)
# - Armada 388:
#   - Clearfog Base
#   - Clearfog Pro
#   - Helios-4
# - i.MX6
#   - Cubox-i
#   - HummingBoard Base
#   - HummingBoard Pro
#   - HummingBoard Gate
#   - HummingBoard Edge
#   - TODO: HummingBoard CBi
#   - TODO: SolidSense N6
function build_debian_13_armhf() {
	download linux-image-6.12.107+deb13-armmp_6.12.107-1_armhf.deb http://ftp.debian.org/debian/pool/main/l/linux linux-image-armmp-13.7.0.deb || return $?
	download hd-media.tar.gz https://deb.debian.org/debian/dists/trixie/main/installer-armhf/20250803+deb13u7/images/hd-media hd-media-13.7.0-armhf.tar.gz || return $?
	download debian-13.7.0-armhf-netinst.iso https://cdimage.debian.org/cdimage/release/13.7.0/armhf/iso-cd debian-13.7.0-armhf-netinst.iso || return $?

	build_hdmedia debian-13.7.0-armhf-netinst.img d-i-13.7.0-armhf $((1024*1024*1024)) hd-media-13.7.0-armhf.tar.gz debian-13.7.0-armhf-netinst.iso "" || return $?
}

# Debian trixie for arm64, net-install, for USB flash-drive (no bootloader)
# - AM64 HummingBoard-T
# - CN9130 Clearfog Base
# - CN9130 Clearfog Pro
# - CN9131 SolidWAN
# - CN9132 Clearfog
# - LX2160 Clearfog-CX
# - LX2160 Honeycomb
# - LX2162 Clearfog
function build_debian_13_arm64() {
download linux-image-6.12.107+deb13-arm64_6.12.107-1_arm64.deb http://ftp.debian.org/debian/pool/main/l/linux-signed-arm64 linux-image-arm64-13.7.0.deb
	download hd-media.tar.gz https://deb.debian.org/debian/dists/trixie/main/installer-arm64/20250803+deb13u7/images/hd-media hd-media-13.7.0-arm64.tar.gz || return $?
	download debian-13.7.0-arm64-netinst.iso https://cdimage.debian.org/cdimage/release/13.7.0/arm64/iso-cd || return $?

	# generate initrd patch with extra drivers:
	# - lx216x:
	#   - xgmac_mdio (for emdio and pcs-phy buses)
	#   - at803x (for for on-som/com 1G ethernet phy)
	#   - phy_fsl_lynx_28g (for serdes phy)
	#   - i2c_mux, i2c_mux_pca954x (for sfp i2c bus)
	# - cn913x:
	#   - phy_mvebu_cp110_utmi (for usb phy)
	#   - pwm_fan (for cn9132 fan control): skipped to avoid fan stopping bug during installation
	mkdir -p ${BASEDIR}/generate
	build_initrd_kmod_patch_usr "${BASEDIR}/download/linux-image-arm64-13.7.0.deb" "${BASEDIR}/generate/linux-image-arm64-13.7.0-kmod.cpio.gz" \
		usr/lib/modules/6.12.107+deb13-arm64/kernel/drivers/net/ethernet/freescale/xgmac_mdio.ko.xz \
		usr/lib/modules/6.12.107+deb13-arm64/kernel/drivers/net/phy/qcom/at803x.ko.xz \
		usr/lib/modules/6.12.107+deb13-arm64/kernel/drivers/phy/freescale/phy-fsl-lynx-28g.ko.xz \
		usr/lib/modules/6.12.107+deb13-arm64/kernel/drivers/i2c/i2c-mux.ko.xz \
		usr/lib/modules/6.12.107+deb13-arm64/kernel/drivers/i2c/muxes/i2c-mux-pca954x.ko.xz \
		usr/lib/modules/6.12.107+deb13-arm64/kernel/drivers/phy/marvell/phy-mvebu-cp110-utmi.ko.xz \
		|| return $?

	build_hdmedia debian-13.7.0-arm64-netinst.img d-i-13.7.0-arm64 $((1024*1024*1024)) hd-media-13.7.0-arm64.tar.gz debian-13.7.0-arm64-netinst.iso "${BASEDIR}/generate/linux-image-arm64-13.7.0-kmod.cpio.gz" || return $?

	return 0
}

if [ $# -lt 1 ]; then
	# build everything by default
	s=0
	build_debian_12_armhf || s=$?
	build_debian_13_armhf || s=$?
	build_debian_13_arm64 || s=$?
else
	# build specified only
	s=0
	build_${1} || s=$?
fi

# end with last error coce
exit $s
