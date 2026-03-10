#!/usr/bin/env bash
# LogiQ aiswitch — team installer
# Run with:  bash <(curl -fsSL https://raw.githubusercontent.com/alexanderkirov/aiswitch/main/install.sh)
#        or: bash install.sh   (if you have the repo checked out locally)
set -euo pipefail

_info()    { printf '  \033[1;36m→\033[0m  %s\n' "$*"; }
_ok()      { printf '  \033[32m✓\033[0m  %s\n'   "$*"; }
_warn()    { printf '  \033[33m⚠\033[0m  %s\n'   "$*"; }
_section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"

# Detect if running from pipe (e.g., curl | bash) vs local checkout
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || true)"
if [[ ! -f "$REPO_DIR/aiswitch.sh" ]]; then
  # Running from pipe - fetch from GitHub
  REMOTE_BASE="https://raw.githubusercontent.com/alexanderkirov/aiswitch/main"
  FETCH_MODE=1
else
  # Running locally
  FETCH_MODE=0
fi

_fetch_file() {
  local url="$1"
  if (( FETCH_MODE )); then
    curl -fsSL "$url"
  else
    cat "$url"
  fi
}

# ── 1. Detect shell rc file ───────────────────────────────────────────────────

_section "LogiQ aiswitch installer"
printf '  Sets up AI profile switching for Claude + Codex.\n\n'

if [[ "${SHELL:-}" == *zsh* ]]; then
  RCFILE="$HOME/.zshrc"
elif [[ "${SHELL:-}" == *bash* ]]; then
  RCFILE="$HOME/.bashrc"
else
  RCFILE="$HOME/.profile"
fi
_info "Shell RC file: $RCFILE"

# ── 2. Create ~/.claude if missing ────────────────────────────────────────────

mkdir -p "$CLAUDE_DIR" "$CODEX_DIR"

# ── 3. Install profile files ──────────────────────────────────────────────────

_section "Installing profile files"

# Claude profiles
for f in work-profile.json personal-profile.json; do
  if (( FETCH_MODE )); then
    _fetch_file "$REMOTE_BASE/profiles/claude/$f" > "$CLAUDE_DIR/$f"
  else
    cp "$REPO_DIR/profiles/claude/$f" "$CLAUDE_DIR/$f"
  fi
  _ok "~/.claude/$f"
done

# Codex profiles
for f in work-profile.toml personal-profile.toml; do
  if (( FETCH_MODE )); then
    _fetch_file "$REMOTE_BASE/profiles/codex/$f" > "$CODEX_DIR/$f"
  else
    cp "$REPO_DIR/profiles/codex/$f" "$CODEX_DIR/$f"
  fi
  _ok "~/.codex/$f"
done

# ── 4. Install aiswitch.sh ────────────────────────────────────────────────────

_section "Installing aiswitch"

if (( FETCH_MODE )); then
  _fetch_file "$REMOTE_BASE/aiswitch.sh" > "$CLAUDE_DIR/aiswitch.sh"
else
  cp "$REPO_DIR/aiswitch.sh" "$CLAUDE_DIR/aiswitch.sh"
fi
chmod 644 "$CLAUDE_DIR/aiswitch.sh"
_ok "~/.claude/aiswitch.sh"

# ── 5. Wire into shell RC ─────────────────────────────────────────────────────

_section "Configuring shell"

SOURCE_LINE='[[ -f ~/.claude/aiswitch.sh ]] && source ~/.claude/aiswitch.sh'

if grep -qF 'aiswitch.sh' "$RCFILE" 2>/dev/null; then
  _ok "$RCFILE already sources aiswitch (skipped)"
else
  printf '\n# ── LogiQ aiswitch ──────────────────────────────────────\n' >> "$RCFILE"
  printf '%s\n' "$SOURCE_LINE" >> "$RCFILE"
  _ok "Added source line to $RCFILE"
fi

# ── 6. Open a new terminal tab/window and run aiswitch ───────────────────────

printf '\n\033[1;32m  ✓ Installation complete!\033[0m\n\n'
printf '  Opening a new terminal to launch aiswitch...\n\n'

osascript -e "
tell application \"Terminal\"
  activate
  do script \"source '$RCFILE' && aiswitch\"
end tell
"
