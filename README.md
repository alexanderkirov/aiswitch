# aiswitch

A macOS shell tool that seamlessly switches Claude and Codex between work and personal profiles. Automatically manages API keys, config files, and rate limit handling.

## Quick Start

### 1. Install

One-liner install (downloads from GitHub):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/alexanderkirov/aiswitch/main/install.sh)
```

Or clone locally:

```bash
git clone https://github.com/alexanderkirov/aiswitch.git
bash aiswitch/install.sh
```

### 2. Reload Shell

```bash
source ~/.zshrc
```

### 3. Set Up API Keys

```bash
aiswitch keys setup
```

Follow the prompts to add your API keys. Keys are stored securely in macOS Keychain.

**Don't have API keys?**
- **Anthropic (Claude)**: Get from [console.anthropic.com](https://console.anthropic.com) → API Keys
- **OpenAI (Codex)**: Get from [https://logiq.logitech.io](https://logiq.logitech.io) → User icon (top right) → API Keys → Create

### 4. Start Using

```bash
aiswitch
```

This opens an interactive menu to switch between profiles.

## Usage

### Interactive Menu
```bash
aiswitch
```
Navigate with arrow keys, press Enter to select.

### Quick Switch
```bash
aiswitch work              # Switch both Claude and Codex to work
aiswitch personal          # Switch both to personal
aiswitch work claude       # Switch only Claude to work
aiswitch work codex        # Switch only Codex to work
```

### Check Status
```bash
aiswitch status
```
Shows current profiles, API key status, and auto mode state.

### Manage API Keys
```bash
aiswitch keys setup        # Add or update API keys
aiswitch keys status       # Check what keys are saved
aiswitch keys delete       # Remove saved keys
```

### Auto Mode (Rate Limit Handling)

When you hit Claude's rate limit (429 error), aiswitch can automatically switch to your personal profile.

**Enable auto mode:**
```bash
aiswitch mode auto
```

**When you hit a rate limit:**
```bash
aiswitch hit
```
This switches you to personal profile immediately and auto-restores to work at the next hourly boundary.

**Disable auto mode:**
```bash
aiswitch mode manual
```

**Manual restore anytime:**
```bash
aiswitch restore
```

## Profiles

### Work Profile (Claude)
- **Default model**: Sonnet (rate-limited org account)
- **Rate limit**: 20 requests/min · 300 requests/hour
- **Available models**: Haiku, Sonnet, Opus (switchable in Claude Code UI)

### Personal Profile (Claude)
- **Default model**: Sonnet (capable, unrestricted)
- **Rate limit**: None
- **Available models**: Haiku, Sonnet, Opus

### Codex Profiles
- **Work**: Medium reasoning effort
- **Personal**: Extra-high reasoning effort

## Desktop App Integration

### Claude Desktop App

`aiswitch work` automatically restarts the Claude app with the correct API endpoint injected via `launchctl setenv`. To verify:

```bash
launchctl getenv ANTHROPIC_BASE_URL    # → https://logiq-service.logitech.io/anthropic
launchctl getenv ANTHROPIC_AUTH_TOKEN  # → eyJ... (token)
```

**Note**: Resuming existing conversations uses the model cached in that session. Start a new conversation to use the switched profile.

**Cowork mode**: The Cowork feature uses a native VM that bypasses `ANTHROPIC_BASE_URL` and always connects to `api.anthropic.com` directly. Cowork requests will not appear in the LogiQ dashboard regardless of profile — this is a Cowork architecture limitation.

**After system reboot**: `launchctl setenv` values don't persist across reboots. Run `aiswitch work` again to restore the work profile to desktop apps.

### Codex Desktop App

`aiswitch work` restarts Codex with the updated `~/.codex/config.toml` (work model + LogiQ API key).

## Troubleshooting

### "zsh: command not found: aiswitch"
Reload your shell:
```bash
source ~/.zshrc
```

### "No API keys found"
Add keys with:
```bash
aiswitch keys setup
```

### Desktop app still uses wrong profile after switching
Run `aiswitch work` again — it force-restarts the app. If it still persists, manually restart:
```bash
kill -9 $(pgrep -x "Claude") && open -b "com.anthropic.claudefordesktop"
```
Then verify `launchctl getenv ANTHROPIC_AUTH_TOKEN` shows the token.

### Config not updating
Check the config files were written:
```bash
cat ~/.claude/settings.json
cat ~/.codex/config.toml
```

### Keychain issues
Reset Keychain keys:
```bash
aiswitch keys delete all
aiswitch keys setup
```

## How It Works

- **Profile files** are stored in `~/.claude/` and `~/.codex/`
- **API keys** are stored securely in macOS Keychain (service: LogiQ)
- **State** is tracked in `~/.claude/aiswitch-state`
- On each switch, config files are updated atomically so both CLI and Desktop apps pick up changes immediately

## Requirements

- macOS with zsh (default shell)
- Internet connection (for initial setup)
- Anthropic and/or OpenAI API keys

## Development

See [CLAUDE.md](CLAUDE.md) for architecture details, development workflow, and advanced usage.

## License

MIT
