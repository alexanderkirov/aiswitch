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

## Two-tool architecture

There are **two separate tools** that work together — both sourced via `~/.zshrc`:

### `apiswitch` (`~/bin/apiswitch`) — Claude auth
Manages Claude Code's connection to the LogiQ Anthropic-compatible API by writing `~/.apienv`, which is sourced into the shell on every launch:

```sh
# work profile writes:
export ANTHROPIC_BASE_URL="https://logiq-service.logitech.io/anthropic"
export ANTHROPIC_AUTH_TOKEN="<logiq_token>"
export CLAUDE_CODE_SKIP_BEDROCK_AUTH=1
export OPENAI_BASE_URL="https://logiq-service.logitech.io/openai/v1"
export OPENAI_API_KEY="<logiq_token>"
unset ANTHROPIC_API_KEY

# personal profile unsets all of the above
```

The LogiQ token is read from macOS Keychain (`LogiQ-openai`) by `apiswitch` at runtime. `~/.zshrc` sources `~/.apienv` on startup and wraps `apiswitch` to re-source after each call.

### `aiswitch` (`~/.claude/aiswitch.sh`) — model/settings profiles
Manages `~/.claude/settings.json` and `~/.codex/config.toml` — controls model selection, rate limit display, and Codex reasoning effort. Does **not** handle Claude auth (that's `apiswitch`'s job).

The Codex `api_key` (LogiQ token) is stored in macOS Keychain as `LogiQ-openai` and appended to `config.toml` on switch.

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

Profile files in `profiles/` are templates — never used directly. `_aiswitch_apply` orchestrates the full switch:

1. `_aiswitch_apply_claude`: copies profile JSON to `~/.claude/settings.json`
2. `_aiswitch_apply_codex`: copies TOML to `~/.codex/config.toml`, appends `api_key`
3. Calls `~/bin/apiswitch <profile>` (output → `/dev/tty`; returns 1 on missing token, aborting apply) + sources `~/.apienv`
4. `_aiswitch_launchd_env`: mirrors all auth env vars into macOS launchd bootstrap namespace via `launchctl setenv`/`unsetenv`, so GUI apps launched via `open -b` inherit them
5. Kills `claude`/`codex` CLI processes from other sessions (by session ID, spares current session)
6. Kills desktop apps with `kill -9` (not `pkill` — Electron resists SIGTERM) and relaunches via `open -b`

### launchd env vs shell env

macOS GUI apps launched via `open -b` do **not** inherit shell env vars — they get env from the launchd bootstrap namespace instead. `_aiswitch_launchd_env` bridges this gap by calling `launchctl setenv` for every var that `apiswitch` writes to `~/.apienv`. The token is read from `$ANTHROPIC_AUTH_TOKEN` (already set in shell by `source ~/.apienv` in step 3) with `_aiswitch_logiq_key()` as fallback.

`launchctl setenv` only affects **newly launched** processes. The desktop app must be restarted (step 6) to pick up new values. Vars set this way persist for the user session but are lost on reboot — `aiswitch work` must be re-run after restart.

### Auth model

| Profile | Claude auth | Codex auth |
|---|---|---|
| work | `ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL` set by `apiswitch` in `~/.apienv` | LogiQ key (`LogiQ-openai`) in `config.toml` |
| personal | all LogiQ env vars unset by `apiswitch`; falls back to claude.ai subscription | LogiQ key (`LogiQ-openai`) in `config.toml` |

### State file

`~/.claude/aiswitch-state` is a `KEY=VALUE` file managed by `_aiswitch_state_get` / `_aiswitch_state_set`. Written atomically via mktemp + mv. Keys: `CLAUDE_PROFILE`, `CODEX_PROFILE`, `AUTO_MODE_ENABLED`, `RATE_LIMIT_HIT_TIME`, `AUTO_MODE_RESTORE_TIME`, `AUTO_MODE_PREV_PROFILE`.

### API key storage

One key in macOS Keychain (service prefix `LogiQ-`, account = `$USER`):
- `LogiQ-openai` → `_aiswitch_logiq_key()` — appended to `config.toml` for both Codex profiles

Falls back to `OPENAI_API_KEY` env var if Keychain entry absent.

### Auto-update

`aiswitch` silently fetches the latest `aiswitch.sh` from GitHub on every invocation (disowned background job, `&!`). If changed, replaces `~/.claude/aiswitch.sh` and prints `↻ aiswitch updated — run: source ~/.zshrc`. Skipped when subcommand is `update`.

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

apiswitch                             interactive menu (Claude auth)
apiswitch work|personal               switch Claude auth profile
apiswitch status                      show current auth profile
```

## Profile settings

| | Claude work | Claude personal | Codex work | Codex personal |
|---|---|---|---|---|
| Default model | `claude-sonnet-4-6` | `claude-sonnet-4-6` | `gpt-5.1-codex` | `gpt-5.1-codex` |
| Available models | haiku, sonnet, opus | haiku, sonnet, opus | — | — |
| Reasoning effort | — | — | `medium` | `xhigh` |
| Rate limit | 20 RPM / 300 RPH | unrestricted | — | — |

## LogiQ API (Codex backend)

Codex uses the LogiQ OpenAI-compatible API at `https://logiq-service.logitech.io/openai/v1`.
The `api_key` in `config.toml` is a base64-encoded LogiQ access token — **not** an OpenAI key.
Obtain via: LogiQ portal → User icon → Profile → API Key tab → Create. Keys expire after 1 year.

Current Codex model: `gpt-5.1-codex`. Other available models: `gpt-5.1-codex-mini`, `gpt-5`, `gpt-5.2`, `gpt-4o`, `gpt-4.1`.

## Auto mode

Switches to personal on rate limit, auto-restores at next hourly boundary + 1 min buffer.

Background monitor (`~/.claude/aiswitch-monitor.sh`) polls every 30s, exits on restore. PID in `~/.claude/aiswitch-monitor.pid`.

Restore time formula: `next_hour_boundary + 60s` — computed in `_aiswitch_compute_restore_time()`.

## Known limitations

**Claude desktop app Cowork mode** — Cowork uses a native Swift/Go VM (`swift_addon.node`) with its own HTTP client that does **not** read `ANTHROPIC_BASE_URL` from `process.env`. It bypasses the Anthropic JS SDK entirely and connects directly to `api.anthropic.com` (Anthropic IP `160.79.104.10`). There is no external config to redirect it to LogiQ. Only the Claude Code CLI and Codex use LogiQ in work profile.

## Troubleshooting

**"Invalid API key" on new machine** — `~/.apienv` is missing. Run `apiswitch work` to regenerate it (requires `~/bin/apiswitch` with the LogiQ token to be present first).

**`aiswitch` not found after install** — `source ~/.zshrc` or verify `~/.zshrc` sources `~/.claude/aiswitch.sh`.

**Desktop app shows old model** — start a new conversation (not resuming); resuming sessions use per-session cached model.

**Monitor process stuck** — `kill $(cat ~/.claude/aiswitch-monitor.pid) && rm ~/.claude/aiswitch-monitor.pid`

**Desktop app still uses wrong profile after `aiswitch work`** — launchd env vars are set but the running app has stale env from before the switch. Force-restart it: `kill -9 $(pgrep -x "Claude") && open -b "com.anthropic.claudefordesktop"`. Then verify: `launchctl getenv ANTHROPIC_AUTH_TOKEN` should show the token.

**Token missing after system reboot** — `launchctl setenv` values don't persist across reboots. Run `aiswitch work` again to repopulate launchd env and restart apps.
