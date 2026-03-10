#!/usr/bin/env bash
# LogiQ aiswitch — team installer
# Run with:  bash <(curl -fsSL <your-raw-url>/install.sh)
#        or: bash install.sh   (if you have the repo checked out)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"

_info()    { printf '  \033[1;36m→\033[0m  %s\n' "$*"; }
_ok()      { printf '  \033[32m✓\033[0m  %s\n'   "$*"; }
_warn()    { printf '  \033[33m⚠\033[0m  %s\n'   "$*"; }
_section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

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

# ── 3. Copy profile files ─────────────────────────────────────────────────────

_section "Installing profile files"

for f in work-profile.json personal-profile.json; do
  src="$REPO_DIR/profiles/claude/$f"
  dst="$CLAUDE_DIR/$f"
  if [[ -f "$src" ]]; then
    cp "$src" "$dst"
    _ok "~/.claude/$f"
  else
    _warn "$src not found — skipping (use existing or create manually)"
  fi
done

for f in work-profile.toml personal-profile.toml; do
  src="$REPO_DIR/profiles/codex/$f"
  dst="$CODEX_DIR/$f"
  if [[ -f "$src" ]]; then
    cp "$src" "$dst"
    _ok "~/.codex/$f"
  else
    _warn "$src not found — skipping"
  fi
done

# ── 4. Copy aiswitch.sh ───────────────────────────────────────────────────────

_section "Installing aiswitch"

cp "$REPO_DIR/aiswitch.sh" "$CLAUDE_DIR/aiswitch.sh"
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

# ── 6. Done ──────────────────────────────────────────────────────────────────

printf '\n\033[1;32m  ✓ Installation complete!\033[0m\n\n'
printf '  Reload your shell:\n'
printf '    source %s\n\n' "$RCFILE"
printf '  Then set up API keys and profiles:\n'
printf '    aiswitch\n\n'
