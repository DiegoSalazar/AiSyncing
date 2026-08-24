# AiSyncing

Automatic daily backups of your AI coding assistant memories, configs, and instruction files to a private GitHub repo.

Supports **Claude Code**, **OpenAI Codex**, **Gemini CLI**, and any custom AI tool you add.

## What it backs up

AI coding assistants store persistent memories, custom agents, instruction files, and config locally. This tool syncs them to a private GitHub repo daily so you never lose them and can restore on any machine.

**Default include lists per tool:**

| Tool | Files backed up |
|------|----------------|
| Claude Code | `CLAUDE.md`, `settings.json`, `config.json`, `projects/*/memory/**`, `agents/**`, `commands/**`, `hooks/**`, `skills/**` |
| OpenAI Codex | `instructions.md`, `AGENTS.md`, `config.json`, `agents/**`, `memory/**` |
| Gemini CLI | `GEMINI.md`, `settings.json`, `config.json`, `memory/**`, `styles/**` |

All include lists are configurable in `config.json`. Add any file pattern you want.

## Requirements

- macOS (for notifications and scheduled sync via LaunchAgent)
- [GitHub CLI](https://cli.github.com/) (`brew install gh`) - authenticated
- `git`, `python3`, `rsync` (pre-installed on macOS)

## Quick start

```bash
git clone https://github.com/DiegoSalazar/AiSyncing.git ~/AiSyncing
cd ~/AiSyncing
bash setup.sh
```

Setup will:

1. Ask which AI tools to back up (auto-detects installed ones)
2. Create a private GitHub repo for your backups
3. Compile a native macOS notification helper (click notifications to open your backup)
4. Install a LaunchAgent for daily scheduled sync
5. Push the initial backup

## Manual sync

```bash
bash ~/AiSyncing/sync.sh
```

## Configuration

Everything is in `config.json` (created by setup). See `config.example.json` for the full schema.

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

Patterns follow rsync include syntax. Anything not matched is excluded.

### Adding a custom AI tool

Add a new entry to `sources`:

```json
{
  "sources": {
    "cursor": {
      "enabled": true,
      "source_dir": "~/.cursor",
      "include": [
        ".cursorrules",
        "config.json",
        "memory/**"
      ]
    }
  }
}
```

### Changing the schedule

Edit `schedule_hour` in `config.json`, then re-run `bash setup.sh` to update the LaunchAgent.

## Notifications

On macOS, each sync sends a notification showing the result. Click it to open your backup's commit history on GitHub.

On first run, macOS will ask to allow notifications from "AI Syncing". Click Allow.

Logs are written to `~/Library/Logs/ai-syncing.log`.

## Restore

```bash
git clone git@github.com:you/ai-backup.git ~/AiSyncing
# Copy data back to the source directories:
rsync -av ~/AiSyncing/data/claude/ ~/.claude/
rsync -av ~/AiSyncing/data/codex/ ~/.codex/
# Re-enable scheduled sync:
bash ~/AiSyncing/setup.sh
```

## Uninstall

```bash
bash ~/AiSyncing/uninstall.sh
```

Stops the LaunchAgent and removes the compiled notification app. Your backup data and config are left in place.

## Updating

If you kept the template as an `upstream` remote (setup does this automatically):

```bash
cd ~/AiSyncing
git fetch upstream
git merge upstream/main
```

## License

MIT
