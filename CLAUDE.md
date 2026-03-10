# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

LogiQ is a zsh shell function (`aiswitch`) that switches Claude and Codex between work/personal profiles. It writes config files in place so both CLI tools and their Mac apps pick up the change without restarting.

## Development workflow

### Making changes

`aiswitch.sh` in this repo is the source of truth. The running copy lives at `~/.claude/aiswitch.sh` and is loaded by `~/.zshrc`.

To test changes locally after editing:
```zsh
cp aiswitch.sh ~/.claude/aiswitch.sh && source ~/.zshrc
```

Profile files under `profiles/` are deployed to `~/.claude/` and `~/.codex/` by `install.sh` and are not live-linked. After updating profiles:
```zsh
bash install.sh
```

### Testing

Test changes interactively:
```zsh
aiswitch                    # test interactive wizard
aiswitch work               # test direct switch
aiswitch work claude        # test single-tool switch
aiswitch keys status        # test key management
aiswitch status             # verify state
```

Test profile application by checking the generated config files:
```zsh
cat ~/.claude/settings.json
cat ~/.codex/config.toml
```

## Architecture of `aiswitch.sh`

### Interactive menu — global result, not stdout

`_aiswitch_menu` **cannot** return its result via stdout (that would require `$()` which forks a subshell and breaks interactive terminal I/O). Instead:

- All display is written explicitly to `/dev/tty`, never stdout
- The selected index is stored in the global `typeset -g _AISWITCH_MENU_IDX`
- Callers check `$?` for quit (returns 1) and read `_AISWITCH_MENU_IDX` for the selection

This pattern applies everywhere: `_aiswitch_apply`, key setup prompts, and status output all write to `/dev/tty`. **Never add `echo`/`printf` to stdout inside these functions** — it will corrupt return values or break callers using `$(...)`.

### Inner functions and zsh dynamic scoping

`_amenu_draw` and `_amenu_clear` are defined inside `_aiswitch_menu`. They reference `$title`, `$items`, `$sel`, `$lns`, `$n`, and `$TTY` which are local variables of `_aiswitch_menu`. This works because **zsh uses dynamic scoping** — a called function sees the locals of its caller. Do not convert these to top-level functions without passing those variables explicitly.

### Menu item format and index mapping

Items are `"key:Display text"` or `"---"` for a visual separator (skipped by keyboard nav). After `_aiswitch_menu` returns, the wizard maps the index back to a key using a **parallel array**:

```zsh
local -a p_keys=(work personal "---" keys status)
local profile="${p_keys[_AISWITCH_MENU_IDX+1]}"   # zsh arrays are 1-indexed
```

The `p_keys` array must exactly mirror the items list passed to `_aiswitch_menu`, including `"---"` entries at the same positions.

### Profile apply pipeline

Profile files (`profiles/claude/*.json`, `profiles/codex/*.toml`) are **templates**, never used directly by Claude/Codex. On switch:

1. `_aiswitch_apply_claude` — uses Python 3 to read the profile JSON, inject `env.ANTHROPIC_API_KEY`, and write the result to `~/.claude/settings.json`
2. `_aiswitch_apply_codex` — copies the TOML then splices `api_key = "..."` via grep/printf into `~/.codex/config.toml`

If no key is stored, the profile is copied as-is without the key field. Both active config files are completely overwritten on every switch.

### State file

`~/.claude/aiswitch-state` is a plain `KEY=VALUE` file managed by `_aiswitch_state_get` / `_aiswitch_state_set`. Current keys: `CLAUDE_PROFILE`, `CODEX_PROFILE` (default `work` when absent). The file is replaced atomically via a temp file.

### API key storage

Keys are in macOS Keychain under service `LogiQ-anthropic` and `LogiQ-openai` (account = `$USER`). `_aiswitch_anthropic_key` / `_aiswitch_openai_key` fall back to the matching env var if the Keychain entry is absent.

### `install.sh` vs `aiswitch.sh` language

`install.sh` runs as `bash` (shebang `#!/usr/bin/env bash`). `aiswitch.sh` is **zsh-only** (uses `typeset -g`, zsh array indexing, `read -rsk1`, `${$(...):- }`). The installer sources `aiswitch.sh` directly and calls its internal functions — this works because the functions it calls (`_aiswitch_setup_keys`, `_aiswitch_apply`) happen to be bash-compatible, but `aiswitch.sh` should not be assumed portable to bash.

**Do not port aiswitch.sh to bash** — zsh features are essential:
- `typeset -g` for module-level globals (bash uses plain `declare` which is function-scoped)
- zsh dynamic scoping for inner functions (`_amenu_draw` needs access to `_aiswitch_menu` locals)
- zsh array syntax `$arr[index]` and `${#arr[@]}` differ from bash
- `read -rsk1` for single-char input is zsh-specific

If bash compatibility is needed in the future, refactor to pass all variables explicitly or use a different approach entirely.

## Command reference

### Profile switching

```
aiswitch                              interactive wizard (no args)
aiswitch work    [claude|codex|all]   switch to work profile
aiswitch personal [claude|codex|all]  switch to personal profile
aiswitch restore                      switch both back to work
```

### Auto mode (rate limit handling)

```
aiswitch mode auto                    enable auto mode
aiswitch mode manual                  disable auto mode
aiswitch mode status                  show auto mode state
aiswitch hit [--time UNIX_TIMESTAMP]  signal rate limit, trigger switch to personal
aiswitch auto-restore                 (internal) check if time to restore, then restore
```

### Other commands

```
aiswitch keys    [setup|status|delete [anthropic|openai|all]]
aiswitch status                       show current state and profiles
```

## Profile settings

| | Claude work | Claude personal | Codex work | Codex personal |
|---|---|---|---|---|
| Default model | `claude-haiku-4-5-20251001` | `claude-sonnet-4-6` | `gpt-5.3-codex` | `gpt-5.3-codex` |
| Available models | haiku, sonnet, opus | haiku, sonnet, opus | — | — |
| Thinking | off | off | — | — |
| Reasoning effort | — | — | `medium` | `xhigh` |
| Rate limit target | 20 RPM / 300 RPH | unrestricted | — | — |

**Model availability**: Both work and personal profiles now include Haiku, Sonnet, and Opus in `availableModels`, allowing you to switch between them in the Claude Code UI. The default model is Haiku (work) or Sonnet (personal), but you can select any available model interactively.

## Auto mode: Rate limit handling

Auto mode automatically switches to the personal (unrestricted) profile when you hit a rate limit, then auto-restores to the work profile at the next hourly boundary.

### Enabling auto mode

```zsh
aiswitch mode auto
```

This displays an explanation and enables auto mode. No background process starts until a rate limit is actually hit.

### When you hit a rate limit

You'll see a 429 error from the Claude API (either in CLI output or in the Desktop app). To trigger auto mode:

```zsh
aiswitch hit
```

This:
1. Validates auto mode is enabled (exits with error if not)
2. Switches to personal profile immediately (if not already on it)
3. Records the hit time and computes restore time (next hour boundary + 1-minute buffer)
4. Starts a background monitor process that checks every 30 seconds
5. Prints confirmation with the restore time

**Example output**:
```
  ✓ Rate limit detected. Auto-restore armed.
  📍 Will restore to work profile at 15:01 (in ~26 minutes)
  💡 You can also manually restore with: aiswitch restore
```

### How restore timing works

Claude's work profile is configured for **300 requests per hour (RPH)** rate limit. When you hit this limit:

- The system records the hit time
- Computes restore time as: **next hour boundary + 1-minute buffer**
- Example: hit at 14:35 → restore at 15:01 (not 14:36)

The 1-minute buffer ensures the rate limit window has definitely passed. This is conservative but safe.

### Background monitor process

When `aiswitch hit` is called, a lightweight background process starts:
- File: `~/.claude/aiswitch-monitor.sh` (created on first use)
- Runs in background with PID stored in `~/.claude/aiswitch-monitor.pid`
- Loops every 30 seconds checking if restore time is reached
- When time comes, calls `aiswitch auto-restore` and exits
- **Automatic cleanup**: Process exits when shell closes (no persistent daemon)

The monitor is lightweight and safe—it's just a loop that checks a timestamp.

### Manual restore anytime

You can manually restore to the work profile at any time:

```zsh
aiswitch restore
```

This bypasses the timer and restores immediately.

### Disabling auto mode

```zsh
aiswitch mode manual
```

This:
- Disables auto mode for future rate limits
- Stops any running monitor process
- Clears any pending auto-restore state
- Your current profile doesn't change

### Checking auto mode status

```zsh
aiswitch status
```

Shows:
- Whether auto mode is enabled
- If a rate limit is active (shows restore time and countdown)
- Current profiles
- API key status

### How the Desktop app interacts with auto mode

The Claude Desktop app may use its own stored credentials (in Electron `safeStorage`), separate from the Keychain. When you see a 429 error in the Desktop app:

1. Run `aiswitch hit` from your terminal to trigger the switch
2. The personal profile will be active on the next API request
3. Auto-restore will happen at the computed time

(Alternatively, the CLI and Desktop app may share credentials depending on your setup. Auto mode primarily targets CLI users, but the profile switch affects both.)

### Rate limit detection is user-initiated

Auto mode doesn't automatically detect 429 errors—you must manually run `aiswitch hit`. This is by design:

- **Explicit**: You confirm you actually saw a 429 (not a network timeout or other error)
- **Works for both CLI and Desktop app**: Same command handles both
- **Future enhancement**: Could add wrapper scripts that parse stderr for 429 and call `aiswitch hit` automatically

### Typical workflow

1. **First time setup**: `aiswitch mode auto` (enables auto mode, no change to current profile)
2. **Normal work**: Use Claude on work profile (20 RPM / 300 RPH limits)
3. **Hit rate limit**: See 429 error, run `aiswitch hit`
4. **Switch happens**: Profile switches to personal (unrestricted)
5. **Wait or restore**: Either wait for auto-restore at next hour, or manually `aiswitch restore`

### Edge cases

**What if I close the terminal before restore?**
- The monitor process exits (normal shell cleanup)
- No state is lost—next terminal session can see the pending restore
- You can run `aiswitch auto-restore` later to manually trigger it, or `aiswitch restore` to force-restore now

**What if I disable auto mode while waiting?**
- `aiswitch mode manual` clears all auto mode state
- Monitor exits
- Profile stays wherever it was (monitor doesn't restore)

**What if the system time is wrong?**
- Restore time is computed based on system time
- If clock is wrong, restore might trigger early/late (by the clock error)
- You can always manually override with `aiswitch restore`

## Desktop App Integration

### Claude Desktop App

The Mac app (`/Applications/Claude.app`) launches the embedded claude-code binary with `settingSources: ["user","project","local"]`, which means it **does** read `~/.claude/settings.json`.

**Profile switching behavior**:
- When you run `aiswitch work` or `aiswitch personal`, it updates `~/.claude/settings.json` immediately
- **Fresh sessions**: When you start a new conversation in the Desktop app, it will pick up the new model from the profile
- **Resuming sessions**: If you resume an existing conversation, it may use the model stored in that session's metadata (not the new profile model)
- **Credentials**: The Desktop app uses its own stored credentials (Electron `safeStorage`), not the Keychain keys. The API key you see in `settings.json` is used by the CLI tool

**Testing Desktop app profile switching**:
```
1. In Terminal: aiswitch work
2. In Claude Desktop: Start a NEW conversation (not resuming old one)
3. Notice the model shown matches the work profile (Haiku by default)
4. In Terminal: aiswitch personal
5. In Claude Desktop: Start a NEW conversation
6. Notice the model switches to personal profile (Sonnet by default)
```

**Notes on Desktop app behavior**:
- `CLAUDE_CONFIG_DIR` env var overrides config directory (Desktop app uses this for VM/container sessions)
- `bypassPermissionsModeEnabled: true` in `~/Library/Application Support/Claude/claude_desktop_config.json` bypasses tool permission checks
- Rate limit handling: When you hit a rate limit in the Desktop app, run `aiswitch hit` in Terminal to trigger auto mode profile switch

### Codex Desktop App

If using Codex (OpenAI) via Desktop app:
- Profile switching updates `~/.codex/config.toml` via `aiswitch` commands
- The Codex Desktop app reads from `~/.codex/config.toml` (or custom path if configured)
- **Fresh sessions**: Profile switches take effect on the next API request
- **Resuming sessions**: May continue with the previously configured model until session restarts

**Testing Codex Desktop app profile switching**:
```
1. In Terminal: aiswitch work codex
2. In Codex Desktop: Start a NEW API session
3. Notice reasoning effort set to "medium" (work profile)
4. In Terminal: aiswitch personal codex
5. In Codex Desktop: Start a NEW API session
6. Notice reasoning effort set to "xhigh" (personal profile)
```

## Verifying Desktop App Profile Switching Works

### Verification Checklist

Use this checklist to verify that profile switching works correctly in both CLI and Desktop apps:

#### Claude Desktop App
- [ ] Check config file exists: `cat ~/.claude/settings.json | head -5`
- [ ] Verify it contains a model field: `grep -i model ~/.claude/settings.json`
- [ ] Profile files are valid JSON: `python3 -m json.tool ~/.claude/settings.json`
- [ ] Switch profiles: `aiswitch work` then `aiswitch personal`
- [ ] Verify file updated each time: `cat ~/.claude/settings.json | grep model`
- [ ] Start a **fresh** Claude conversation after each switch
- [ ] Verify the model changes (Haiku for work, Sonnet for personal)
- [ ] Verify all three models (haiku, sonnet, opus) are available in settings

#### Codex Desktop App
- [ ] Check config file exists: `cat ~/.codex/config.toml`
- [ ] Verify it contains model and reasoning_effort: `grep "^model\|reasoning" ~/.codex/config.toml`
- [ ] Switch profiles: `aiswitch work codex` then `aiswitch personal codex`
- [ ] Verify file updated each time: `cat ~/.codex/config.toml | grep reasoning_effort`
- [ ] Start a **fresh** Codex session after each switch
- [ ] Verify reasoning effort changes (medium for work, xhigh for personal)

#### Command Line Interface (CLI)
- [ ] Switch profiles: `aiswitch work` and `aiswitch personal`
- [ ] Verify state saved: `grep PROFILE ~/.claude/aiswitch-state`
- [ ] Verify config written: `cat ~/.claude/settings.json | grep model`
- [ ] Test single-tool switches: `aiswitch work claude` and `aiswitch work codex`
- [ ] Test restore: `aiswitch restore` returns to work profile

#### Auto Mode (if enabled)
- [ ] Enable: `aiswitch mode auto`
- [ ] Check status: `aiswitch status` shows auto mode enabled
- [ ] Test hit: `aiswitch hit --time $(date +%s)` triggers switch to personal
- [ ] Verify immediate profile switch: `cat ~/.claude/settings.json | grep model`
- [ ] Check countdown: `aiswitch status` shows restore time
- [ ] Manual restore: `aiswitch restore` clears auto mode state

### Integration Test Script

Run the automated integration test:
```bash
bash <(curl -fsSL https://path-to-repo/test_desktop_integration.sh)
```

Or locally:
```bash
/tmp/test_desktop_integration.sh
```

Expected output: All 6 test categories pass with ✓ marks

### Configuration File Formats

**Claude settings.json** (example):
```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "model": "claude-haiku-4-5-20251001",
  "availableModels": ["haiku", "sonnet", "opus"],
  "alwaysThinkingEnabled": false
}
```

**Codex config.toml** (example):
```toml
model = "gpt-5.3-codex"
model_reasoning_effort = "medium"

[mcp_servers.figma]
url = "https://mcp.figma.com/mcp"
```

### Debugging Profile Issues

**Problem**: Desktop app shows old model after `aiswitch`

**Debug steps**:
1. Verify file updated: `ls -lt ~/.claude/settings.json` (check timestamp)
2. Verify JSON is valid: `python3 -m json.tool ~/.claude/settings.json`
3. Force Desktop app reload: Fully quit the app (⌘Q), reopen
4. Start a **new** conversation (not resuming old one)
5. Check app is reading from correct directory: `echo $CLAUDE_CONFIG_DIR`

**Problem**: Auto mode rate limit hit doesn't switch profiles in Desktop app

**Debug steps**:
1. Verify manual switch works: `aiswitch personal` (check that settings.json updates)
2. Verify Desktop app can see new settings: Quit and reopen, start new conversation
3. Run `aiswitch hit` and verify: `grep "personal" ~/.claude/aiswitch-state`
4. Check status: `aiswitch status` shows restore time
5. Next API request from Desktop app will use new profile

**Problem**: Keychain API keys not used by Desktop app

**Debug steps**:
1. Check Keychain has key: `aiswitch keys status`
2. Verify key injected into settings: `grep ANTHROPIC_API_KEY ~/.claude/settings.json`
3. Desktop app may use its own credentials storage (Electron safeStorage)
4. Set API key in Desktop app directly if needed
5. CLI tools will use Keychain key from `settings.json` env section

### Configuration Files Read by Desktop Apps

**Claude Desktop app**:
- Primary: `~/.claude/settings.json` (written by `_aiswitch_apply_claude`)
- Optional: `~/.claude/claude_code.json` or project-specific settings
- Session metadata: Stores model choice per session (may override settings)

**Codex Desktop app**:
- Primary: `~/.codex/config.toml` (written by `_aiswitch_apply_codex`)
- API key section is updated with Keychain value if present

### Verification Checklist for Desktop App Integration

- ✓ Profile files are valid JSON/TOML (syntax checked by `install.sh`)
- ✓ `_aiswitch_apply_claude` correctly injects API key into `settings.json`
- ✓ `_aiswitch_apply_codex` correctly injects API key into `config.toml`
- ✓ Files are written atomically (temp file + mv pattern)
- ✓ Desktop apps read from standard config locations
- ✓ Profile switching is immediate (files updated synchronously)
- ✓ New sessions pick up new profiles
- ✓ Manual `aiswitch restore` works from Terminal

### Troubleshooting Desktop App Profile Switching

**Desktop app doesn't pick up new profile after `aiswitch`**:
- Verify the config file was updated: `cat ~/.claude/settings.json | grep model`
- Start a **new** conversation (not resuming existing one)
- Desktop app reads config on startup, not mid-session
- If still not working, restart the Desktop app entirely

**Rate limit in Desktop app doesn't automatically switch**:
- Desktop app doesn't call `aiswitch hit` automatically
- You must run `aiswitch hit` manually in Terminal when you see 429
- Then the next API request will use the personal (unrestricted) profile

**API key not being used by Desktop app**:
- Desktop app stores credentials in Electron `safeStorage` (separate from Keychain)
- The `env.ANTHROPIC_API_KEY` in `settings.json` is for CLI use
- If Desktop app doesn't have API key set, you may need to configure it in app settings

## Repository structure

```
LogiQ/
  aiswitch.sh              ← main zsh function (deployed to ~/.claude/aiswitch.sh)
  install.sh               ← team installer script (bash, sources aiswitch.sh)
  profiles/
    claude/
      work-profile.json    ← Claude work config template (Haiku, rate-limited)
      personal-profile.json ← Claude personal config template (Sonnet, unrestricted)
    codex/
      work-profile.toml    ← Codex work config template (medium reasoning)
      personal-profile.toml ← Codex personal config template (xhigh reasoning)
  .claude/
    settings.local.json    ← local project overrides (if any)
```

State and config generated at runtime (not in repo):
- `~/.claude/aiswitch-state` — persisted profile selections and mode
- `~/.claude/settings.json` — active Claude config (regenerated on each switch)
- `~/.codex/config.toml` — active Codex config (regenerated on each switch)

## Troubleshooting

**"No API keys found" on first run**
- Run `aiswitch keys setup` to add Anthropic and/or OpenAI keys to Keychain
- Keys must be added before switching profiles (the wizard prompts this)

**Config not picking up after switch**
- Claude CLI picks up changes immediately (config is read on each invocation)
- Claude Desktop app: config is read on next request (not real-time); resuming an existing session may not pick up the new model (fresh sessions will)
- Codex CLI should pick up changes immediately
- Codex Desktop app behavior depends on its own refresh logic

**Profile files not deployed to ~/.claude or ~/.codex**
- Run `bash install.sh` from the repo directory to deploy profile files
- The installer copies (not symlinks) to avoid Keychain injection issues during setup

**zsh: command not found: aiswitch**
- The installer should have added a source line to `~/.zshrc`
- Verify: `grep aiswitch ~/.zshrc`
- If missing, manually add: `[[ -f ~/.claude/aiswitch.sh ]] && source ~/.claude/aiswitch.sh`
- Then reload shell: `source ~/.zshrc`

**Keychain issues on new Mac or account**
- `aiswitch keys setup` walks through Keychain setup with prompts
- To check status: `aiswitch keys status`
- To delete and re-add: `aiswitch keys delete [anthropic|openai|all]` then `aiswitch keys setup`

**Auto mode: "No API keys found"**
- Auto mode doesn't require API keys to be set up, but rate limit detection does
- Make sure you have an Anthropic API key set (used by Claude CLI that detects 429s)
- Run `aiswitch keys setup` if needed

**Auto mode: `aiswitch hit` says auto mode not enabled**
- Run `aiswitch mode auto` first to enable auto mode
- Check status with `aiswitch mode status`

**Auto mode: Monitor process not cleaning up**
- Monitor should exit automatically when restore time is reached
- If stuck, check: `ps aux | grep aiswitch-monitor`
- Manual cleanup: `kill $(cat ~/.claude/aiswitch-monitor.pid)` then `rm ~/.claude/aiswitch-monitor.pid`

**Auto mode: Restore time was in the past but didn't auto-trigger**
- Run `aiswitch auto-restore` to manually trigger it
- Or run `aiswitch restore` to force-restore immediately

**Auto mode: Want to cancel pending auto-restore**
- Run `aiswitch restore` to force-restore to work profile now
- Or run `aiswitch mode manual` to disable auto mode and clear state

## Completed Features

**Auto mode** ✅: Automatically handles rate-limit (429) errors by switching to personal profile and auto-restoring at the next hourly boundary. Implemented with:
- `aiswitch mode auto/manual/status` — Control auto mode
- `aiswitch hit [--time]` — Signal rate limit, trigger switch to personal
- `aiswitch auto-restore` — Internal command to check and execute restore
- Background monitor process that polls every 30 seconds
- Full state tracking in `~/.claude/aiswitch-state`
- Comprehensive documentation and testing

## Potential Future Enhancements

- **Auto-detection wrapper**: Shell script to parse Claude CLI stderr for 429 and auto-call `aiswitch hit`
- **Usage statistics**: Track profile switches and rate limit events
- **Rate limit prediction**: Suggest switching before hitting limit based on usage
- **Performance optimization**: Adaptive polling intervals or native file watching
- **Desktop app integration guide**: Advanced workflows for using auto mode with Desktop apps
