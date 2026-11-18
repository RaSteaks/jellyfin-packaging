FROM moby/buildkit:v0.33.1 AS buildkit
FROM jellyfin/jellyfin:2026111613@sha256:e9351b7367beb388a789f2dee02108cd1e86f8114654bf12bdfb9f5e4b03f81c

# The fork's Debian FFmpeg build embeds its absolute library and driver paths.
# Point those paths at the same generation as the server and web client.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git libdvdnav4 \
 && rm -rf /var/lib/apt/lists/* /usr/lib/jellyfin-ffmpeg /jellyfin/jellyfin-web \
 && ln -s /components/current/ffmpeg /usr/lib/jellyfin-ffmpeg \
 && ln -s /components/current/web /jellyfin/jellyfin-web
COPY --from=buildkit /usr/bin/buildctl /usr/local/bin/buildctl
COPY --chmod=755 entrypoint.sh update-components.sh /opt/jellyfin-updater/
COPY server.Dockerfile web.Dockerfile ffmpeg-recipe.sh /opt/jellyfin-updater/
ENV BUILDKIT_HOST=unix:///run/user/1000/buildkit/buildkitd.sock \
    GIT_TERMINAL_PROMPT=0
ENTRYPOINT ["/opt/jellyfin-updater/entrypoint.sh"]
