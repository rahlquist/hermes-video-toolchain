# Third-Party Notices

This repository is an integration and packaging layer. It contains no third-party
source code. The components below are downloaded and installed at run time by
`install.sh`, and each retains its own license and copyright. Copyright notices
live in each upstream repository's `LICENSE` file.

## Installed by the toolchain

### OpenScreen

- **Upstream:** https://github.com/getopenscreen/openscreen
- **License:** MIT
- **Maintained by:** getopenscreen — community continuation of the project created
  by [Siddharth Vaddem](https://github.com/siddharthvaddem/openscreen), who archived
  the original after v1.5.0 and approved its continuation under the same name and
  license.
- **Installed as:** AppImage at `~/.hermes/tools/openscreen/`, exposed as
  `~/.local/bin/openscreen`, and served to Hermes over MCP.

### HyperFrames

- **Upstream:** https://github.com/heygen-com/hyperframes
- **License:** Apache-2.0
- **Maintained by:** HeyGen
- **Installed as:** npm package `hyperframes`, Chrome Headless Shell under
  `~/.cache/hyperframes/`, and skills in `~/.hermes/skills/`.

### hermes-video-editing

- **Upstream:** https://github.com/argus-metis/hermes-video-editing
- **License:** MIT
- **Maintained by:** Argus-Metis
- **Installed as:** clone at `~/.hermes/video-editing/` with an isolated venv, and
  symlinked into `~/.hermes/skills/video-editing`.

## Local patches

`patches/video-editing.py` modifies the hermes-video-editing skill **on the user's
machine**. It does not redistribute upstream code. The two changes are:

1. **Interpreter isolation** — repoints the skill's commands at the dedicated venv
   (`$PY`) instead of whatever `python` resolves to inside a Hermes session.
2. **scenedetect 0.7 compatibility** — accepts the renamed `adaptive_threshold`
   argument, and keeps AdaptiveDetector's own default threshold unless one is
   given explicitly. Offered upstream as
   [PR #2](https://github.com/argus-metis/hermes-video-editing/pull/2).

Neither change alters the upstream license.

## Used but not bundled

- [Hermes Agent](https://hermes-agent.nousresearch.com/) — the host application.
- [scenedetect](https://github.com/Breakthrough/PySceneDetect) — scene detection,
  installed into the video-editing venv as a dependency of hermes-video-editing.

## This repository

MIT — see [LICENSE](LICENSE). The integration layer (installer, router skill, and
patches) is original work; the engines above are third-party and unmodified apart
from the local patches described here.
