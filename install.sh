#!/usr/bin/env bash
# =============================================================================
# Hermes Video Production Toolchain — installer
#
# Installs three OSS engines and wires them into Hermes Agent:
#   1. OpenScreen        — screen/window capture, on-device captions, GPU export
#   2. HyperFrames       — HTML/CSS/GSAP -> deterministic MP4, motion graphics
#   3. hermes-video-editing — headless post-processing + platform export
#
# Idempotent: safe to re-run. Re-running skips what is already installed.
#
# Usage:
#   bash install.sh              # full install
#   bash install.sh --core       # skip the heavy AI deps (whisper/torch)
#   bash install.sh --verify     # just verify what is present
#
# Env overrides:
#   HERMES_HOME=...             (default ~/.hermes)
#   OPENSCREEN_VERSION=2.1.2    (default: latest release)
#   NPM_GLOBAL=...              (default ~/.npm-global)
# =============================================================================
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
TOOLS_DIR="$HERMES_HOME/tools"
OPENSCREEN_DIR="$TOOLS_DIR/openscreen"
VIDEO_EDITING_DIR="$HERMES_HOME/video-editing"
NPM_GLOBAL="${NPM_GLOBAL:-$HOME/.npm-global}"

MODE="full"
case "${1:-}" in
  --core)  MODE="core" ;;
  --verify) MODE="verify" ;;
  "")      ;;
  -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
  *) echo "unknown flag: $1" >&2; exit 2 ;;
esac

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

OS="$(uname -s)"
ARCH="$(uname -m)"

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------
preflight() {
  log "Preflight"
  command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg not found — install it first (pacman -S ffmpeg / brew install ffmpeg)"
  command -v curl   >/dev/null 2>&1 || die "curl not found"
  command -v python3 >/dev/null 2>&1 || die "python3 not found"

  if [ "$OS" = "Linux" ]; then
    command -v node >/dev/null 2>&1 || die "node not found (HyperFrames needs Node 22+)"
    command -v npm  >/dev/null 2>&1 || die "npm not found"
  fi

  # Python for the video-editing venv: prefer 3.11–3.13 (best wheel support for
  # torch/opencv); 3.14 works for core but may lack wheels for some AI deps.
  PY=""
  for c in python3.13 python3.12 python3.11 python3; do
    if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
  done
  [ -n "$PY" ] || die "no usable python3 found"
  ok "ffmpeg $(ffmpeg -version 2>/dev/null | head -1 | cut -d' ' -f3)"
  ok "python $($PY --version 2>&1 | awk '{print $2}')"
  # An `if`, not `[ … ] && …`: as the last command, a false test would make the
  # function return 1 and `set -e` would abort the installer on macOS.
  if [ "$OS" = "Linux" ]; then ok "node $(node --version)"; fi
}

# -----------------------------------------------------------------------------
# 1. OpenScreen
# -----------------------------------------------------------------------------
install_openscreen() {
  log "OpenScreen"
  # Source: https://github.com/getopenscreen/openscreen  (MIT)
  mkdir -p "$OPENSCREEN_DIR"

  if [ "$OS" = "Linux" ]; then
    if command -v openscreen >/dev/null 2>&1 && openscreen --help >/dev/null 2>&1; then
      ok "already installed: $(command -v openscreen)"; return 0
    fi

    local api url ver
    api="https://api.github.com/repos/getopenscreen/openscreen/releases/latest"
    if [ -n "${OPENSCREEN_VERSION:-}" ]; then
      api="https://api.github.com/repos/getopenscreen/openscreen/releases/tags/v$OPENSCREEN_VERSION"
    fi

    url="$(curl -sL "$api" | python3 -c "
import sys, json
d = json.load(sys.stdin)
want = '${OPENSCREEN_VERSION:-}'
for a in d.get('assets', []):
    n = a.get('name', '')
    if n.endswith('.AppImage') and (not want or want in n):
        print(a['browser_download_url']); break
")"
    [ -n "$url" ] || die "could not resolve an OpenScreen .AppImage URL"
    ver="$(curl -sL "$api" | python3 -c "import sys,json;print(json.load(sys.stdin).get('tag_name','?'))")"

    log "downloading OpenScreen $ver"
    curl -sL --progress-bar -o "$OPENSCREEN_DIR/openscreen.AppImage" "$url"
    chmod +x "$OPENSCREEN_DIR/openscreen.AppImage"

    mkdir -p "$HOME/.local/bin"
    printf '#!/usr/bin/env bash\nexec "%s/openscreen.AppImage" "$@"\n' "$OPENSCREEN_DIR" \
      > "$HOME/.local/bin/openscreen"
    chmod +x "$HOME/.local/bin/openscreen"
    export PATH="$HOME/.local/bin:$PATH"

    openscreen --help >/dev/null 2>&1 \
      && ok "OpenScreen $ver -> $OPENSCREEN_DIR/openscreen.AppImage" \
      || warn "OpenScreen installed but 'openscreen --help' did not respond"

    cat <<'NOTE'

  OpenScreen on Linux needs, for native capture:
    - xdg-desktop-portal (+ a backend: -gtk, -kde, or -wlr)
    - PipeWire (for system audio)
  Without them it falls back to browser capture with fewer features.
  Verify with:  openscreen sources --json
NOTE
    return 0
  fi

  # macOS
  if [ -d "/Applications/Openscreen.app" ]; then
    ok "already installed: /Applications/Openscreen.app"; return 0
  fi
  warn "macOS: download the .dmg from https://github.com/getopenscreen/openscreen/releases"
  warn "       drag OpenScreen into /Applications, then grant Screen Recording +"
  warn "       Accessibility in System Settings > Privacy & Security."
  warn "       The CLI is /Applications/Openscreen.app/Contents/MacOS/Openscreen"
}

# -----------------------------------------------------------------------------
# 2. HyperFrames
# -----------------------------------------------------------------------------
install_hyperframes() {
  log "HyperFrames"
  # Source: https://github.com/heygen-com/hyperframes  (Apache-2.0)
  export PATH="$NPM_GLOBAL/bin:$PATH"

  if command -v hyperframes >/dev/null 2>&1; then
    ok "already installed: $(hyperframes --version 2>&1 | head -1)"
  else
    # Install into $NPM_GLOBAL (user-owned) rather than npm's default prefix,
    # which is root-owned on distro/system Node and fails with EACCES.
    npm install -g --prefix "$NPM_GLOBAL" hyperframes || die "npm install -g hyperframes failed"
  fi

  grep -q 'npm-global/bin' "$HOME/.bashrc" 2>/dev/null \
    || echo "export PATH=\"$NPM_GLOBAL/bin:\$PATH\"" >> "$HOME/.bashrc"

  hyperframes browser ensure || warn "hyperframes browser ensure failed (needed for local rendering)"
  hyperframes skills update   || warn "hyperframes skills update failed"

  # Capture first: with pipefail, a failing doctor piped into grep sent the
  # result down the "clean" branch even when ✗ lines were printed.
  local doctor_out doctor_rc=0
  doctor_out="$(hyperframes doctor 2>&1)" || doctor_rc=$?
  if printf '%s\n' "$doctor_out" | grep -E '✗' || [ "$doctor_rc" -ne 0 ]; then
    warn "hyperframes doctor reports issues (run 'hyperframes doctor' for details)"
  else
    ok "hyperframes doctor clean"
  fi
}

# -----------------------------------------------------------------------------
# 3. hermes-video-editing
# -----------------------------------------------------------------------------
install_video_editing() {
  log "hermes-video-editing"
  # Source: https://github.com/argus-metis/hermes-video-editing  (MIT)

  if [ -d "$VIDEO_EDITING_DIR/.git" ]; then
    ok "repo present at $VIDEO_EDITING_DIR"
  else
    git clone --depth 1 https://github.com/argus-metis/hermes-video-editing.git "$VIDEO_EDITING_DIR" \
      || die "clone failed"
  fi

  local py=""
  for c in python3.13 python3.12 python3.11 python3; do
    if command -v "$c" >/dev/null 2>&1; then py="$c"; break; fi
  done

  [ -d "$VIDEO_EDITING_DIR/.venv" ] || "$py" -m venv "$VIDEO_EDITING_DIR/.venv"
  local PIP="$VIDEO_EDITING_DIR/.venv/bin/pip"

  "$PIP" install --quiet --upgrade pip

  local core="moviepy ffmpeg-python opencv-python-headless Pillow numpy"
  # scenedetect >= 0.7 depends on the GUI `opencv-python`, which installs a second
  # cv2 over the headless one (and needs libGL). scenedetect-headless is the
  # same package built against opencv-python-headless.
  local ai="openai-whisper scenedetect-headless torch torchaudio"

  log "installing core deps"
  "$PIP" install --quiet $core || die "core deps failed"

  if [ "$MODE" != "core" ]; then
    # Venvs from earlier runs may hold scenedetect + opencv-python. Remove them,
    # then restore the cv2 files the uninstall shares with the headless build.
    if "$PIP" show opencv-python >/dev/null 2>&1; then
      log "replacing GUI opencv-python with the headless build"
      "$PIP" uninstall --quiet -y opencv-python scenedetect || true
      "$PIP" install --quiet --force-reinstall --no-deps opencv-python-headless \
        || die "reinstalling opencv-python-headless failed"
    fi
    log "installing AI deps (whisper, scenedetect, torch) — this is the large one"
    "$PIP" install --quiet $ai || warn "AI deps failed (core still works; captions/silence removal need these)"
  else
    warn "skipping AI deps (--core)"
  fi

  mkdir -p "$HERMES_HOME/skills"
  ln -sfn "$VIDEO_EDITING_DIR" "$HERMES_HOME/skills/video-editing"

  # Apply the interpreter + scenedetect patches (idempotent).
  if [ -f "$(dirname "$0")/patches/video-editing.py" ]; then
    python3 "$(dirname "$0")/patches/video-editing.py" "$VIDEO_EDITING_DIR" \
      || warn "patch step failed"
  fi

  "$VIDEO_EDITING_DIR/.venv/bin/python" -c "import moviepy, cv2" \
    && ok "video-editing venv ready" \
    || warn "venv import check failed"
}

# -----------------------------------------------------------------------------
# 4. Router skill
# -----------------------------------------------------------------------------
install_skill() {
  log "Router skill"
  local src; src="$(dirname "$0")/skills/video-toolchain"
  [ -d "$src" ] || { warn "skills/video-toolchain not found next to install.sh"; return 0; }
  mkdir -p "$HERMES_HOME/skills/video-toolchain"
  cp -R "$src/." "$HERMES_HOME/skills/video-toolchain/"
  ok "installed $HERMES_HOME/skills/video-toolchain/SKILL.md"
}

# -----------------------------------------------------------------------------
# 5. OpenScreen MCP wiring
# -----------------------------------------------------------------------------
wire_mcp() {
  log "OpenScreen MCP"
  local cfg="$HERMES_HOME/config.yaml"
  [ -f "$cfg" ] || { warn "no config.yaml at $cfg — add config/mcp.openscreen.yaml manually"; return 0; }

  if grep -qE '^[[:space:]]*openscreen:' "$cfg"; then
    ok "already configured in $cfg"; return 0
  fi

  python3 - "$cfg" "$HOME/.local/bin/openscreen" <<'PY'
import re, sys
path, cmd = sys.argv[1], sys.argv[2]
block = f"  openscreen:\n    command: {cmd}\n    args:\n      - mcp\n    enabled: true\n"
src = open(path).read()
lines = src.splitlines()
idx = next((i for i, l in enumerate(lines) if re.match(r'^mcp_servers:\s*$', l)), None)
if idx is None:
    if src and not src.endswith('\n'):
        src += '\n'
    src += '\nmcp_servers:\n' + block
else:
    j = idx + 1
    while j < len(lines):
        if lines[j] and not lines[j][0].isspace() and not lines[j].lstrip().startswith('#'):
            break
        j += 1
    lines.insert(j, block.rstrip('\n'))
    src = '\n'.join(lines) + '\n'
open(path, 'w').write(src)
print("wired")
PY
  ok "added mcp_servers.openscreen to $cfg"
}

# -----------------------------------------------------------------------------
# Verify
# -----------------------------------------------------------------------------
verify() {
  log "Verification"
  local fail=0

  local mac_openscreen="/Applications/Openscreen.app/Contents/MacOS/Openscreen"
  if command -v openscreen >/dev/null 2>&1 && openscreen --help >/dev/null 2>&1; then
    ok "openscreen CLI"
  elif [ "$OS" = "Darwin" ] && [ -x "$mac_openscreen" ]; then
    ok "openscreen CLI ($mac_openscreen)"
  else
    warn "openscreen CLI not responding"; fail=1
  fi

  if command -v hyperframes >/dev/null 2>&1; then
    ok "hyperframes $(hyperframes --version 2>&1 | head -1)"
  else
    warn "hyperframes not on PATH (add $NPM_GLOBAL/bin)"; fail=1
  fi

  if "$VIDEO_EDITING_DIR/.venv/bin/python" -c "import moviepy, cv2" 2>/dev/null; then
    ok "video-editing venv"
  else
    warn "video-editing venv incomplete"; fail=1
  fi

  [ -f "$HERMES_HOME/skills/video-toolchain/SKILL.md" ] \
    && ok "router skill" || { warn "router skill missing"; fail=1; }

  [ $fail -eq 0 ] && log "all engines verified" || warn "some checks failed — see above"
  return $fail
}

# -----------------------------------------------------------------------------
main() {
  preflight
  [ "$MODE" = "verify" ] && { verify; exit $?; }

  install_openscreen
  [ "$OS" = "Linux" ] && install_hyperframes
  install_video_editing
  install_skill
  wire_mcp

  echo
  verify
  echo
  log "Done. Start a new Hermes session so the MCP server and skills load."
  log "Then try:  'Record a 20s screen demo and export it as an MP4.'"
}

main "$@"
