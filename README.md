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

Profile switching takes effect on the **next conversation**. To test:

1. Run: `aiswitch work`
2. Open Claude Desktop app
3. Start a **new** conversation (not resuming old one)
4. Verify it shows Sonnet model (work default)
5. Run: `aiswitch personal`
6. Start another **new** conversation
7. Verify it shows Sonnet model (personal default)

**Note**: Resuming existing conversations may use the model stored in that session, not the new profile.

### Codex Desktop App

Same workflow—new sessions pick up the new profile.

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

### Desktop app doesn't pick up new profile
- Make sure you started a **new** conversation (not resuming)
- Desktop apps read config on startup, not mid-session
- Try fully quitting the app (⌘Q) and reopening

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
