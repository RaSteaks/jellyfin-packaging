#!/bin/bash
set -eu

# Adapt the fork's Debian packaging template. It builds on amd64 and
# cross-compiles for arm64; the source commit identifies the template itself.
arch=${1:?Missing Debian architecture}
template=${2:?Missing FFmpeg Dockerfile.in}
sed -e 's|^FROM DISTRO$|FROM --platform=linux/amd64 debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2 AS package|' \
    -e "s/BUILD_ARCHITECTURE/$arch/g" -e 's/GCC_RELEASE_VERSION/14/g' \
    -e 's/LLVMSPIRVLIB_RELEASE_VERSION/19/g' -e 's/LLVM_RELEASE_VERSION/19/g' \
    -e 's|^VOLUME .*|ENV RELEASE=debian:trixie|' \
    -e '/^ENTRYPOINT /d' "$template"
cat <<'DOCKERFILE'

RUN /docker-build.sh && dpkg-deb -x /dist/deb/jellyfin-ffmpeg8_*.deb /export
FROM scratch AS ffmpeg
COPY --from=package /export/usr/lib/jellyfin-ffmpeg/ /
DOCKERFILE
