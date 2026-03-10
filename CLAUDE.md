# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

LogiQ is a zsh shell function (`aiswitch`) that switches Claude Code and Codex between work/personal profiles by writing config files in place so both CLI tools and their Mac apps pick up changes immediately.

## Development workflow

`aiswitch.sh` is the source of truth. The running copy lives at `~/.claude/aiswitch.sh`, loaded via `~/.zshrc`.

Deploy and test changes:
```zsh
cp aiswitch.sh ~/.claude/aiswitch.sh && source ~/.zshrc
```

After updating profile templates in `profiles/`:
```zsh
bash install.sh
```

Verify output files after a switch:
```zsh
cat ~/.claude/settings.json
cat ~/.codex/config.toml
```

## Architecture of `aiswitch.sh`

### I/O rule: all interactive output goes to `/dev/tty`, never stdout

`_aiswitch_menu` cannot return via stdout — `$()` forks a subshell and breaks terminal I/O. Instead:
- All display writes to `/dev/tty` explicitly
- Selected index stored in global `typeset -g _AISWITCH_MENU_IDX`
- Callers check `$?` for quit (returns 1) and read `_AISWITCH_MENU_IDX`

**This applies to all interactive functions** (`_aiswitch_apply`, `_aiswitch_setup_keys`, `_aiswitch_cmd_mode`, etc.). Never add `echo`/`printf` to stdout inside these — it corrupts return values.

Exception: `aiswitch status` and `aiswitch keys status` use plain `echo` to stdout (non-interactive output).

### zsh dynamic scoping for inner functions

`_amenu_draw` and `_amenu_clear` are defined inside `_aiswitch_menu` and reference its local variables (`$title`, `$items`, `$sel`, `$lns`, `$n`, `$TTY`) via zsh dynamic scoping. Do not extract them to top-level without passing all variables explicitly.

### Menu index mapping

Items passed to `_aiswitch_menu` use format `"key:Display text"` or `"---"` for separators. After return, map the index using a parallel array:

```zsh
local -a p_keys=(work personal "---" keys status)
local profile="${p_keys[_AISWITCH_MENU_IDX+1]}"   # zsh arrays are 1-indexed
```

The `p_keys` array must mirror the items list exactly, including `"---"` at the same positions.

### Profile apply pipeline

Profile files in `profiles/` are templates — never used directly. On switch:

- `_aiswitch_apply_claude`: copies profile JSON to `~/.claude/settings.json`. For **work** profile only, injects the LogiQ key as `ANTHROPIC_API_KEY` via Python 3. Personal profile is copied as-is (uses claude.ai subscription auth — no key injection avoids auth conflict warning).
- `_aiswitch_apply_codex`: copies TOML to `~/.codex/config.toml`, then appends `api_key = "..."` for both profiles.

### Auth model

| Profile | Claude auth | Codex auth |
|---|---|---|
| work | LogiQ API key → `ANTHROPIC_API_KEY` in `settings.json` | LogiQ API key in `config.toml` |
| personal | claude.ai subscription (no key injected) | LogiQ API key in `config.toml` |

### State file

`~/.claude/aiswitch-state` is a `KEY=VALUE` file managed by `_aiswitch_state_get` / `_aiswitch_state_set`. Written atomically via mktemp + mv. Keys: `CLAUDE_PROFILE`, `CODEX_PROFILE`, `AUTO_MODE_ENABLED`, `RATE_LIMIT_HIT_TIME`, `AUTO_MODE_RESTORE_TIME`, `AUTO_MODE_PREV_PROFILE`.

### API key storage

Single LogiQ key stored in macOS Keychain under service `LogiQ-openai` (account = `$USER`), accessed via `_aiswitch_logiq_key()`. Falls back to `$OPENAI_API_KEY` env var if absent.

### `install.sh` vs `aiswitch.sh` language

`install.sh` is bash. `aiswitch.sh` is **zsh-only** — do not port to bash. Zsh features used:
- `typeset -g` for module-level globals
- Dynamic scoping for inner functions
- `read -rsk1` for single-char input
- `$arr[index]` (1-indexed) array syntax

`install.sh` detects pipe execution (`bash <(curl ...)`) vs local checkout via `FETCH_MODE`, downloading files from `https://raw.githubusercontent.com/alexanderkirov/aiswitch/main` when piped.

## Command reference

```
aiswitch                              interactive wizard
aiswitch work|personal [claude|codex|all]
aiswitch restore                      restore both to work
aiswitch update                       self-update from GitHub
aiswitch keys [setup|status|delete [logiq|all]]
aiswitch mode [auto|manual|status]
aiswitch hit [--time UNIX_TIMESTAMP]  signal rate limit
aiswitch auto-restore                 (internal) check/execute restore
aiswitch status
```

## Profile settings

| | Claude work | Claude personal | Codex work | Codex personal |
|---|---|---|---|---|
| Default model | `claude-sonnet-4-6` | `claude-sonnet-4-6` | `gpt-5.3-codex` | `gpt-5.3-codex` |
| Available models | haiku, sonnet, opus | haiku, sonnet, opus | — | — |
| Reasoning effort | — | — | `medium` | `xhigh` |
| Rate limit | 20 RPM / 300 RPH | unrestricted | — | — |

## Auto mode

Switches to personal on rate limit, auto-restores at next hourly boundary + 1 min buffer.

Background monitor (`~/.claude/aiswitch-monitor.sh`) polls every 30s, exits on restore. PID in `~/.claude/aiswitch-monitor.pid`.

Restore time formula: `next_hour_boundary + 60s` — computed in `_aiswitch_compute_restore_time()`.

## Troubleshooting

**Auth conflict warning** — `ANTHROPIC_API_KEY` set while on personal profile: run `aiswitch work` then `aiswitch personal` to regenerate `settings.json` cleanly.

**`aiswitch` not found after install** — `source ~/.zshrc` or verify `~/.zshrc` sources `~/.claude/aiswitch.sh`.

**Desktop app shows old model** — start a new conversation (not resuming); resuming sessions use per-session cached model.

**Monitor process stuck** — `kill $(cat ~/.claude/aiswitch-monitor.pid) && rm ~/.claude/aiswitch-monitor.pid`
