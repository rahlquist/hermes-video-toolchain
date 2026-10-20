---
name: video-toolchain
description: Use when the user wants a finished video end-to-end — screen demo, product promo, explainer, social clip, or a post-processed edit of existing footage. Orchestrates OpenScreen (screen capture), HyperFrames (designed/animated authoring), and the hermes-video-editing skill (headless post-processing) into one pipeline. Install with the hermes-video-toolchain repo.
version: 1.0.0
platforms: [linux, macos]
metadata:
  hermes:
    tags: [Video, Production, Pipeline, OpenScreen, HyperFrames, Screen-Recording, Editing, Export, Captions]
    category: creative
    requires_toolsets: [terminal]
---

# Video Production Toolchain

Three engines, three non-overlapping jobs. Pick the right one per stage; do not
make one engine do another's job.

| Engine | Job | Reach it via |
|---|---|---|
| **OpenScreen** | Capture screen/window + mic/system audio + webcam; on-device captions; interactive polish | `mcp__openscreen__*` tools, or the `openscreen` CLI |
| **HyperFrames** | Author designed/animated motion graphics and render deterministically to MP4 | `hyperframes` CLI + the `hyperframes*` skills |
| **hermes-video-editing** | Headless post-process existing footage: trim, silence removal, reframe, stabilise, colour, platform export, audio gen, visual review | `$PY scripts/…` (see that skill) |

## When to use

- "Record a demo of this app / this PR / this change"
- "Make a promo / explainer / social clip for X"
- "Turn this footage into a TikTok / Reel / Short"
- "Add captions / cut the silences / reframe this video"
- Any request that spans more than one engine.

## Install

```bash
git clone https://github.com/rahlquist/hermes-video-toolchain.git
cd hermes-video-toolchain
bash install.sh            # full (includes whisper/torch)
bash install.sh --core     # skip the heavy AI deps
bash install.sh --verify   # check what is present
```

The installer is idempotent — re-running skips what is already there.

## Routing — decide the stages before touching a tool

| Input | Stages |
|---|---|
| Nothing yet, need a screen demo | OpenScreen capture → (optional HyperFrames overlays) → video-editing export |
| Nothing yet, need a designed promo/explainer | HyperFrames author+render → video-editing post/export |
| Existing footage, needs polish/cut/reframe | video-editing only |
| Existing footage + designed title/lower-thirds | HyperFrames overlay render → video-editing composite+export |
| Talking head → styled captions | video-editing `caption generate` (SRT) → HyperFrames `/embedded-captions` OR video-editing `caption burn` |

## Interchange — the only contract between engines

- **MP4** — the universal hand-off. Every engine reads and writes it.
- **SRT** — captions. OpenScreen writes transcripts; video-editing writes/burns SRT.
- **PNG frames / contact sheets** — visual review artifacts.
- Do **not** try to share `.openscreen` project JSON or HyperFrames `index.html`
  across engines. Those are tool-local. Render to MP4, then hand off.

## Pipelines

### A. Screen demo (OpenScreen → video-editing)

```bash
# 1. Capture headlessly (NDJSON progress on stdout)
openscreen record --duration 20 --project demo.openscreen --json
#    --display 0 | --window "Title"   --mic   --system-audio   --camera

# 2. On-device captions (Whisper, no upload)
openscreen captions demo.openscreen

# 3. Export MP4
openscreen export demo.openscreen -o demo.mp4 --json

# 4. Post-process + platform export
PY="$HOME/.hermes/video-editing/.venv/bin/python"
"$PY" ~/.hermes/video-editing/scripts/video_toolkit.py silence remove demo.mp4 -o /tmp/s1.mp4
"$PY" ~/.hermes/video-editing/scripts/video_toolkit.py edit export /tmp/s1.mp4 --preset youtube -o final.mp4
```

Prefer the **MCP tools** (`mcp__openscreen__startRecording`, `stopRecording`,
`exportVideo`, `getFrames`) when driving interactively — they return a `projectId`
and `checkpointId` and edit the live project. Use the CLI for scripts and CI.

### B. Designed promo (HyperFrames → video-editing)

```bash
# 1. Author — load the HyperFrames router skill first
#    skill_view("hyperframes")  then follow the owning workflow skill
hyperframes init promo && cd promo
hyperframes lint && hyperframes check
hyperframes render                 # → renders/*.mp4

# 2. Post-process + platform export
PY="$HOME/.hermes/video-editing/.venv/bin/python"
"$PY" ~/.hermes/video-editing/scripts/video_toolkit.py edit export \
  renders/promo_*.mp4 --preset instagram-reel -o final.mp4
```

### C. Existing footage → social clip (video-editing only)

```bash
PY="$HOME/.hermes/video-editing/.venv/bin/python"
V=~/.hermes/video-editing/scripts
"$PY" $V/video_toolkit.py silence remove in.mp4 -o /tmp/s1.mp4
"$PY" $V/video_toolkit.py enhance reframe /tmp/s1.mp4 --target 9:16 -o /tmp/s2.mp4
"$PY" $V/video_toolkit.py caption burn /tmp/s2.mp4 -o /tmp/s3.mp4
"$PY" $V/video_toolkit.py edit export /tmp/s3.mp4 --preset tiktok -o final.mp4
```

### D. Screen demo + designed lower-thirds (OpenScreen → HyperFrames → video-editing)

1. OpenScreen capture + export the clean screen take to MP4.
2. HyperFrames: author a transparent-overlay composition (lower-third, title
   card) sized to the take's aspect, render to MP4/WebM with alpha.
3. video-editing: composite the overlay onto the take with ffmpeg `overlay`,
   then export to the platform preset.

### E. Talking head → styled captions

```bash
PY="$HOME/.hermes/video-editing/.venv/bin/python"
V=~/.hermes/video-editing/scripts
# Fast path — burn plain SRT
"$PY" $V/video_toolkit.py caption burn talk.mp4 -o out.mp4
# Styled path — SRT into HyperFrames /embedded-captions for designed subtitles
"$PY" $V/video_toolkit.py caption generate talk.mp4 -o talk.srt
# then follow skill_view("hyperframes") → /embedded-captions
```

## Verification — always, before delivering

1. `video_toolkit.py info analyze OUTPUT` — duration, resolution, fps, codec,
   audio channels. Compare against the target preset.
2. `video_toolkit.py frames grid OUTPUT -o review.jpg` — then inspect with
   `vision_analyze`. Check for black frames at cuts, readable captions, correct
   framing.
3. Audio: `audio_toolkit.py waveform` / `spectrogram` → inspect, or check RMS in
   the analyze output (healthy: −20 to −6 dB).
4. If a stage's output looks wrong, fix that stage and re-run — do not stack
   corrections downstream.

## Pitfalls

- **One driver per pipeline.** OpenScreen's AI editing assistant and HyperFrames'
  agent skills both edit. Pick one per stage; never run both on the same project.
- **OpenScreen is unstable** — it documents breaking changes to the CLI and
  `.openscreen` format. Pin the version; re-check `--help` after upgrades.
- **OpenScreen needs a display + portal.** On Linux: `xdg-desktop-portal` and
  PipeWire. Without them it falls back to browser capture with fewer features.
  `openscreen sources --json` tells you what is actually available.
- **HyperFrames render needs Chrome** — `hyperframes browser ensure` once.
  Renders are deterministic; same input → same frames.
- **video-editing deps are isolated** in `~/.hermes/video-editing/.venv`. Always
  set `PY` before running its scripts; never install them into the Hermes env.
- **Background removal is not installed** by this toolchain. If `enhance bg-remove`
  reports backgroundremover missing, install it only into the venv:
  `"$HOME/.hermes/video-editing/.venv/bin/pip" install backgroundremover` — never
  with a bare `pip`, which would pollute the Hermes environment.
- **Silence removal / background removal are slow on CPU.** Warn the user before
  running them on long footage.
- **Platform presets clamp resolution and duration** — check the preset table in
  the video-editing skill before promising a length.
- **Temp files are large.** Clean up between stages; keep an eye on free disk.

## Credits

Third-party components installed by this toolchain — each retains its own license:

- **OpenScreen** (MIT) — https://github.com/getopenscreen/openscreen
- **HyperFrames** (Apache-2.0) — https://github.com/heygen-com/hyperframes
- **hermes-video-editing** (MIT) — https://github.com/argus-metis/hermes-video-editing

Full notices: [hermes-video-toolchain](https://github.com/rahlquist/hermes-video-toolchain)
→ `THIRD_PARTY_NOTICES.md`.

## Related skills

- `hyperframes` — router + capability map for HyperFrames (read first for any
  HyperFrames work).
- `video-editing` — the headless post-processing toolkit used in every pipeline.
- `media-use` (HyperFrames) — sourcing BGM, SFX, images, voice when authoring.
