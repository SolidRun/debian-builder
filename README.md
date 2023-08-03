# SolidRun Debian System Image Builder

## Package Builder

`packages.py` is a tool for automatically building debian packages and publishing them as a signed debian-compatible repository.
It uses Debian `sbuild` command to perform builds in clean auto-generated chroots, and can both cross-compile for different architectures
or fake native builds through qemu user-mode emulation.

### Configuration of the build host

The whole packagin process for Debian is closely tied to debian-specific tools.
Therefore it is recommended to start with a default installation of Debian 12 (bookworm).

#### Install required packages:

```
sudo apt-get install sbuild schroot debootstrap apt-cacher-ng devscripts debarchiver qemu-user-static software-properties-common
sudo apt-add-repository contrib
sudo apt-get install repo
```

#### Install optional packages:

Some debian packages require certain tools present on the build machine, *before handing over to `sbuild`*, e.g. to generate control files.

```
sudo apt-get install kernel-wedge python3-jinja2
```

#### Configure sbuild

Add current user to *sbuild* group:

    sudo sbuild-adduser $(id -un)

Note: after changing groups, the shell session must be logged out and logged in again to apply new memberships.

Edit `~/.sbuildrc`:

```
##############################################################################
# PACKAGE BUILD RELATED (additionally produce _source.changes)
##############################################################################
# -d
$distribution = 'unstable';
# -A
$build_arch_all = 1;
# -s
$build_source = 1;
# --source-only-changes (applicable for dput. irrelevant for dgit push-source).
$source_only_changes = 1;
# -v
$verbose = 1;
# parallel build
$ENV{'DEB_BUILD_OPTIONS'} = 'parallel=12';
##############################################################################
# POST-BUILD RELATED (turn off functionality by setting variables to 0)
##############################################################################
$run_lintian = 1;
$lintian_opts = ['-i', '-I'];
$run_piuparts = 1;
$piuparts_opts = ['--schroot', '%r-%a-sbuild', '--no-eatmydata'];
$run_autopkgtest = 0;
$autopkgtest_root_args = '';
$autopkgtest_opts = [ '--', 'schroot', '%r-%a-sbuild' ];

##############################################################################
# PERL MAGIC
##############################################################################
1;
```

Adapt especially the "parallel=" setting to the number of cores on the actual system.

#### Prepare chroot environments for package builds

##### Debian 12 amd64

```
sudo debootstrap --variant=buildd --include=eatmydata --arch=amd64 --components=main --foreign bookworm /srv/chroot/bookworm-amd64-sbuild/ http://127.0.0.1:3142/deb.debian.org/debian
sudo cp /usr/bin/qemu-x86_64-static /usr/bin/qemu-i386-static /srv/chroot/bookworm-amd64-sbuild/usr/bin/
sudo chroot /srv/chroot/bookworm-amd64-sbuild /debootstrap/debootstrap --second-stage

cat << EOF | sudo tee /etc/schroot/chroot.d/bookworm-amd64-sbuild > /dev/null
[bookworm-amd64-sbuild]
description=Debian bookworm/amd64 autobuilder
groups=root,sbuild
root-groups=root,sbuild
profile=sbuild
type=directory
directory=/srv/chroot/bookworm-amd64-sbuild
union-type=overlay
command-prefix=eatmydata
EOF
```

##### Debian 12 arm64

```
sudo debootstrap --variant=buildd --include=eatmydata --arch=arm64 --components=main --foreign bookworm /srv/chroot/bookworm-arm64-sbuild/ http://127.0.0.1:3142/deb.debian.org/debian
sudo cp /usr/bin/qemu-aarch64-static /usr/bin/qemu-arm-static /srv/chroot/bookworm-arm64-sbuild/usr/bin/
sudo chroot /srv/chroot/bookworm-arm64-sbuild /debootstrap/debootstrap --second-stage

cat << EOF | sudo tee /etc/schroot/chroot.d/bookworm-arm64-sbuild >/dev/null
[bookworm-arm64-sbuild]
description=Debian bookworm/arm64 autobuilder
groups=root,sbuild
root-groups=root,sbuild
profile=sbuild
type=directory
directory=/srv/chroot/bookworm-arm64-sbuild
union-type=overlay
command-prefix=eatmydata
EOF
```

##### Debian 12 armhf

```
sudo debootstrap --variant=buildd --include=eatmydata --arch=armhf --components=main --foreign bookworm /srv/chroot/bookworm-armhf-sbuild/ http://127.0.0.1:3142/deb.debian.org/debian
sudo cp /usr/bin/qemu-arm-static /srv/chroot/bookworm-armhf-sbuild/usr/bin/
sudo chroot /srv/chroot/bookworm-armhf-sbuild /debootstrap/debootstrap --second-stage

cat << EOF | sudo tee /etc/schroot/chroot.d/bookworm-armhf-sbuild > /dev/null
[bookworm-armhf-sbuild]
description=Debian bookworm/armhf autobuilder
groups=root,sbuild
root-groups=root,sbuild
profile=sbuild
type=directory
directory=/srv/chroot/bookworm-armhf-sbuild
union-type=overlay
command-prefix=eatmydata
EOF
```

##### Debian 11 amd64

```
sudo debootstrap --variant=buildd --include=eatmydata --arch=arm64 --components=main --foreign bullseye /srv/chroot/bullseye-amd64-sbuild/ http://127.0.0.1:3142/deb.debian.org/debian
sudo cp /usr/bin/qemu-x86_64-static /usr/bin/qemu-i386-static /srv/chroot/bullseye-amd64-sbuild/usr/bin/
sudo chroot /srv/chroot/bullseye-amd64-sbuild /debootstrap/debootstrap --second-stage

cat << EOF | sudo tee /etc/schroot/chroot.d/bullseye-amd64-sbuild > /dev/null
[bullseye-amd64-sbuild]
description=Debian bullseye/amd64 autobuilder
groups=root,sbuild
root-groups=root,sbuild
profile=sbuild
type=directory
directory=/srv/chroot/bullseye-amd64-sbuild
union-type=overlay
command-prefix=eatmydata
EOF
```

##### Debian 11 arm64

```
sudo debootstrap --variant=buildd --include=eatmydata --arch=arm64 --components=main --foreign bullseye /srv/chroot/bullseye-arm64-sbuild/ http://127.0.0.1:3142/deb.debian.org/debian
sudo cp /usr/bin/qemu-aarch64-static /usr/bin/qemu-arm-static /srv/chroot/bullseye-arm64-sbuild/usr/bin/
sudo chroot /srv/chroot/bullseye-arm64-sbuild /debootstrap/debootstrap --second-stage

cat << EOF | sudo tee /etc/schroot/chroot.d/bullseye-arm64-sbuild > /dev/null
[bullseye-arm64-sbuild]
description=Debian bullseye/arm64 autobuilder
groups=root,sbuild
root-groups=root,sbuild
profile=sbuild
type=directory
directory=/srv/chroot/bullseye-arm64-sbuild
union-type=overlay
command-prefix=eatmydata
EOF
```

##### Debian 11 armhf

```
sudo debootstrap --variant=buildd --include=eatmydata --arch=armhf --components=main --foreign bullseye /srv/chroot/bullseye-armhf-sbuild/ http://127.0.0.1:3142/deb.debian.org/debian
sudo cp /usr/bin/qemu-arm-static /srv/chroot/bullseye-armhf-sbuild/usr/bin/
sudo chroot /srv/chroot/bullseye-armhf-sbuild /debootstrap/debootstrap --second-stage

cat << EOF | sudo tee /etc/schroot/chroot.d/bullseye-armhf-sbuild > /dev/null
[bullseye-armhf-sbuild]
description=Debian bullseye/armhf autobuilder
groups=root,sbuild
root-groups=root,sbuild
profile=sbuild
type=directory
directory=/srv/chroot/bullseye-armhf-sbuild
union-type=overlay
command-prefix=eatmydata
EOF
```

##### Debian 10 amd64

```
sudo debootstrap --variant=buildd --include=eatmydata --arch=amd64 --components=main --foreign buster /srv/chroot/buster-amd64-sbuild/ http://127.0.0.1:3142/deb.debian.org/debian
sudo cp /usr/bin/qemu-x86_64-static /usr/bin/qemu-i386-static /srv/chroot/buster-amd64-sbuild/usr/bin/
sudo chroot /srv/chroot/buster-amd64-sbuild /debootstrap/debootstrap --second-stage

cat << EOF | sudo tee /etc/schroot/chroot.d/buster-amd64-sbuild > /dev/null
[buster-amd64-sbuild]
description=Debian buster/amd64 autobuilder
groups=root,sbuild
root-groups=root,sbuild
profile=sbuild
type=directory
directory=/srv/chroot/buster-amd64-sbuild
union-type=overlay
command-prefix=eatmydata
EOF
```

##### Debian 10 arm64

```
sudo debootstrap --variant=buildd --include=eatmydata --arch=arm64 --components=main --foreign buster /srv/chroot/buster-arm64-sbuild/ http://127.0.0.1:3142/deb.debian.org/debian
sudo cp /usr/bin/qemu-aarch64-static /usr/bin/qemu-arm-static /srv/chroot/buster-arm64-sbuild/usr/bin/
sudo chroot /srv/chroot/buster-arm64-sbuild /debootstrap/debootstrap --second-stage

cat << EOF | sudo tee /etc/schroot/chroot.d/buster-arm64-sbuild > /dev/null
[buster-arm64-sbuild]
description=Debian buster/arm64 autobuilder
groups=root,sbuild
root-groups=root,sbuild
profile=sbuild
type=directory
directory=/srv/chroot/buster-arm64-sbuild
union-type=overlay
command-prefix=eatmydata
EOF
```

##### Debian 10 armhf

```
sudo debootstrap --variant=buildd --include=eatmydata --arch=armhf --components=main --foreign buster /srv/chroot/buster-armhf-sbuild/ http://127.0.0.1:3142/deb.debian.org/debian
sudo cp /usr/bin/qemu-arm-static /srv/chroot/buster-armhf-sbuild/usr/bin/
sudo chroot /srv/chroot/buster-armhf-sbuild /debootstrap/debootstrap --second-stage

cat << EOF | sudo tee /etc/schroot/chroot.d/buster-armhf-sbuild > /dev/null
[buster-armhf-sbuild]
description=Debian buster/armhf autobuilder
groups=root,sbuild
root-groups=root,sbuild
profile=sbuild
type=directory
directory=/srv/chroot/buster-armhf-sbuild
union-type=overlay
command-prefix=eatmydata
EOF
```

### Build some packages

Packages can be generated from sources listed in the subdirectories below `package-recipes/`.
Each subdirectory may contain:

- manifest.xml (to fetch package sources using "repo" command)
- download.list (to fetch package sources using http download)

To cross-build for example packages for Armada 388 Debian 11 (`package-recipes/sr-a38x-debian-11`) on amd64 architecture:

    ./packages.py -c sr-imx6-debian-11 -r bullseye -a armhf -b amd64

## Image Builder

`images.py` uses [kiwi-ng](https://osinside.github.io/kiwi/) to bootstrap a debian rootfs and then pack a bootable disk image.

There are two places for configuration of specific images:

- `rootfs-recipes/*`: The kiwi-ng configuration: Repositories, software selection, post-install steps and filesystem creation.

- `imagex.xml`: The `images.py` configuration: image name -> kiwi configuration mapping, block device offsets and binary blobs.


### Install runtime dependencies

    apt-get install debootstrap fdisk kpartx libxml2-dev libxslt1-dev python3-pip python3-venv qemu-utils rsync zlib1g-dev
    python3 -m venv --copies --prompt kiwi .venv
    source .venv/bin/activate
    pip3 install wheel xmlschema
    pip3 install kiwi==v9.23.22
    sudo mkdir -p /root/.gnupg

### Build an actual Image

    # optionally serve local repository of custom packages
    python3 -m http.server -d build/repo-sr-imx8-debian-11 &

    # clean artifacts from previous build
    sudo rm -rf build/cache build/debug.log build/sr-imx8-debian-buster-imx8mm-hummingboard-pulse

    # build an image by its xml name property
    sudo .venv/bin/python3 ./images.py sr-imx8-debian-buster-imx8mm-hummingboard-pulse
