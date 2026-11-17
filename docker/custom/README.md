# Local disc image build

This recipe builds the selected server, Web and FFmpeg source through the official
packaging Dockerfile and FFmpeg Debian build template. It does not run `checkout.py`,
reset a worktree, initialize privileged QEMU, push, deploy or modify a production
container. The matching 13.0 development Web snapshot includes disc title selection and per-disc queues.

## Prepare an immutable context

From the packaging repository, choose the target architecture explicitly. Do not
derive it from the macOS development machine. Both `amd64` and `arm64` recipes can
be prepared offline; only build the architecture you intend to deploy.

```sh
python3 docker/custom/build.py prepare \
  --arch amd64 \
  --server ../jellyfin --web ../jellyfin-web --ffmpeg ../jellyfin-ffmpeg \
  --allow-dirty --output /tmp/jellyfin-disc-build
```

Replace `amd64` with `arm64` when appropriate. `--allow-dirty` explicitly includes
reviewed uncommitted changes and unignored new files; omit it for a clean committed
release build. The output must be a new directory outside the source repositories.
The script checks baseline ancestry and matching server/Web version. It archives
the actual sibling repositories, not the packaging submodules, and records both
HEAD and a content hash. `manifest.json` contains the architecture and generated tag:

```text
rasteaks/jellyfin:13.0.0-dev-disc3-<context-sha256-first-12>-<architecture>
```

Save the entire output, not just the manifest. No commit is manufactured for dirty
sources. The context hash identifies the exact dirty snapshot. Edits after `prepare`
require another new context; `build` rejects changed snapshots.

## Build locally

Requires Docker Engine/Buildx. The upstream FFmpeg Debian toolchain runs on
`linux/amd64` and cross-builds ARM64; the builder must already support that platform.
On an Apple Silicon development machine this requires available emulation or a
Linux builder. This script never installs privileged emulation on your behalf.

```sh
python3 docker/custom/build.py build --output /tmp/jellyfin-disc-build
```

The build uses `--load`, never `--push`. Retain `build.log`, `build-metadata.json`,
`image-inspect.json`, `manifest.json` and the context. Source hashes are also image
labels and `/jellyfin/sources.json`. FFmpeg is built from the frozen custom source
and its Debian package is installed over the explicitly versioned official package.
The local revision is `8.1.3-2+disc2-trixie`. It includes `libdvdnav`, `libdvdread`,
the `dvdvideo` demuxer and `/usr/lib/jellyfin-ffmpeg/jellyfin-disc-info`. The server
expects that companion executable beside FFmpeg. Do not replace only the server
while keeping an older FFmpeg package without DVD navigation.

`sources.lock.json` fixes the four source baselines, Debian/Node image digests and
.NET SDK version. npm uses the source lockfile. Floating Rockchip and legacy Intel
driver branches in the FFmpeg recipe are pinned in that fork. OS repository packages,
upstream version tags, external driver downloads and build tools still use the
official recipes: this is **source-repeatable**, not a bit-for-bit reproducibility
claim. Fully hermetic reproduction additionally needs repository snapshots and a
verified mirror of the transitive dependency downloads. Preserve the built image
digest/archive for exact redeployment.

## Isolated test container

```sh
export JELLYFIN_DISC_IMAGE='rasteaks/jellyfin:13.0.0-dev-disc3-<hash>-amd64'
export JELLYFIN_DISC_SAMPLES='/absolute/path/to/disposable/samples'
docker compose -f docker/custom/compose.yaml config
docker compose -f docker/custom/compose.yaml up -d
```

Open `http://127.0.0.1:18096`. The container has its own name, port, config/database
volume and cache volume; media is read-only. No GPU or host networking is enabled
by default. For NAS client testing, deliberately change the bind address/port and
add the appropriate hardware devices and group permissions after checking the host.
Do not reuse production config/cache volume names or mount paths.

Check PlaybackInfo, selected source, ffmpeg command/log and client playback status.
Remux/transcode over HLS is not Direct Play. Require rendering, sync, seeks and
resume evidence, not only a successful scan or a nonempty playlist.

```sh
docker compose -f docker/custom/compose.yaml down
```

This retains the isolated test data volumes. No command here removes production data.

## Migration and rollback

Before migration record the running Jellyfin version, exact image ID/digest, plugin
versions, container mounts, UID/GID, device/group mappings and current FFmpeg build
configuration. Compare the third-party image's subtitle/playback/hardware patches
against this official-source baseline. A `latest` tag does not establish a version.

Stop the old instance before creating a consistent config/database backup, or use a
documented consistent backup method. Preserve that backup untouched and test a copy
in a separate container. Never let two instances write the same database. This branch adds the `DiscPlaybackStates` table; keep the entire database backup,
not an export of only selected tables. Check the supported upgrade path before allowing schema migration; do not start this branch
against production data as an experiment.

Rollback means stop the candidate, restore the **pre-migration data backup to a
separate restored directory**, then start the pinned old image using that restored
data. Reusing a migrated database with the old image is not a rollback plan. Retain
the original media mounts read-only during validation.

## Local checks

```sh
python3 -m unittest discover -s docker/custom -p 'test_*.py' -v
```

Snapshot safety tests need only Python and Git; Compose configuration validation
does not need a running Docker daemon. A prepared context or passing configuration
check is not a successful Docker image build. See the server's `DISC_PLAYBACK.md`
for implemented behavior and open acceptance gates.

## Adaptive disc playback (opt-in)

Enable **Adaptive quality for disc titles** in Dashboard → Playback → Transcoding.
The server must permit video and audio transcoding for the test user. Enable the
existing transcoding throttle and segment deletion options; the local validation
preset uses 120 seconds ahead and 300 seconds retained. Existing configurations are
not changed automatically. The pinned FFmpeg package remains disc2: this iteration
uses its existing encoders/navigation and changes server command generation.

Web Auto can use the multi-quality master; selecting a fixed quality sends an
explicit opt-out. The server offers compatible H.264/AAC variants and shared audio
without generating every variant at startup. Native clients control their own HLS
adaptation and cache; Web's exact timing is not a remote-control protocol.

FFmpeg 8 does not expose the runtime pause command detected by this server. When
throttling is enabled, adaptive outputs use bounded encoding windows and generate
the next window on demand. Fixed-quality playback retains the encoder's existing
throttle behavior. This is temporary streaming data, not a permanent conversion.

See [VidHub testing](VIDHUB_TESTING.md) for the user's macOS acceptance procedure
and the optional loopback bandwidth proxy. See the server's DISC_PLAYBACK.md for
source/title identity, codec constraints, and buffering behavior.
