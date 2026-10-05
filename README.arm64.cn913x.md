# Debian on SolidRun Boards - 64-bit ARM

This page provides instructions for installing official [Debian from debian.org](https://www.debian.org/) on SolidRun 64-bit arm platforms.

## Supported Devices

- CN9130 SoM:
  - Clearfog Base (since Debian 13)
  - Clearfog Pro (since Debian 13)
  - CN9131 SolidWAN (since Debian 13)
- CN9132 COM-Express Type 7
  - Clearfog (since Debian 13)

## Creating Installer Media

SolidRun provides prebuilt installer disk images:

- [Debian Bookworm (13)](https://images.solid-run.com/Pure-Debian/arm64/13/)

Download an image above, decompress and write it to a suitable installation media such as USB flash drive or SD-Card, e.g. using `dd` or [etcher.io](https://etcher.io/)
The installer media **can not be used as installation destination**: E.g. when installing Debian to SD-Card, Installer must be on USB Drive.

Latest versions can always be prepared using the scripts in [this project](?tab=readme-ov-file#creating-installation-media).

## Install SoC Bootloader

CN913x product line comes preinstalled with U-Boot on SPI.

Update only in case of problems, see [CN913x U-Boot Documentation](https://github.com/SolidRun/Documentation/blob/bsp/cn913x/u-boot.md).

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

### USB Flash Drive not detected by U-Boot

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

### console stops after Starting Kernel

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

### sata drives not detected

Some sata ports fail to probe:

```
[    1.300063] ahci f2540000.sata: invalid port number 1
[    1.300067] ahci f2540000.sata: No port enabled
```

Debian 13 is still on v6.12, which ~~can't handle sata controllers that have their first port disabled~~ can handle sata controllers that have their first port disabled only since 13.7.0 release.

~~Further Linux v6.16 has introduced a new bug causing all sata ports disabled in device-tree, [fix was submitted to lkml](https://lore.kernel.org/r/20250911-cn913x-sr-fix-sata-v2-0-0d79319105f8@solid-run.com) and is awaiting review.~~

~~Upgrade to v6.14 or later, e.g. by installing `linux-image-arm64` from [Debian Backports](https://www.google.com/url?sa=t&source=web&rct=j&opi=89978449&url=https://backports.debian.org/Instructions/)~~.

~~**Resolved with Linux v6.14 or later.**~~

### Boot-loop with NVME (PCI) connected

CN9132 Clearfog boot-loops the Debian installer, when an nvme or pci card is connected to ~~either x2 or x4~~ any slot.
This is due to ~~missing support for multi-lane pci ports on the mvebu-comphy driver~~ a race condition between common clock framework and clock/phy/pci drivers, which is non-trivial to resolve.

~~Instead device-tree should remove ability to re-configure those lanes.~~

~~A [patch was submitted to lkml](https://lore.kernel.org/r/20250911-cn913x-sr-fix-sata-v2-0-0d79319105f8@solid-run.com) and is awaiting review.~~

The issue ~~is currently being discussed on [the mailing lists](https://lists.infradead.org/pipermail/linux-phy/2025-October/026249.html)~~ [has been resolved here](https://lists.infradead.org/pipermail/linux-arm-kernel/2025-October/1075501.html), the fix was applied to both master and stable.

### Can't boot from NVME (PCI)

Bootloaders built before 11/09/2025 do not automatically boot from NVME.
When OS is installed to a pci nvme drive, update according to [CN913x U-Boot Documentation](https://github.com/SolidRun/Documentation/blob/bsp/cn913x/u-boot.md).

**Resolved with u-boot builds dated 11/09/2025 or later.**

### eMMC read / write errors

On CN9132-CEX-7 only, eMMC access at high-speed modes is not stable - leading to sporadic failed transactions.
These modes should be disabled from device-tree, a [patch was submitted to lkml](https://lore.kernel.org/r/20250911-cn913x-sr-fix-sata-v2-0-0d79319105f8@solid-run.com) and is awaiting review.

### eMMC U-Boot "unable to select a mode"

**Resolved with u-boot builds dated 24/07/2024 or later.**

U-Boot can fail to access the eMMC:

```
Marvell>> mmc dev 0
unable to select a mode
switch to partitions #0, OK
mmc0(part 0) is current device
Marvell>>
```
