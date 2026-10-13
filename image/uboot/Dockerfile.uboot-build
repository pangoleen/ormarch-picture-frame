FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential gcc-arm-linux-gnueabihf bison flex bc libssl-dev libgnutls28-dev \
    python3 python3-dev python3-setuptools python3-pyelftools swig device-tree-compiler u-boot-tools \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
