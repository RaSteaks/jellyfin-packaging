FROM mcr.microsoft.com/dotnet/sdk:10.0.404@sha256:fe0fd4e93bd2fbb47c883b7a6369e5c8d3db8bf01cdc5981f6ee35fbdf3ff4fb AS dotnet
FROM node:24-trixie-slim@sha256:af02d57b57719b9657a45199a79264a9437940cd55b3c7b3fc99615654f124a0 AS node
FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2 AS codecs
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl build-essential autoconf automake libtool pkg-config \
    cmake meson ninja-build && rm -rf /var/lib/apt/lists/*
COPY install-codec-sdk.sh /tmp/
RUN bash /tmp/install-codec-sdk.sh

FROM jellyfin/jellyfin:2026111613@sha256:e9351b7367beb388a789f2dee02108cd1e86f8114654bf12bdfb9f5e4b03f81c
RUN set -eu; \
    intel_packages=""; \
    if [ "$(dpkg --print-architecture)" = amd64 ]; then \
        sed -i '/^Components:/s/main$/main non-free/' /etc/apt/sources.list.d/debian.sources; \
        intel_packages="libvpl-dev libmfx-gen1.2 intel-media-va-driver-non-free i965-va-driver"; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        git util-linux build-essential dpkg-dev patch lsb-release pkg-config \
        python3 autoconf automake libtool nasm gifsicle libpng-dev libjpeg-dev \
        clang glslang-tools libshaderc-dev libvulkan-dev libplacebo-dev \
        libffmpeg-nvenc-dev libva-dev libdrm-dev ocl-icd-opencl-dev \
        mesa-va-drivers mesa-vulkan-drivers vainfo $intel_packages \
        libass-dev libbluray-dev libdvdnav-dev libdvdread-dev libchromaprint-dev \
        libdav1d-dev libfontconfig-dev libfreetype-dev libfribidi-dev libharfbuzz-dev \
        libgmp-dev libgnutls28-dev libmp3lame-dev libopenmpt-dev libopus-dev \
        libsvtav1enc-dev libtheora-dev libvorbis-dev libvpx-dev libwebp-dev \
        libx264-dev libx265-dev libxml2-dev libzimg-dev libzvbi-dev; \
    rm -rf /var/lib/apt/lists/* /usr/lib/jellyfin-ffmpeg /jellyfin/jellyfin-web; \
    ln -s /components/current/ffmpeg /usr/lib/jellyfin-ffmpeg; \
    ln -s /components/current/web /jellyfin/jellyfin-web; \
    useradd --system --user-group --home-dir /components/.build-home \
        --no-create-home --shell /usr/sbin/nologin jellyfin-build

COPY --link --from=dotnet /usr/share/dotnet/ /usr/share/dotnet/
COPY --link --from=node /usr/local/bin/node /usr/local/bin/node
COPY --link --from=node /usr/local/include/node/ /usr/local/include/node/
COPY --link --from=node /usr/local/lib/node_modules/npm/ /usr/local/lib/node_modules/npm/
COPY --link --from=codecs /opt/jellyfin-codecs/ /opt/jellyfin-codecs/
COPY --chmod=755 entrypoint.sh update-components.sh build-server.sh build-web.sh build-ffmpeg.sh /opt/jellyfin-updater/
ENV DOTNET_ROOT=/usr/share/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    npm_config_nodedir=/usr/local \
    GIT_TERMINAL_PROMPT=0
RUN ln -s /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
 && ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
 && echo /opt/jellyfin-codecs/lib > /etc/ld.so.conf.d/jellyfin-native.conf \
 && ldconfig

# Record toolchain inputs separately to avoid rebuilding other components when
# just one compiler or its dependencies change in a later image.
RUN cd /opt/jellyfin-updater \
 && ls /usr/share/dotnet/sdk > server.toolchain \
 && sha256sum /usr/local/bin/node /usr/local/lib/node_modules/npm/package.json > web.toolchain \
 && dpkg-query -W -f='${Package}=${Version}\n' > ffmpeg.toolchain \
 && find /opt/jellyfin-codecs -type f -print0 | sort -z | xargs -0 sha256sum >> ffmpeg.toolchain
ENTRYPOINT ["/opt/jellyfin-updater/entrypoint.sh"]
