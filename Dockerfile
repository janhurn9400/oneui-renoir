# Build environment for ./build.sh: the same Ubuntu release and erofs-utils 1.9 the port is tested with.
# Runs privileged (loop mounts, overlayfs, security.* xattrs); the host kernel needs erofs and overlayfs.
FROM ubuntu:26.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash ca-certificates curl unzip xz-utils lz4 tar python3 attr file util-linux kmod \
      erofs-utils secilc openjdk-21-jre-headless zipalign apksigner \
    && rm -rf /var/lib/apt/lists/*
# apktool 3 (bundles its own aapt2): Ubuntu's 2.7 is older than the one the S23 overlay patch was made with
ARG APKTOOL=3.0.3
RUN curl -fsSLo /usr/local/lib/apktool.jar \
      https://github.com/iBotPeaches/Apktool/releases/download/v${APKTOOL}/apktool_${APKTOOL}.jar \
    && printf '#!/bin/sh\nexec java -jar /usr/local/lib/apktool.jar "$@"\n' > /usr/local/bin/apktool \
    && chmod 0755 /usr/local/bin/apktool
WORKDIR /src
