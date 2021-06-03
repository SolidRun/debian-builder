# SolidRun Debian System Image Builder

## Install runtime dependencies

    apt-get install debootstrap kpartx libxml2-dev libxslt1-dev python3-pip python3-venv qemu-utils rsync zlib1g-dev
    python3 -m venv --prompt kiwi .venv
    source .venv/bin/activate
    pip3 install wheel xmlschema
    pip3 install kiwi==v9.23.22

## Configure Images

According to the XML Schema described in *images.xsd*, ***images.xml*** describes all system images that are to be built.

## Build Images

    # optionally serve local repository for build
    python3 -m http.server -d build/repo-sr-imx8-debian-11 &

    sudo mkdir -p /root/.gnupg
    sudo .venv/bin/python3 ./images.py

## Prepare to build Packages

### Install and configure sbuild

Follow the [Debian wiki page on sbuild](https://wiki.debian.org/sbuild) to prepare:

- a chroot for each target distro (e.g. bullseye)
- apt-cacher-ng for caching dependencies
- (optionally) add foreign architectures to support cross-compiling
- (recommended) enable eatmydata
- (optionally) a ccache store

The goal is to enable building of Debian packages by invoking the sbuild command as standard user:

    sbuild --dist=bullseye --build=amd64 --host=amd64 --jobs=1 /path/to/package/source


#### TLDR CLI Commands

```
sudo sbuild-debian-developer-setup --distribution=debian --suite=bullseye

sudo sbuild-shell bullseye
# dpkg --add-architecture arm64
# dpkg --add-architecture armhf
exit

TODO:ccache
```

TODO TODO say how to invoke sbuild when it works
TODOTODO building against existing packages

### Install debarchiver

    apt-get install apt-utils debarchiver
