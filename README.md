# Hermes Video Production Toolchain

A complete, free, open-source video production pipeline for [Hermes Agent](https://hermes-agent.nousresearch.com/) — capture, designed authoring, and headless post-processing, wired together so an agent can take a request from "make me a demo" to a finished, platform-ready MP4.

Free for personal and commercial use, with no watermarks. Optional paid cloud tiers exist — HyperFrames cloud rendering, and Runway/Shotstack in the video-editing skill — but the entire local pipeline runs without them.

## What it is

Three OSS engines, three non-overlapping jobs:

| Engine | Job | License |
|---|---|---|
| [**OpenScreen**](https://github.com/getopenscreen/openscreen) | Screen/window capture, webcam PiP, mic + system audio, cursor auto-zoom, on-device Whisper captions, GPU export | MIT |
| [**HyperFrames**](https://github.com/heygen-com/hyperframes) | HTML/CSS/GSAP → deterministic MP4: titles, lower-thirds, kinetic type, beat-synced promos, decks | Apache-2.0 |
| [**hermes-video-editing**](https://github.com/argus-metis/hermes-video-editing) | Headless post-processing: trim, silence removal, scene detection, smart reframe, stabilise, captions, platform export, audio gen | MIT |

Each is excellent at one stage. Together they cover the whole pipeline — which none does alone.

```
        ┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
        │    OpenScreen   │     │    HyperFrames   │     │ video-editing   │
        │   (capture)     │────▶│ (designed/anim)  │────▶│ (post / export) │
        └─────────────────┘     └──────────────────┘     └─────────────────┘
                    │                     │
                    └────── MP4 + SRT + PNG frames ──────┘
                            (the only interchange)
```

## Requirements

- **Hermes Agent** (the desktop app or CLI)
- **Linux** (fully automated) or **macOS** (guided)
- `ffmpeg` — all three engines
- **Node 22+** — HyperFrames
- **Python 3.11–3.13** — hermes-video-editing (3.14 works for core; some AI deps may lack wheels)
- **~7 GB free disk** for the full install (torch/OpenCV/Chrome dominate)
- Linux only: `xdg-desktop-portal` (+ a backend) and `pipewire` for native capture

## Install

```bash
git clone https://github.com/rahlquist/hermes-video-toolchain.git
cd hermes-video-toolchain
bash install.sh
```

Idempotent — re-running skips what is already installed.

```bash
bash install.sh --core      # skip whisper/torch (smaller, no captions/silence removal)
bash install.sh --verify    # check what is present without installing
```

### What it does

1. **OpenScreen** — resolves the latest release, downloads the AppImage to `~/.hermes/tools/openscreen/`, and creates a `~/.local/bin/openscreen` wrapper. (No sudo needed.)
2. **HyperFrames** — `npm install -g`, downloads Chrome Headless Shell for rendering, installs its skills into `~/.hermes/skills/`.
3. **hermes-video-editing** — clones the repo, creates an isolated Python venv (so torch/OpenCV never touch your Hermes environment), installs deps, symlinks the skill, and applies two compatibility patches.
4. **Router skill** — installs `video-toolchain` into `~/.hermes/skills/`.
5. **OpenScreen MCP** — adds the server to `~/.hermes/config.yaml` under `mcp_servers` (55 tools). The original is saved as `config.yaml.bak`; if the existing `mcp_servers` block is in a shape the installer does not recognise, it leaves the file alone and asks you to merge `config/mcp.openscreen.yaml` by hand.

Start a **new** Hermes session so the MCP server and skills load.

## Verify

```bash
openscreen sources --json          # should list your display, windows, microphones
hyperframes doctor                 # all green
hyperframes --version
~/.hermes/video-editing/.venv/bin/python -c "import moviepy, cv2; print('ok')"
```

## Use

Load the router skill, then just ask:

```
Record a 20 second demo of this app and export it as an MP4.
```

```
Make a 30 second vertical promo for our launch, with captions.
```

```
Cut the silences out of this recording and make it a TikTok.
```

The skill routes by input type and chains the engines. See `skills/video-toolchain/SKILL.md` for the routing table, five ready-made pipelines, and the interchange rules.

## Pipelines at a glance

| You want | Pipeline |
|---|---|
| Screen demo | OpenScreen capture → captions → export → platform preset |
| Product promo / explainer | HyperFrames author + render → post-process → export |
| Social clip from existing footage | video-editing only (silence removal, reframe, captions, preset) |
| Demo with designed lower-thirds | OpenScreen take + HyperFrames alpha overlay + composite |
| Styled captions on talking-head | video-editing SRT → HyperFrames `/embedded-captions` |

## Platform export presets

`instagram-reel`, `instagram-post`, `youtube`, `youtube-shorts`, `tiktok`, `twitter`, `facebook`, `telegram` — each clamps resolution, framerate, and duration.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `openscreen sources` lists nothing | Needs `xdg-desktop-portal` + a backend, and PipeWire. Check `systemctl --user is-active pipewire`. |
| `libva error: virtio_gpu_drv_video.so` | Non-fatal on VMs — falls back to software rendering. |
| `hyperframes render` fails on Chrome | Run `hyperframes browser ensure`. |
| `scenes detect` raises `TypeError` about `threshold` | The patch did not apply — re-run `bash install.sh`, or see `patches/video-editing.py`. |
| `python scripts/...` fails with `ModuleNotFoundError` | You ran the bare command. Set `PY="$HOME/.hermes/video-editing/.venv/bin/python"` first (the skill says this). |
| Disk fills up | torch + OpenCV + Chrome ≈ 7 GB. Clean scratch renders; use `--core` if you don't need AI features. |
| `enhance bg-remove` says backgroundremover is not installed | Not part of this install (large, optional). Install it into the venv: `~/.hermes/video-editing/.venv/bin/pip install backgroundremover`. Never use a bare `pip`, which targets the Hermes environment. |
| `npm install -g` warns about blocked scripts | Benign for esbuild; add `--allow-scripts=esbuild` only if a feature needs its postinstall artifacts. |

## Design notes

- **Not a Hermes plugin.** All three engines already ship the right integration surfaces (MCP server, skills, CLI). A plugin would duplicate them.
- **Interchange is MP4 + SRT + PNG.** Tool-specific project formats (`.openscreen` JSON, HyperFrames HTML) stay tool-local. Do not try to share them.
- **One driver per pipeline.** OpenScreen's AI editing assistant and HyperFrames' agent skills both edit — running both on one project double-edits.
- **Deps are isolated.** The video-editing venv is deliberately separate from the Hermes environment.

## Patches applied

The installer applies two fixes the upstream skill needs on a current machine:

1. **Interpreter isolation** — repoints the skill's commands at the dedicated venv (`$PY`) instead of whatever `python` resolves to in a Hermes session.
2. **scenedetect 0.7 compatibility** — 0.7 renamed `AdaptiveDetector`'s `threshold` to `adaptive_threshold`, which broke `scenes detect` on every call. The two are on different scales, so the patch keeps AdaptiveDetector's own default unless `--threshold` is given (upstream's 27.0 default would detect no cuts). Tracked upstream as [PR #2](https://github.com/argus-metis/hermes-video-editing/pull/2).

Both live in `patches/video-editing.py` and are idempotent.

## Contributing

Upstream fixes belong upstream. The scenedetect fix is already an open PR against `argus-metis/hermes-video-editing`; improvements to the installer or router skill belong here.

## Credits

This is an integration layer — it writes no video code of its own. It exists
because these three projects do:

| Project | Maintained by | License | Upstream |
|---|---|---|---|
| **OpenScreen** | getopenscreen — community continuation of Siddharth Vaddem's original | MIT | https://github.com/getopenscreen/openscreen |
| **HyperFrames** | HeyGen | Apache-2.0 | https://github.com/heygen-com/hyperframes |
| **hermes-video-editing** | Argus-Metis | MIT | https://github.com/argus-metis/hermes-video-editing |

Used but not bundled:

- [Hermes Agent](https://hermes-agent.nousresearch.com/) — the host agent.
- [scenedetect](https://github.com/Breakthrough/PySceneDetect) — scene detection, a
  dependency installed into the video-editing venv.

OpenScreen is the community continuation of the project created by
[Siddharth Vaddem](https://github.com/siddharthvaddem/openscreen), who archived the
original after v1.5.0 and approved its continuation under the same name and license.

Full notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

MIT — see [LICENSE](LICENSE). The three engines retain their own licenses (MIT, Apache-2.0, MIT).
