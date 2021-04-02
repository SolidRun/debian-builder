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

    sudo mkdir -p /root/.gnupg
    sudo .venv/bin/python3 ./build.py
