# Verification record — 2026-11-16

Changes remain uncommitted in the four original main worktrees: Server/Web/Packaging
`master`, FFmpeg `jellyfin`. Exact baseline commits are in `sources.lock.json`.
No new worktree, history rewrite, push, image publication or production deployment
was performed for this implementation. The server and Web are the matching 13.0.0
development line, not a version inferred from the production image's `latest` tag.

## Executed checks

| Check | Observed result |
| --- | --- |
| Final .NET 10.0.404 `dotnet test Jellyfin.slnx --configuration Release` | 4,270 passed, 17 skipped, 4 environment-related failures, 4,291 total |
| Encoder tests after native-index mapping change | 112 passed |
| Real Blu-ray ISO opt-in test on final assemblies | 1 passed: BDInfo/UDF and actual custom ffprobe |
| Server Release build | Passed, zero warnings/errors |
| Web Node 24: `npm run test` | 19 files, 236 tests passed |
| Web `npm run build:check` | Passed |
| Changed playback JS ESLint / action sheet Stylelint | Zero errors; one existing FIXME warning in playbackmanager |
| Web `npm run build:production` | Passed, two existing asset-size warnings |
| Packaging snapshot tests | 4 passed |
| Compose config, changed-file whitespace, authoring shell syntax | Passed |
| FFmpeg and DVD helper | Compiled from the current source on macOS; software test configuration |
| Docker image | Not built: Docker daemon socket is absent; target NAS architecture remains unspecified |

.NET tests used one MSBuild node and disabled shared compilation for this environment.
The four full-suite failures are two English/Chinese localization expectations and
two invalid-hostname DNS expectations. They also reproduced in a clean v12.4 export;
the affected implementation/tests are unchanged in the chosen main baseline. No
failure was suppressed. The opt-in media test is included in the normal skipped
count, then passed separately with its real fixture. No coverage quota or broad new
mock/test framework was introduced.

## Valid media and playback evidence

All samples are synthetic, unencrypted and disposable. No production media, database
or config was used. The final server ran at loopback port 18101 with its own data,
config and cache under `/private/tmp/jellyfin-disc-final`.

| Input or scenario | Evidence and scope |
| --- | --- |
| BDMV directory | tsMuxeR 3.1.0 authored 12-second 1080p24 H.264/AC-3 title, valid MPLS/CLPI and two chapters; BDInfo, real ffprobe and nonempty HLS output |
| Blu-ray UDF ISO | Same authored content, UDF adapter plus original image through libbluray; actual HLS output and opt-in test |
| VIDEO_TS / DVD UDF ISO | dvdauthor 0.7.2 authored two titles with different chapter lists; native dvdvideo probe reports 12.012 seconds, 360 video frames and 372 AC-3 frames; actual HLS output for directory and image |
| Equivalent IMG | Copy of the validated DVD UDF image; content identification, native playback and progress verified |
| MKV Remux | Existing regular-video route; generated H.264/AC-3 source and actual HLS output |
| DVD title state | Title 1 at 7 seconds and title 2 at 3 seconds remain separate; title 2 remembered; fresh user requires selection and has zero progress |
| Versions and parts | Explicit Extended/Theatrical directory editions plus Remux MKV; numeric part ordering, three sources, second-disc resume and remaining-parts API |
| Rescan | Renaming a synthetic MPLS required selection again; restoring its original number preserved its stable source ID and saved position |
| Web SRT | Headless WebKit rendered DVD video and the correct SRT cue after a seek to 7.466 seconds |
| ASS / external audio | Web selected ASS and commentary audio. Server burn-in output after a 6-second seek visibly contains the 7-second ASS cue; measured post-seek 880/440 Hz power ratio exceeded 180,000 in the known two-tone sidecar |
| Web cross-disc | First title finished; second disc paused for a 12-second/8-second title choice; selected second-disc title rendered at 1920x1080. 390px menu screenshot retained |
| Web continue watching | New browser session resumed Theatrical, disc 2, title 0, from its saved approximately 4.02-second position; rendered frame captured at approximately 4.15 seconds |

The added 8-second Blu-ray title was authored with tsMuxeR's explicit playlist/clip
number options and merged as valid MPLS/CLPI/M2TS files. Empty marker files are used
only in existing path-classification tests, never as playback evidence. The DVD
fixture generator was run again and its resulting ISO decoded all expected frames.

HLS segments are real media output (for example 2,152,788 bytes for the Blu-ray
sample and 504,968 bytes for DVD). These forced-profile runs transcode video; they
are **not Direct Play**. The ASS seek output additionally burns subtitles. Native
image readers never mounted or extracted a complete disc.

The isolated short-sample server used a one-second minimum resume duration; source
production defaults were unchanged. Browser automation used headless WebKit, plus
an earlier built-in-browser selection/cancel check. No Chrome or personal profile
was used. The WebKit console contains a WebSocket teardown warning and JASSUB
fontconfig fallback warnings; bundled/custom-font fidelity is not established by
these samples. Early temporary browser-driver cleanup attempts used unavailable
controls/keys; screenshots and assertions before that cleanup were retained, and
resume was verified separately. They are not represented as application failures
or as passing entire harness runs.

## Remaining limits

* Encrypted discs, menus and BD-J are excluded. No claim is made for BIN/CUE,
  MDF/MDS, NRG or arbitrary IMG contents. The tested ISO9660-only experiment was
  rejected by libdvdread and is not supported by this UDF implementation.
* Directory multi-disc grouping keeps the existing same-disc-type constraint;
  mixing DVD and Blu-ray parts in one directory stack remains independent items.
* Large commercial discs, seamless branching, alternate angles, UHD/HDR/Dolby Vision,
  complex embedded image subtitles, HD audio and every font have not been exercised.
* Acceptance targets this Web build. Other clients retain ordinary video behavior;
  clients without title selection must fail when a choice is required.
* The actual NAS architecture, hardware decoding devices/drivers, third-party
  nyanmisaka patches, installed plugins and production upgrade path were not provided
  or tested. Generic software functionality does not depend on those details; image
  architecture, hardware acceleration and production migration do.
* Docker contexts can be frozen offline for amd64 and arm64. A prepared context is
  not an image build. The official recipes still download OS/toolchain dependencies;
  this is source-repeatable, not a bit-for-bit hermetic build claim.

## Retained evidence and reproduction

`out/disc2-evidence/` contains logs, TRX files, sanitized source/runtime records,
selected screenshots, result JSON, generated fixture inputs and hashes. Credentials
and authentication files are excluded. Prepared source snapshots are archived under
`out/`; their manifests give the exact architecture, source hashes and image tags.

Use `README.md` for prepare/build/isolated Compose and migration/rollback commands.
Use the server's `DISC_PLAYBACK.md` for format and filename contracts, API/storage
changes and synthetic fixture commands. The new `DiscPlaybackStates` migration was
applied to the isolated SQLite database. Before migration preserve the entire old
data backup and old image digest; rollback restores both, never the old image against
an already migrated production database.
