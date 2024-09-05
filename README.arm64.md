# Debian on SolidRun Boards - 64-bit ARM

This page provides instructions for installing official [Debian from debian.org](https://www.debian.org/) on SolidRun 32-bit arm platforms.

## Supported Devices

- CN9130 SoM:
  - Clearfog Base (since Debian 13)
  - Clearfog Pro (since Debian 13)
  - CN9131 SolidWAN (since Debian 13)
- CN9132 COM-Express Type 7
  - Clearfog (since Debian 13)

## Creating Installer Media

SolidRun provides prebuilt installer disk images:

- [Debian Bookworm (12)](https://images.solid-run.com/Pure-Debian/arm64/12/)

Download an image above, decompress and write it to a suitable installation media such as USB flash drive or SD-Card, e.g. using `dd` or [etcher.io](https://etcher.io/)
The installer media **can not be used as installation destination**: E.g. when installing Debian to SD-Card, Installer must be on USB Drive.

Latest versions can always be prepared using the scripts in [this project](?tab=readme-ov-file#creating-installation-media).

## Install SoC Bootloader

TBD.

## Boot Installer

- connect installation media
- connect serial console
- connect ethernet

Then power on.
U-Boot will start - showing a timeout prompt before cycling through known boot targets:

```
U-Boot 2024.04 (Jul 17 2024 - 07:26:18 +0000)

SoC:   MV88F6828-A0 at 1600 MHz
DRAM:  1 GiB (800 MHz, 32-bit, ECC not enabled)
Core:  38 devices, 22 uclasses, devicetree: separate
MMC:   mv_sdh: 0
Loading Environment from SPIFlash... SF: Detected w25q32 with page size 256 Bytes, erase size 4 KiB, total 4 MiB
OK
Model: SolidRun Clearfog A1
Board: SolidRun Clearfog Base
Net:   eth1: ethernet@70000, eth2: ethernet@30000, eth3: ethernet@34000
Hit any key to stop autoboot:  3
```

Boot targets can be inspected by printing the `boot_targets` variable from u-boot console:

```
=> print boot_targets
boot_targets=mmc0 usb0 scsi0 pxe dhcp
```

New units without an operating system on integrated storage will automatically boot into the debian installer media.
Boot of a specific media can be forced by combining a boot-target with `bootcmd_*`, e.g.:

    # boot from USB drive
    run bootcmd_usb0

## Known Issues / Workarounds

### CN9130 SoM / CN9132 CEX7

#### console stops after Starting Kernel

Console may hang without actually booting into the installer:

```
Booting the Debian installer...
## Flattened Device Tree blob at 06f00000
   Booting using the fdt blob at 0x6f00000
   Loading Ramdisk to 7d246000, end 7f5ca6e6 ... OK
   Loading Device Tree to 000000007d23c000, end 000000007d245a7f ... OK

Starting kernel ...



```

The Debian kernel image overwrites part of ramdisk during decompression,
leading to not loading any kernel modules even for console messages.

As a work-around set the u-boot variable `ramdisk_addr_r` to `0x10000000`:

```
Hit any key to stop autoboot:  0
Marvell>> print ramdisk_addr_r
ramdisk_addr_r=0x9000000
Marvell>> edit ramdisk_addr_r
edit: 0x10000000
Marvell>> saveenv
Saving Environment to SPI Flash... SF: Detected w25q64cv with page size 256 Bytes, erase size 4 KiB, total 8 MiB
Erasing SPI flash...Writing to SPI flash...done
OK
```

#### USB Flash Drive not detected by U-Boot

USB flash-drive detection by u-boot may fail while executing `run bootcmd_usb0`:

```
Starting the controller
USB XHCI 1.00
Bus usb3@510000: Register 2000120 NbrPorts 2
Starting the controller
USB XHCI 1.00
scanning bus usb3@500000 for devices... 1 USB Device(s) found
scanning bus usb3@510000 for devices... cannot reset port 2!?
1 USB Device(s) found
       scanning usb for storage devices... 0 Storage Device(s) found
```

In this case `usb reset` command can be used for retrying till the message changes to "1 Storage Device(s) found".
Afterwards booting installer can be retried with `run bootcmd_usb0`:

```
Marvell>> usb reset
resetting USB...
Bus usb3@500000: Register 2000120 NbrPorts 2
Starting the controller
USB XHCI 1.00
Bus usb3@510000: Register 2000120 NbrPorts 2
Starting the controller
USB XHCI 1.00
scanning bus usb3@500000 for devices... 2 USB Device(s) found
scanning bus usb3@510000 for devices... 1 USB Device(s) found
       scanning usb for storage devices... 1 Storage Device(s) found
Marvell>> run bootcmd_usb0
```

#### USB Flash Drive not detected by Linux

Debian Kernel is missing driver for USB-2.0 PHYs, leading to usb-2.0 and 3.0 ports failing to probe.

See also the [Debian Bug-Report](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1076934).

#### eMMC U-Boot "unable to select a mode"

**Resolved with u-boot builds dated 24/07/2024 or later.**

U-Boot can fail to access the eMMC:

```
Marvell>> mmc dev 0
unable to select a mode
switch to partitions #0, OK
mmc0(part 0) is current device
Marvell>>
```
