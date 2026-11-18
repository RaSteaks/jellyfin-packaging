#!/bin/bash
set -eu

output=$1
arch=$2
prefix=/usr/lib/jellyfin-ffmpeg
jobs=${JELLYFIN_BUILD_JOBS:-2}
[[ $jobs =~ ^[1-9][0-9]*$ ]] || { echo "JELLYFIN_BUILD_JOBS must be a positive integer." >&2; exit 1; }

# dpkg-buildpackage normally applies the fork's quilt series, including the
# Jellyfin filters and Rockchip changes, before invoking debian/rules.
dpkg-source --before-build .
export PKG_CONFIG_PATH=/opt/jellyfin-codecs/lib/pkgconfig
export CPPFLAGS="-I/opt/jellyfin-codecs/include"
export LDFLAGS="-L/opt/jellyfin-codecs/lib -Wl,-rpath,$prefix/lib"
configure_args=("TARGET_DIR=$prefix")
if [[ $arch == arm64 ]]; then
    # The fork's ARM64 packaging targets an amd64 cross-builder. Here the
    # compiler, codec libraries and running NAS are all native ARM64.
    configure_args+=("CONFIG_ARM64=--arch=aarch64 --enable-rkmpp --enable-rkrga")
fi
make -f debian/rules override_dh_auto_configure "${configure_args[@]}"
make -j"$jobs"
stage="$PWD/.native-install"
make DESTDIR="$stage" install-progs install-libs install-data
mv "$stage$prefix/bin/ffmpeg" "$stage$prefix/bin/ffprobe" "$stage$prefix/lib" "$output/"
if [[ -d $stage$prefix/share ]]; then
    mv "$stage$prefix/share" "$output/"
fi
cc -O2 tools/jellyfin-disc-info.c -o "$output/jellyfin-disc-info" -ldvdnav -ldvdread
ln -s /usr/bin/vainfo "$output/vainfo"
