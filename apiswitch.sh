#!/usr/bin/env bash
# apiswitch — toggle API profiles for Claude Code & Codex CLI
# Token stored in macOS Keychain as service "LogiQ-openai", account = $USER

readonly LOGIQ_ANTHROPIC="https://logiq-service.logitech.io/anthropic"
readonly LOGIQ_OPENAI="https://logiq-service.logitech.io/openai/v1"
readonly ENV_FILE="$HOME/.apienv"
readonly PROFILE_FILE="$HOME/.apiprofile"

PROFILES=(work personal)
DESCS=(
  "LogiQ  (logiq-service.logitech.io)"
  "Subscription  (Claude Max · GPT Plus)"
)

# ANSI — only emit when stdout is a terminal
if [[ -t 1 ]]; then
  B=$'\033[1m' D=$'\033[2m' R=$'\033[0m'
  GRN=$'\033[32m' CYN=$'\033[36m' GRY=$'\033[90m' YLW=$'\033[33m'
else
  B='' D='' R='' GRN='' CYN='' GRY='' YLW=''
fi

# ── helpers ────────────────────────────────────────────────────────────────────

_logiq_token() {
  local k; k=$(security find-generic-password -a "$USER" -s "LogiQ-openai" -w 2>/dev/null)
  echo "${k:-${OPENAI_API_KEY:-}}"
}

current_profile() { cat "$PROFILE_FILE" 2>/dev/null || printf 'none'; }

write_env() {
  if [[ "$1" == work ]]; then
    local token; token=$(_logiq_token)
    if [[ -z "$token" ]]; then
      printf "  ${YLW}⚠  No LogiQ token found. Run: aiswitch keys setup${R}\n"
      return 1
    fi
    printf '%s\n' \
      "export CLAUDE_CODE_SKIP_BEDROCK_AUTH=1" \
      "export ANTHROPIC_BASE_URL=\"$LOGIQ_ANTHROPIC\"" \
      "export ANTHROPIC_AUTH_TOKEN=\"$token\"" \
      "export CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1" \
      "unset ANTHROPIC_API_KEY" \
      "export OPENAI_BASE_URL=\"$LOGIQ_OPENAI\"" \
      "export OPENAI_API_KEY=\"$token\"" \
      > "$ENV_FILE"
  else
    printf '%s\n' \
      "unset CLAUDE_CODE_SKIP_BEDROCK_AUTH" \
      "unset ANTHROPIC_BASE_URL" \
      "unset ANTHROPIC_AUTH_TOKEN" \
      "unset CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS" \
      "unset ANTHROPIC_API_KEY" \
      "unset OPENAI_BASE_URL" \
      "unset OPENAI_API_KEY" \
      > "$ENV_FILE"
  fi
  printf '%s' "$1" > "$PROFILE_FILE"
}

# ── menu rendering ─────────────────────────────────────────────────────────────

MENU_H=4   # 2 option rows + blank line + hint row

draw_menu() {
  local sel=$1 cur=$2
  for i in 0 1; do
    local p="${PROFILES[$i]}" desc="${DESCS[$i]}" tag=''
    [[ "$p" == "$cur" ]] && tag="  ${GRY}●${R}"
    if [[ $i -eq $sel ]]; then
      printf "  ${CYN}❯${R} ${B}%-10s${R}  ${D}%s${R}%b\n" "$p" "$desc" "$tag"
    else
      printf "    ${D}%-10s  %s${R}%b\n" "$p" "$desc" "$tag"
    fi
  done
  printf '\n'
  printf "  ${GRY}↑↓  navigate    ↵  select    q  quit${R}\n"
}

# ── interactive mode ───────────────────────────────────────────────────────────

PICKED=''

do_interactive() {
  local cur idx=0
  cur=$(current_profile)
  [[ "$cur" == personal ]] && idx=1

  printf "\n  ${B}API Profile${R}  ${GRY}Claude Code · Codex CLI${R}\n\n"

  tput civis 2>/dev/null
  trap 'tput cnorm 2>/dev/null' EXIT INT TERM

  draw_menu "$idx" "$cur"

  local key seq
  while true; do
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        read -rsn2 -t 0.05 seq 2>/dev/null || seq=''
        case "$seq" in
          '[A') (( idx > 0 )) && (( idx-- )) ;;
          '[B') (( idx < 1 )) && (( idx++ )) ;;
        esac
        tput cuu "$MENU_H" 2>/dev/null
        draw_menu "$idx" "$cur"
        ;;
      '')
        tput cuu "$MENU_H" 2>/dev/null
        for (( i=0; i<MENU_H; i++ )); do printf '\033[2K\n'; done
        tput cuu "$MENU_H" 2>/dev/null
        break
        ;;
      q|$'\x03')
        tput cnorm 2>/dev/null
        trap - EXIT INT TERM
        printf "\n  ${GRY}cancelled.${R}\n\n"
        exit 0
        ;;
    esac
  done

  tput cnorm 2>/dev/null
  trap - EXIT INT TERM
  PICKED="${PROFILES[$idx]}"
}

# ── main ───────────────────────────────────────────────────────────────────────

case "${1:-}" in
  work|personal)
    PICKED="$1"
    ;;
  status)
    cur=$(current_profile)
    printf "\n  ${B}%-10s${R}  ${GRY}%s${R}\n\n" \
      "$cur" "${DESCS[ $([[ $cur == personal ]] && echo 1 || echo 0) ]}"
    exit 0
    ;;
  '')
    do_interactive
    ;;
  -h|--help|help)
    printf "usage: apiswitch [work|personal|status]\n"
    printf "\n"
    printf "  work      LogiQ API  (Claude Code + Codex via logiq-service.logitech.io)\n"
    printf "  personal  Subscription auth  (Claude Max + GPT Plus)\n"
    printf "  status    Show current profile\n"
    printf "\n"
    printf "  Run with no arguments for interactive menu.\n"
    printf "\n"
    exit 0
    ;;
  *)
    printf 'apiswitch: unknown argument "%s"\n' "$1" >&2
    printf 'usage: apiswitch [work|personal|status]\n' >&2
    exit 1
    ;;
esac

write_env "$PICKED" || exit 1

i=0; [[ "$PICKED" == personal ]] && i=1
printf "  ${GRN}✓${R} ${B}%s${R}  ${GRY}%s${R}\n\n" "$PICKED" "${DESCS[$i]}"
