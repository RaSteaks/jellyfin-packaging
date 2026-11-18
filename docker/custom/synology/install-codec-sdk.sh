#!/bin/bash
set -euo pipefail

# Match the supplementary dependencies used by the fork's Debian FFmpeg build.
# This runs when publishing the image. NAS restarts only compile the fork itself.
prefix=/opt/jellyfin-codecs
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cd "$work"
unpack() {
    local name=$1 url=$2 checksum=$3
    curl --fail --location --retry 3 "$url" -o "$name.tar.gz"
    printf '%s  %s.tar.gz\n' "$checksum" "$name" | sha256sum -c -
    mkdir "$name"
    tar -xzf "$name.tar.gz" -C "$name" --strip-components=1
}

unpack fdk https://gitlab.freedesktop.org/wtaymans/fdk-aac-stripped/-/archive/stripped5/fdk-aac-stripped-stripped5.tar.gz \
    58d0b300fea4e98806119f3e6f3534ec1e026570aff66bbd5072412b66f14c83
(
    cd fdk
    ./autogen.sh
    ./configure --prefix="$prefix" --disable-static
    make -j4
    make install
)
case "$(dpkg --print-architecture)" in
    amd64)
        unpack amf https://github.com/GPUOpen-LibrariesAndSDKs/AMF/releases/download/v1.5.2/AMF-headers-v1.5.2.tar.gz \
            d3c12eb324edf05e214608b6a395a51dd95770ed9d45520185d6c3a206811c99
        cp -a amf/AMF "$prefix/include/"
        ;;
    arm64)
        unpack mpp https://codeload.github.com/nyanmisaka/rk-mirrors/tar.gz/848b885f95587994a53216e435f650041a894e31 \
            d5355f9962c0a610c0d02725d60118b0a64a43216818bb5e4f85c84db42b2138
        cmake -S mpp -B mpp-build -G Ninja -DCMAKE_INSTALL_PREFIX="$prefix" \
            -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DBUILD_TEST=OFF
        cmake --build mpp-build --parallel 4 && cmake --install mpp-build
        unpack rga https://codeload.github.com/nyanmisaka/rk-mirrors/tar.gz/1d330cc28551943bed3380261a5a9c6fbd58ff53 \
            30bd712507fcc6be075cd4aaa2622d46fde203fa6f3418b85d0fc1e2136b8ec4
        meson setup rga-build rga --prefix="$prefix" --libdir=lib --buildtype=release \
            --default-library=shared -Dcpp_args=-fpermissive -Dlibdrm=false -Dlibrga_demo=false
        ninja -j4 -C rga-build install
        ;;
esac
