<p align="center">
  <img src="logo.svg" alt="AiSyncing logo" width="160">
</p>

<h1 align="center">AiSyncing</h1>

<p align="center">
  <a href="https://github.com/DiegoSalazar/AiSyncing/actions/workflows/test.yml"><img src="https://github.com/DiegoSalazar/AiSyncing/actions/workflows/test.yml/badge.svg" alt="Tests"></a>
</p>

Automatic daily backups of your AI coding assistant memories, configs, and instruction files to a private GitHub repo.

Supports **Claude Code**, **OpenAI Codex**, **Gemini CLI**, **Cursor**, and any custom AI tool you add.

## Features

- **Multi-tool**: backs up multiple AI harnesses simultaneously (Claude, Codex, Gemini, Cursor, Windsurf, or anything with a local config directory)
- **Auto-setup**: interactive `setup.sh` detects installed AI tools, creates a private GitHub backup repo, and configures everything
- **Configurable allow list**: per-source `include` patterns in `config.json` control exactly which files get backed up. Sane defaults for the top AI tools out of the box.
- **Daily scheduled sync**: macOS LaunchAgent runs at your chosen hour. Each commit shows which sources changed: `sync(claude,codex): 2026-08-24 15:00:00`
- **Native macOS notifications**: a compiled Swift helper app shows banner notifications on each sync. Click to open your backup's commit history on GitHub.
- **Restore anywhere**: clone your backup repo on a new machine and rsync the data back

## What it backs up

AI coding assistants store persistent memories, custom agents, instruction files, and config locally. This tool syncs them to a private GitHub repo so you never lose them.

**Default include lists per tool:**

| Tool | Source directory | Files backed up |
|------|----------------|-----------------|
| Claude Code | `~/.claude` | `CLAUDE.md`, `settings.json`, `config.json`, `projects/*/memory/**`, `agents/**`, `commands/**`, `hooks/**`, `skills/**` |
| OpenAI Codex | `~/.codex` | `instructions.md`, `AGENTS.md`, `config.json`, `agents/**`, `memory/**` |
| Gemini CLI | `~/.gemini` | `GEMINI.md`, `settings.json`, `config.json`, `memory/**`, `styles/**` |
| Cursor | `~/.cursor` | `rules/**`, `prompts/**`, `memories/**`, `config.json`, `settings.json` |

Setup auto-detects which tools are installed and enables them. All include lists are fully configurable.

## Requirements

- macOS (for notifications and scheduled sync via LaunchAgent)
- [GitHub CLI](https://cli.github.com/) (`brew install gh`), authenticated
- `git`, `python3`, `rsync` (pre-installed on macOS)

## Quick start

```bash
git clone https://github.com/DiegoSalazar/AiSyncing.git ~/AiSyncing
cd ~/AiSyncing
bash setup.sh
```

Setup will walk you through:

1. **Backup repo**: picks a name, auto-creates a private GitHub repo via `gh`
2. **Git identity**: name and email for backup commits (defaults to your global git config)
3. **AI tools**: auto-detects installed tools by checking for their config directories
4. **Schedule**: which hour to run the daily sync (default: 3 PM)
5. **Build and install**: compiles the notification helper, installs the LaunchAgent, pushes the initial backup

The AiSyncing template repo is saved as the `upstream` remote so you can pull updates later.

## Manual sync

```bash
bash ~/AiSyncing/sync.sh
```

## How it works

1. For each enabled source, `sync.sh` reads the `include` list from `config.json`
2. Generates rsync filter rules at runtime (auto-includes parent directories for nested patterns)
3. Rsyncs each source directory into `data/<source>/`
4. Commits with a message showing which sources changed: `sync(claude,gemini): 2026-08-24 15:00:00`
5. Pushes to your private backup repo
6. Sends a macOS notification (click to open commit history)

Sources with missing directories are skipped with a warning, not fatal. If no sources sync, you get a notification about it.

## Configuration

Everything is in `config.json` (created by `setup.sh`). See `config.example.json` for the full schema.

### Changing what gets backed up

Each source has an `include` array of glob patterns. Edit it to add or remove files:

```json
{
  "sources": {
    "claude": {
      "enabled": true,
      "source_dir": "~/.claude",
      "include": [
        "CLAUDE.md",
        "projects/*/memory/**",
        "agents/**",
        "my-custom-dir/**"
      ]
    }
  }
}
```

Patterns follow rsync include syntax. Parent directories are auto-included for nested paths. Anything not matched is excluded.

### Adding a custom AI tool

Add a new entry to `sources` with any name, its config directory, and the files you want backed up. For example, to add Windsurf (Codeium):

```json
{
  "sources": {
    "windsurf": {
      "enabled": true,
      "source_dir": "~/.codeium/windsurf",
      "include": [
        ".windsurfrules",
        "memories/**",
        "config.json",
        "settings.json",
        "prompts/**"
      ]
    }
  }
}
```

The sync script handles any number of sources. Each gets its own `data/<name>/` subdirectory in the backup.

### Changing the schedule

Edit `schedule_hour` in `config.json`, then re-run `bash setup.sh` to update the LaunchAgent.

## Notifications

On macOS, each sync sends a banner notification showing the result. Click it to open your backup's commit history on GitHub.

The notification helper is a minimal Swift app (`notifier.swift`) compiled into `AiSyncing.app` during setup. It runs as a background process (no dock icon) and uses macOS UserNotifications for proper banner support with click actions.

On first notification, macOS will ask to allow notifications from "AI Syncing". Click Allow.

Falls back to `osascript` if the app isn't built (no click-to-open in fallback mode).

Logs: `~/Library/Logs/ai-syncing.log`

## Restore

Clone your backup repo on a new machine and copy the data back:

```bash
git clone git@github.com:you/ai-backup.git ~/AiSyncing
rsync -av ~/AiSyncing/data/claude/ ~/.claude/
rsync -av ~/AiSyncing/data/codex/ ~/.codex/
rsync -av ~/AiSyncing/data/gemini/ ~/.gemini/
rsync -av ~/AiSyncing/data/cursor/ ~/.cursor/
# Re-enable scheduled sync:
bash ~/AiSyncing/setup.sh
```

## Uninstall

```bash
bash ~/AiSyncing/uninstall.sh
```

Stops the LaunchAgent and removes the compiled notification app. Your backup data and config are left in place.

## Updating

Setup saves the AiSyncing template as the `upstream` remote:

```bash
cd ~/AiSyncing
git fetch upstream
git merge upstream/main
```

## License

MIT
