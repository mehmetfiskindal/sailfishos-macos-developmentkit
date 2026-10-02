FROM ubuntu:22.04@sha256:b1066385161d28ddf6bc7e7b28a9170eec11484c821d1a5150d176cbde41d7f7
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential binutils cmake pkg-config p7zip-full curl ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work
