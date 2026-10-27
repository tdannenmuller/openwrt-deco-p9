FROM debian:12
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential clang flex bison g++ gawk gcc-multilib g++-multilib gettext git libncurses-dev \
    libssl-dev python3 python3-setuptools python3-distutils-extra rsync swig unzip zlib1g-dev file wget \
    ca-certificates curl xz-utils bzip2 patch perl libelf-dev quilt sudo \
 && rm -rf /var/lib/apt/lists/*
RUN useradd -m builder
USER builder
WORKDIR /home/builder
