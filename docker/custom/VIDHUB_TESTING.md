# macOS VidHub acceptance

This is a user-run application check. Server/API and browser results do not by
themselves establish VidHub compatibility. Record the actual VidHub and macOS
versions used. Do not use the production Jellyfin database or media for this test.

## Prepare the isolated server

1. Build the current source using `README.md`, selecting the NAS/test-host
   architecture explicitly. Set the resulting image tag in `JELLYFIN_DISC_IMAGE`.
2. Set `JELLYFIN_DISC_SAMPLES` to disposable, valid media and start `compose.yaml`.
   The container listens at `http://127.0.0.1:18096` and has separate config/cache.
3. Complete setup, add the read-only samples library, and create a test user.
4. In Dashboard → Playback → Transcoding, enable **Adaptive quality for disc titles**,
   transcoding throttling and segment deletion. Start with 120 seconds for throttling
   and 300 seconds for retained segments. Permit video/audio transcoding for the user.
5. Include a BDMV or DVD with multiple actual titles and title-qualified sidecars.
   Use a sample of at least six minutes for bandwidth recovery/window tests; the
   repository's short authored fixtures are useful for basic navigation but cannot
   establish two-minute recovery behavior. Keep an ordinary MKV as a regression sample.

For a generated six-minute sample, from the server repository (full FFmpeg with
libx264 and tsMuxeR 3.1.0 are required):

```sh
bash tests/fixtures/discs/generate-bluray.sh \
  /absolute/new-fixture-directory /path/to/ffmpeg /path/to/tsMuxeR 360
```

The default without the last argument remains the 12-second fixture expected by
the existing opt-in probe test. Long fixtures include a subtitle cue at 123 seconds.

## Connect VidHub

Add a Jellyfin server in VidHub and enter `http://127.0.0.1:18096`, using the test
account. UI names vary by application version. Do not connect the test account to
the existing production service by mistake.

Open a disc's details and look for the application's media-source/version selector.
Expected entries contain the edition/part, title number and duration. Select a
specific title **inside VidHub** and play it. The expected request sends that
MediaSourceId to PlaybackInfo and uses the returned playback address. The server
will not guess a title when an ambiguous disc has no valid selection.

Check these concrete outcomes:

| Action | Expected result |
| --- | --- |
| Choose title A, then title B | Correct title/duration and title-bound subtitle tracks; no cross-title sidecar reuse |
| Select external SRT | A cue appears at the authored time; it still matches after a seek |
| Change audio / ASS where the client supports it | Correct selected track, stable timeline, and truthful remux/transcode status |
| Seek forward, stop, reopen | Resume the same version/disc/title near the saved position |
| Play an ordinary MKV | Existing normal playback remains available |
| Open a raw ISO through an explicit original-file mode | Original bytes/ranges; this does not establish title-aware HLS playback |

The new source IDs are opaque strings. If VidHub requires every source ID to be an
item GUID, never offers source selection, or discards the negotiated HLS URL, record
that behavior as a compatibility failure. Do not substitute a Web title selection
and mark the requested in-app workflow as passed.

## Optional low-bandwidth test on the Mac

The server repository includes a standard-library-only loopback proxy. For the
Compose test port, run from that repository:

```sh
python3 tests/fixtures/discs/throttle-proxy.py \
  --upstream http://127.0.0.1:18096 --port 18104 \
  --phases 20:30,2:60,15
```

Add a separate VidHub Jellyfin connection to `http://127.0.0.1:18104` using the same
test server/user. The schedule starts with the first media/bitrate-test transfer:
20 Mbps for 30 seconds, 2 Mbps for 60 seconds, then 15 Mbps. Segment requests share
one bandwidth budget, including audio and parallel video requests. API/assets and
WebSockets are not throttled. Stop and restart the proxy to reset the schedule.

Expected: when using the multi-quality HLS master, a capable client requests a lower
variant as bandwidth drops and can return to higher variants after recovery. The
client decides its own switching cadence; the Web client's two-minute policy is
not imposed on VidHub. If the client plays raw ISO/MKV bytes or pins one rendition,
this test does not prove ABR. If it offers an original/fixed-quality mode, verify
that choice separately; fixed-quality Web requests explicitly disable ABR.

The proxy binds only to loopback, does not modify system networking, stores no
credentials, and does not intentionally log authentication query strings. Do not
use it as a production reverse proxy. Its limited API surface is for local testing.

## Evidence to retain

Record the app version, sample structure/title, selected source, approximate playback
and seek times, and what the application displayed. Save a few screenshots and the
isolated server's FFmpeg logs. For ABR, look for the same PlaySessionId/MediaSourceId
with different VideoBitrate rendition requests and a shared audio rendition.

Useful failure distinctions:

- No title entries: inspect the item-details MediaSources response and the client's UI.
- Selection returns an incompatible-stream error: check the supplied source ID,
  DeviceProfile and video/audio permissions.
- Raw-file traffic instead of HLS: the client's chosen mode does not exercise this adaptation.
- HLS loads but stays in one quality: inspect the master and actual variant requests;
  the client may not enable ABR or may have fixed a level.
- Buffering with correct requests: compare transfer speed, encoded output speed and
  requested bitrate; server cache size alone cannot repair insufficient uplink.
- Resume mismatch: retain the selected source ID and reported PositionTicks.

Redact ApiKey, Authorization, access tokens and passwords before sharing logs.
When done, quit VidHub, stop the proxy and run `docker compose ... down`; this keeps
the isolated test volumes. Production migration still requires the old image and
a complete pre-migration configuration/database backup.
