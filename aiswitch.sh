# ── aiswitch — AI tool profile switcher ───────────────────────────────────────
# Switches work/personal profiles for Claude and Codex (CLI + Mac apps).
# API keys are stored in macOS Keychain; injected into config files on switch.
#
# Usage:
#   aiswitch                              ← interactive wizard (no args)
#   aiswitch work    [claude|codex|all]   ← switch to work profile
#   aiswitch personal [claude|codex|all]  ← switch to personal profile
#   aiswitch keys                         ← manage API keys
#   aiswitch status                       ← show current profile state
#   aiswitch restore                      ← switch both tools back to work

_AISWITCH_STATE="$HOME/.claude/aiswitch-state"
_AISWITCH_KEYCHAIN="LogiQ"

# ── State helpers ──────────────────────────────────────────────────────────────

_aiswitch_state_get() {
  [[ -f "$_AISWITCH_STATE" ]] \
    && grep "^${1}=" "$_AISWITCH_STATE" | tail -1 | cut -d= -f2-
}

_aiswitch_state_set() {
  local tmp; tmp=$(mktemp)
  [[ -f "$_AISWITCH_STATE" ]] && grep -v "^${1}=" "$_AISWITCH_STATE" > "$tmp" || true
  echo "${1}=${2}" >> "$tmp"
  mv "$tmp" "$_AISWITCH_STATE"
}

_aiswitch_claude_profile()  { echo "${$(_aiswitch_state_get CLAUDE_PROFILE):-work}"; }
_aiswitch_codex_profile()   { echo "${$(_aiswitch_state_get CODEX_PROFILE):-work}";  }

# ── Auto mode helpers ──────────────────────────────────────────────────────────

_aiswitch_auto_mode_enabled() {
  [[ "$(_aiswitch_state_get AUTO_MODE_ENABLED)" == "1" ]]
}

_aiswitch_rate_limit_active() {
  local hit_time; hit_time=$(_aiswitch_state_get RATE_LIMIT_HIT_TIME)
  [[ -n "$hit_time" && "$hit_time" != "0" ]]
}

_aiswitch_next_hour_boundary() {
  # Returns Unix timestamp of next :00 minute (top of next hour)
  local now; now=$(date +%s)
  local seconds_into_hour=$(( now % 3600 ))
  local seconds_until_next_hour=$(( 3600 - seconds_into_hour ))
  echo $(( now + seconds_until_next_hour ))
}

_aiswitch_compute_restore_time() {
  # Given a hit time, compute when to restore (next hour + 1 min buffer)
  local hit_time="${1:-$(date +%s)}"
  local seconds_into_hour=$(( hit_time % 3600 ))
  local seconds_until_next_hour=$(( 3600 - seconds_into_hour ))
  echo $(( hit_time + seconds_until_next_hour + 60 ))  # +60 for 1-min buffer
}

_aiswitch_auto_mode_status() {
  if ! _aiswitch_auto_mode_enabled; then
    echo "disabled"
    return
  fi

  if ! _aiswitch_rate_limit_active; then
    echo "enabled"
    return
  fi

  local restore_time; restore_time=$(_aiswitch_state_get AUTO_MODE_RESTORE_TIME)
  local now; now=$(date +%s)

  if (( now >= restore_time )); then
    echo "ready-to-restore"
  else
    local secs_remaining=$(( restore_time - now ))
    local mins_remaining=$(( secs_remaining / 60 ))
    local restore_date; restore_date=$(date -r "$restore_time" '+%H:%M')
    echo "waiting ⏳ restore at $restore_date (${mins_remaining}m)"
  fi
}

# ── Key management (macOS Keychain) ───────────────────────────────────────────

_aiswitch_key_get() {
  security find-generic-password \
    -a "$USER" -s "${_AISWITCH_KEYCHAIN}-${1}" -w 2>/dev/null
}

_aiswitch_key_set() {
  security delete-generic-password \
    -a "$USER" -s "${_AISWITCH_KEYCHAIN}-${1}" 2>/dev/null
  security add-generic-password \
    -a "$USER" -s "${_AISWITCH_KEYCHAIN}-${1}" -w "${2}"
}

_aiswitch_logiq_key() {
  local k; k=$(_aiswitch_key_get "openai")
  echo "${k:-${OPENAI_API_KEY:-}}"
}

_aiswitch_keys_any() {
  [[ -n "$(_aiswitch_logiq_key)" ]]
}

_aiswitch_key_mask() {
  [[ -n "$1" ]] && echo "✓  ${1:0:8}••••••••" || echo "✗  not set"
}

_aiswitch_read_secret() {        # hidden line input → stdout
  printf '%s' "$1" > /dev/tty
  IFS= read -rs _secret_val < /dev/tty
  printf '\n' > /dev/tty
  echo "$_secret_val"
}

_aiswitch_setup_key() {          # _aiswitch_setup_key NAME LABEL
  local current; current=$(_aiswitch_key_get "$1")
  printf '\n  \033[1m%s API key\033[0m\n' "$2" > /dev/tty
  if [[ -n "$current" ]]; then
    printf '  Current: \033[2m%s\033[0m\n'   "${current:0:8}••••••••"  > /dev/tty
    printf '  \033[2mPress Enter to keep, or paste a new key to replace.\033[0m\n' > /dev/tty
  fi
  local input; input=$(_aiswitch_read_secret "  Key: ") || return 1
  if [[ -n "$input" ]]; then
    _aiswitch_key_set "$1" "$input"
    printf '  \033[32m✓ Saved to macOS Keychain\033[0m\n' > /dev/tty
  elif [[ -n "$current" ]]; then
    printf '  \033[2m  kept existing\033[0m\n' > /dev/tty
  else
    printf '  \033[2m  skipped\033[0m\n' > /dev/tty
  fi
}

_aiswitch_setup_keys() {
  printf '\n  \033[1;36m──  API Key Setup  ──\033[0m\n'                                   > /dev/tty
  printf '  Keys are stored in your macOS Keychain, not in files.\n\n'                    > /dev/tty
  printf '  \033[1mLogiQ key\033[0m (Claude Code + Codex)\n'                              > /dev/tty
  printf '  \033[2m  https://logiq.logitech.io → User icon → Profile → API Key → Create\033[0m\n' > /dev/tty
  _aiswitch_setup_key "openai" "LogiQ" || return 1
  printf '\n  \033[32m✓ Setup complete.\033[0m\n\n' > /dev/tty
}

# ── Interactive menu ───────────────────────────────────────────────────────────
# _aiswitch_menu TITLE INITIAL_IDX ITEM...
#   Items: "key:Label"  or  "---" for separator
#   Sets _AISWITCH_MENU_IDX (global). Returns 0=selected, 1=quit.

typeset -g _AISWITCH_MENU_IDX

_aiswitch_menu() {
  local title="$1" initial="${2:-0}"; shift 2
  local -a items=("$@")
  local n=${#items[@]} sel=$initial lns=0
  local TTY=/dev/tty

  while (( sel < n )) && [[ "${items[sel+1]}" == "---" ]]; do (( sel++ )); done

  _amenu_draw() {
    local i line
    printf '  \033[1m%s\033[0m\n' "$title" > "$TTY"; (( lns++ ))
    printf '\n'                             > "$TTY"; (( lns++ ))
    for (( i = 0; i < n; i++ )); do
      line="${items[i+1]}"
      [[ "$line" == *:* && "$line" != "---" ]] && line="${line#*:}"
      if   [[ "${items[i+1]}" == "---" ]]; then
        printf '  \033[2m──────────────────────────\033[0m\n' > "$TTY"
      elif (( i == sel )); then
        printf '  \033[1;36m❯ %s\033[0m\n' "$line"           > "$TTY"
      else
        printf '    %s\n'                  "$line"            > "$TTY"
      fi
      (( lns++ ))
    done
    printf '\n'                                               > "$TTY"; (( lns++ ))
    printf '  \033[2m↑↓ move  ↵ select  q quit\033[0m\n'    > "$TTY"; (( lns++ ))
  }

  _amenu_clear() {
    (( lns > 0 )) && printf '\033[%dA\033[J' "$lns" > "$TTY"
    lns=0
  }

  printf '\033[?25l' > "$TTY"
  _amenu_draw

  local key ch1 ch2
  while true; do
    IFS= read -rsk1 key < "$TTY"
    if [[ "$key" == $'\e' ]]; then
      IFS= read -rsk1 -t 0.05 ch1 < "$TTY"
      if [[ "$ch1" == '[' ]]; then
        IFS= read -rsk1 ch2 < "$TTY"
        case "$ch2" in
          A) local ns=$(( sel-1 ))
             while (( ns>=0 )) && [[ "${items[ns+1]}" == "---" ]]; do (( ns-- )); done
             (( ns>=0 )) && sel=$ns ;;
          B) local ns=$(( sel+1 ))
             while (( ns<n )) && [[ "${items[ns+1]}" == "---" ]]; do (( ns++ )); done
             (( ns<n  )) && sel=$ns ;;
        esac
      fi
    elif [[ "$key" == $'\n' || "$key" == $'\r' ]]; then
      _amenu_clear; printf '\033[?25h' > "$TTY"
      _AISWITCH_MENU_IDX=$sel; return 0
    elif [[ "$key" == 'q' || "$key" == 'Q' || "$key" == $'\x03' ]]; then
      _amenu_clear; printf '\033[?25h' > "$TTY"
      _AISWITCH_MENU_IDX=-1; return 1
    fi
    _amenu_clear; _amenu_draw
  done
}

# ── Apply profile to config files ─────────────────────────────────────────────

_aiswitch_apply_claude() {
  local profile="$1"
  local src="$HOME/.claude/${profile}-profile.json"
  local dst="$HOME/.claude/settings.json"

  cp "$src" "$dst"
  _aiswitch_state_set CLAUDE_PROFILE "$profile"
}

_aiswitch_apply_codex() {
  local profile="$1"
  local src="$HOME/.codex/${profile}-profile.toml"
  local dst="$HOME/.codex/config.toml"
  local key; key=$(_aiswitch_logiq_key)

  cp "$src" "$dst"
  if [[ -n "$key" ]]; then
    # Remove any existing api_key line, then append
    grep -v "^api_key" "$dst" > "${dst}.tmp" && mv "${dst}.tmp" "$dst"
    printf '\napi_key = "%s"\n' "$key" >> "$dst"
  fi
  _aiswitch_state_set CODEX_PROFILE "$profile"
}

_aiswitch_apply() {           # _aiswitch_apply PROFILE TOOLS
  local profile="$1" tools="${2:-all}"
  local applied=()

  case "$tools" in
    claude|all) _aiswitch_apply_claude "$profile"; applied+=("Claude") ;;
  esac
  case "$tools" in
    codex|all)  _aiswitch_apply_codex  "$profile"; applied+=("Codex")  ;;
  esac

  # Sync apiswitch env so current shell and new processes use the right profile
  if [[ -x "$HOME/bin/apiswitch" ]]; then
    "$HOME/bin/apiswitch" "$profile" 2>/dev/null
    source "$HOME/.apienv" 2>/dev/null
  fi

  # Kill running CLI processes — they'll restart on next invocation with fresh env
  case "$tools" in
    claude|all) pkill -x "claude" 2>/dev/null || true ;;
  esac
  case "$tools" in
    codex|all)  pkill -x "codex"  2>/dev/null || true ;;
  esac

  # Restart desktop apps
  case "$tools" in
    claude|all)
      if pgrep -x "Claude" > /dev/null 2>&1; then
        pkill -x "Claude" 2>/dev/null || true
        sleep 0.3
        open -b "com.anthropic.claudefordesktop" &
      fi ;;
  esac
  case "$tools" in
    codex|all)
      if pgrep -x "Codex" > /dev/null 2>&1; then
        pkill -x "Codex" 2>/dev/null || true
        sleep 0.3
        open -b "com.openai.codex" &
      fi ;;
  esac

  local targets="${(j: + :)applied}"
  printf '  \033[32m✓ Switched %s → %s profile\033[0m\n' "$targets" "$profile" > /dev/tty
}

# ── Auto mode commands ─────────────────────────────────────────────────────────

_aiswitch_start_monitor() {
  # Start background monitor process if not already running
  local pid_file="$HOME/.claude/aiswitch-monitor.pid"

  if [[ -f "$pid_file" ]]; then
    local old_pid; old_pid=$(<"$pid_file")
    if kill -0 "$old_pid" 2>/dev/null; then
      return 0  # Already running
    fi
  fi

  # Write monitor script to temp location
  local monitor_script="$HOME/.claude/aiswitch-monitor.sh"
  cat > "$monitor_script" << 'MONEOF'
#!/bin/zsh
# Auto-restore monitor — checks periodically if it's time to restore

_STATE_FILE="$HOME/.claude/aiswitch-state"
_PID_FILE="$HOME/.claude/aiswitch-monitor.pid"

_state_get() {
  [[ -f "$_STATE_FILE" ]] \
    && grep "^${1}=" "$_STATE_FILE" | tail -1 | cut -d= -f2-
}

_state_set() {
  local tmp; tmp=$(mktemp)
  [[ -f "$_STATE_FILE" ]] && grep -v "^${1}=" "$_STATE_FILE" > "$tmp" || true
  echo "${1}=${2}" >> "$tmp"
  mv "$tmp" "$_STATE_FILE"
}

trap "rm -f '$_PID_FILE'" EXIT

echo $$ > "$_PID_FILE"

while true; do
  RESTORE_TIME=$(_state_get AUTO_MODE_RESTORE_TIME)
  AUTO_ENABLED=$(_state_get AUTO_MODE_ENABLED)

  # Exit if state cleared or auto mode disabled
  [[ -z "$RESTORE_TIME" || "$AUTO_ENABLED" != "1" ]] && break

  NOW=$(date +%s)
  if (( NOW >= RESTORE_TIME )); then
    # Time to restore!
    PREV_PROFILE=$(_state_get AUTO_MODE_PREV_PROFILE)

    # Restore the previous profile
    source "$HOME/.claude/aiswitch.sh"
    _aiswitch_apply "${PREV_PROFILE:-work}" "all" 2>/dev/null

    # Clear auto mode state
    _state_set RATE_LIMIT_HIT_TIME ""
    _state_set AUTO_MODE_RESTORE_TIME ""
    _state_set AUTO_MODE_PREV_PROFILE ""

    printf '\n  \033[32m✓ Auto-restored to %s profile\033[0m\n' "${PREV_PROFILE:-work}" > /dev/tty
    break
  fi

  sleep 30
done

rm -f "$_PID_FILE"
MONEOF
  chmod 755 "$monitor_script"

  # Start in background
  nohup zsh "$monitor_script" > /dev/null 2>&1 &
  echo $! > "$pid_file"
}

_aiswitch_stop_monitor() {
  local pid_file="$HOME/.claude/aiswitch-monitor.pid"
  if [[ -f "$pid_file" ]]; then
    local pid; pid=$(<"$pid_file")
    kill "$pid" 2>/dev/null || true
    rm -f "$pid_file"
  fi
}

_aiswitch_cmd_mode() {
  local action="${1:-status}"

  case "$action" in
    auto)
      if _aiswitch_auto_mode_enabled; then
        printf '  \033[33m⚠  Auto mode already enabled\033[0m\n' > /dev/tty
        return 0
      fi
      printf '\n  \033[1;36m──  Enable Auto Mode  ──\033[0m\n' > /dev/tty
      printf '  When auto mode is active:\n' > /dev/tty
      printf '  • Run "aiswitch hit" when you encounter a rate limit\n' > /dev/tty
      printf '  • Profile will auto-switch to personal (unrestricted)\n' > /dev/tty
      printf '  • At the next hour, will auto-restore to work profile\n' > /dev/tty
      printf '  • You can always manually restore with "aiswitch restore"\n\n' > /dev/tty

      _aiswitch_state_set AUTO_MODE_ENABLED "1"
      printf '  \033[32m✓ Auto mode enabled\033[0m\n' > /dev/tty
      ;;

    manual)
      if ! _aiswitch_auto_mode_enabled; then
        printf '  \033[33m⚠  Auto mode already disabled\033[0m\n' > /dev/tty
        return 0
      fi
      _aiswitch_stop_monitor
      _aiswitch_state_set AUTO_MODE_ENABLED "0"
      _aiswitch_state_set RATE_LIMIT_HIT_TIME ""
      _aiswitch_state_set AUTO_MODE_RESTORE_TIME ""
      _aiswitch_state_set AUTO_MODE_PREV_PROFILE ""
      printf '  \033[32m✓ Auto mode disabled\033[0m\n' > /dev/tty
      ;;

    status)
      printf '\n  Auto mode:  '
      if _aiswitch_auto_mode_enabled; then
        printf '\033[32mEnabled\033[0m\n'
      else
        printf '\033[2mDisabled\033[0m\n'
      fi

      if _aiswitch_rate_limit_active; then
        local restore_time; restore_time=$(_aiswitch_state_get AUTO_MODE_RESTORE_TIME)
        local prev_profile; prev_profile=$(_aiswitch_state_get AUTO_MODE_PREV_PROFILE)
        local now; now=$(date +%s)
        local restore_date; restore_date=$(date -r "$restore_time" '+%H:%M')
        printf '  Status:     ⏳ Waiting to restore to %s at %s\n' "$prev_profile" "$restore_date"
      else
        printf '  Status:     Idle (no rate limit active)\n'
      fi
      printf '\n'
      ;;

    *)
      printf '  Usage: aiswitch mode [auto|manual|status]\n' > /dev/tty
      return 1
      ;;
  esac
}

_aiswitch_cmd_hit() {
  local hit_time="${1:-}"

  if [[ "$hit_time" == "--time" ]]; then
    hit_time="${2:-}"
  fi

  if ! _aiswitch_auto_mode_enabled; then
    printf '  \033[33m⚠  Auto mode is not enabled\033[0m\n' > /dev/tty
    printf '  Enable it first: aiswitch mode auto\n' > /dev/tty
    return 1
  fi

  hit_time="${hit_time:-$(date +%s)}"
  local restore_time; restore_time=$(_aiswitch_compute_restore_time "$hit_time")
  local current_profile; current_profile=$(_aiswitch_claude_profile)

  # Switch to personal if not already
  if [[ "$current_profile" != "personal" ]]; then
    _aiswitch_apply "personal" "all"
  fi

  # Store rate limit state
  _aiswitch_state_set RATE_LIMIT_HIT_TIME "$hit_time"
  _aiswitch_state_set AUTO_MODE_RESTORE_TIME "$restore_time"
  _aiswitch_state_set AUTO_MODE_PREV_PROFILE "$current_profile"

  # Start monitor
  _aiswitch_start_monitor

  # Print status
  local restore_date; restore_date=$(date -r "$restore_time" '+%H:%M')
  local now; now=$(date +%s)
  local mins_remaining=$(( (restore_time - now) / 60 ))

  printf '\n  \033[32m✓ Rate limit detected. Auto-restore armed.\033[0m\n' > /dev/tty
  printf '  📍 Will restore to %s profile at %s (in ~%d minutes)\n' "$current_profile" "$restore_date" "$mins_remaining" > /dev/tty
  printf '  💡 You can also manually restore with: aiswitch restore\n\n' > /dev/tty
}

_aiswitch_cmd_auto_restore() {
  local restore_time; restore_time=$(_aiswitch_state_get AUTO_MODE_RESTORE_TIME)
  local now; now=$(date +%s)

  if [[ -z "$restore_time" ]]; then
    printf '  \033[33m⚠  No auto-restore scheduled\033[0m\n' > /dev/tty
    return 1
  fi

  if (( now >= restore_time )); then
    local prev_profile; prev_profile=$(_aiswitch_state_get AUTO_MODE_PREV_PROFILE)
    _aiswitch_apply "${prev_profile:-work}" "all"

    _aiswitch_state_set RATE_LIMIT_HIT_TIME ""
    _aiswitch_state_set AUTO_MODE_RESTORE_TIME ""
    _aiswitch_state_set AUTO_MODE_PREV_PROFILE ""
  else
    printf '  \033[33m⚠  Restore time not yet reached\033[0m\n' > /dev/tty
    local restore_date; restore_date=$(date -r "$restore_time" '+%H:%M')
    printf '  Will auto-restore at %s\n' "$restore_date" > /dev/tty
    return 1
  fi
}

# ── Wizard ─────────────────────────────────────────────────────────────────────

_aiswitch_wizard() {
  # First-run key check
  if ! _aiswitch_keys_any; then
    printf '\n  \033[33m⚠  No API keys found. Set them up first.\033[0m\n' > /dev/tty
    _aiswitch_setup_keys || return 0
  fi

  local cp; cp=$(_aiswitch_claude_profile)
  local dp; dp=$(_aiswitch_codex_profile)
  local header="aiswitch  ·  Claude: ${cp}  ·  Codex: ${dp}"

  # Step 1: profile
  _aiswitch_menu "$header" 0 \
    "work:🔷  Work     — conservative (20 rpm / 300 rph)" \
    "personal:🔶  Personal — unrestricted" \
    "---" \
    "keys:🔑  Setup API keys" \
    "status:ℹ   Show status"
  [[ $? -ne 0 ]] && return 0

  local -a p_keys=(work personal "---" keys status)
  local profile="${p_keys[_AISWITCH_MENU_IDX+1]}"

  case "$profile" in
    keys)   _aiswitch_setup_keys; return 0 ;;
    status) aiswitch status;      return 0 ;;
  esac

  # Step 2: tools
  _aiswitch_menu "Apply to" 0 \
    "all:All       — Claude + Codex" \
    "claude:Claude    — Code CLI + Mac app" \
    "codex:Codex     — Codex CLI + Mac app"
  [[ $? -ne 0 ]] && return 0

  local -a t_keys=(all claude codex)
  local tools="${t_keys[_AISWITCH_MENU_IDX+1]}"

  _aiswitch_apply "$profile" "$tools"
}

# ── Self-update ────────────────────────────────────────────────────────────────

_aiswitch_cmd_update() {
  local remote_url="https://raw.githubusercontent.com/alexanderkirov/aiswitch/main/aiswitch.sh"
  local install_path="$HOME/.claude/aiswitch.sh"
  local tmp; tmp=$(mktemp)

  printf '  Checking for updates...\n' > /dev/tty

  if ! curl -fsSL "$remote_url" -o "$tmp" 2>/dev/null; then
    printf '  \033[31m✗ Failed to reach GitHub. Check your connection.\033[0m\n' > /dev/tty
    rm -f "$tmp"
    return 1
  fi

  if diff -q "$install_path" "$tmp" > /dev/null 2>&1; then
    printf '  \033[32m✓ Already up to date.\033[0m\n' > /dev/tty
    rm -f "$tmp"
    return 0
  fi

  cp "$install_path" "${install_path}.bak"
  mv "$tmp" "$install_path"
  chmod 644 "$install_path"

  printf '  \033[32m✓ Updated! Reload your shell to apply:\033[0m\n' > /dev/tty
  printf '    source ~/.zshrc\n\n' > /dev/tty
}

# ── Public command ─────────────────────────────────────────────────────────────

aiswitch() {
  if (( $# == 0 )); then
    _aiswitch_wizard; return $?
  fi

  local sub="$1"; shift

  case "$sub" in

    work|personal)
      local tools="${1:-all}"
      if [[ "$tools" != "claude" && "$tools" != "codex" && "$tools" != "all" ]]; then
        echo "Usage: aiswitch ${sub} [claude|codex|all]"; return 1
      fi
      _aiswitch_apply "$sub" "$tools"
      ;;

    keys)
      case "${1:-setup}" in
        setup)  _aiswitch_setup_keys ;;
        status)
          local ok; ok=$(_aiswitch_key_get "openai")
          echo "  LogiQ: $(_aiswitch_key_mask "$ok")"
          ;;
        delete)
          local name="${2:-}"
          if [[ "$name" == "logiq" || "$name" == "openai" || "$name" == "all" ]]; then
            security delete-generic-password -a "$USER" -s "${_AISWITCH_KEYCHAIN}-openai" 2>/dev/null
            echo "  Deleted LogiQ key"
          else
            echo "Usage: aiswitch keys delete [logiq|all]"
          fi
          ;;
        *) echo "Usage: aiswitch keys [setup|status|delete]" ;;
      esac
      ;;

    mode)
      _aiswitch_cmd_mode "$@"
      ;;

    hit)
      local time_arg=""
      if [[ "$1" == "--time" ]]; then
        shift
        time_arg="$1"
      fi
      _aiswitch_cmd_hit "$time_arg"
      ;;

    auto-restore)
      _aiswitch_cmd_auto_restore
      ;;

    restore)
      _aiswitch_apply "work" "all"
      ;;

    status)
      local cp dp ok am_status
      cp=$(_aiswitch_claude_profile); dp=$(_aiswitch_codex_profile)
      ok=$(_aiswitch_key_get "openai")
      am_status=$(_aiswitch_auto_mode_status)

      echo "╭─ aiswitch ─────────────────────────────────────────────"
      echo "│  Claude profile:  $cp    (→ ~/.claude/settings.json)"
      echo "│  Codex  profile:  $dp    (→ ~/.codex/config.toml)"
      echo "│"

      if _aiswitch_auto_mode_enabled; then
        echo "│  Auto mode:       enabled"
        echo "│  Status:          $am_status"
        echo "│"
      fi

      echo "│  API key  (macOS Keychain — service: ${_AISWITCH_KEYCHAIN})"
      echo "│    LogiQ: $(_aiswitch_key_mask "$ok")"
      echo "│"
      echo "│  aiswitch [work|personal] [claude|codex|all]"
      if _aiswitch_auto_mode_enabled; then
        echo "│  aiswitch mode [auto|manual]   aiswitch hit"
      fi
      echo "│  aiswitch keys [setup|status|delete]"
      echo "│  aiswitch restore   aiswitch status   aiswitch update"
      echo "╰────────────────────────────────────────────────────────"
      ;;

    update)
      _aiswitch_cmd_update
      ;;

    help|--help|-h) aiswitch status ;;

    *)
      echo "Unknown subcommand: $sub"
      echo "Run aiswitch (no args) for the interactive wizard."
      return 1
      ;;
  esac
}
