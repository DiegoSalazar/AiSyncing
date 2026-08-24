#!/usr/bin/env bash
# Interactive setup: creates a private backup repo, writes config, and installs daily sync.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"

echo "=== AI Syncing Setup ==="
echo ""
echo "Automatic daily backups of your AI tool memories, configs, and instruction files."
echo ""

# --- Prerequisites ---
for cmd in gh git python3 rsync; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is required but not found."
    exit 1
  fi
done

if ! gh auth status &>/dev/null 2>&1; then
  echo "Error: Not authenticated with GitHub. Run: gh auth login"
  exit 1
fi

GH_USER=$(gh api user --jq .login)
echo "GitHub user: $GH_USER"

# --- Backup repo ---
echo ""
DEFAULT_REPO_NAME="ai-backup"
read -rp "Backup repo name [$DEFAULT_REPO_NAME]: " REPO_NAME
REPO_NAME="${REPO_NAME:-$DEFAULT_REPO_NAME}"
FULL_REPO="$GH_USER/$REPO_NAME"

if gh repo view "$FULL_REPO" &>/dev/null 2>&1; then
  echo "Repo $FULL_REPO already exists."
else
  echo "Creating private repo $FULL_REPO..."
  gh repo create "$REPO_NAME" --private --description "AI harness memory and config backup (powered by AiSyncing)"
  echo "Created."
fi

GH_PROTOCOL=$(gh config get git_protocol 2>/dev/null || echo "https")
if [ "$GH_PROTOCOL" = "ssh" ]; then
  REPO_URL="git@github.com:${FULL_REPO}.git"
else
  REPO_URL="https://github.com/${FULL_REPO}.git"
fi
COMMITS_URL="https://github.com/${FULL_REPO}/commits/main"

# --- Git identity ---
echo ""
DEFAULT_NAME=$(git config --global user.name 2>/dev/null || echo "")
DEFAULT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

read -rp "Git name [$DEFAULT_NAME]: " GIT_NAME
GIT_NAME="${GIT_NAME:-$DEFAULT_NAME}"

read -rp "Git email [$DEFAULT_EMAIL]: " GIT_EMAIL
GIT_EMAIL="${GIT_EMAIL:-$DEFAULT_EMAIL}"

# --- Detect AI tools ---
echo ""
echo "Detecting installed AI tools..."

CLAUDE_ENABLED=false
CODEX_ENABLED=false
GEMINI_ENABLED=false

[ -d "$HOME/.claude" ] && CLAUDE_ENABLED=true
[ -d "$HOME/.codex" ]  && CODEX_ENABLED=true
[ -d "$HOME/.gemini" ] && GEMINI_ENABLED=true

echo ""
printf "  %s Claude Code  (~/.claude)\n" "$([ "$CLAUDE_ENABLED" = true ] && echo '[x]' || echo '[ ]')"
printf "  %s OpenAI Codex (~/.codex)\n"  "$([ "$CODEX_ENABLED"  = true ] && echo '[x]' || echo '[ ]')"
printf "  %s Gemini CLI   (~/.gemini)\n" "$([ "$GEMINI_ENABLED" = true ] && echo '[x]' || echo '[ ]')"
echo ""

# --- Schedule ---
read -rp "Daily sync hour (0-23) [15]: " SCHEDULE_HOUR
SCHEDULE_HOUR="${SCHEDULE_HOUR:-15}"

# --- Write config ---
cat > "$CONFIG" <<CONF
{
  "backup_repo": "$REPO_URL",
  "commits_url": "$COMMITS_URL",
  "git_user_name": "$GIT_NAME",
  "git_email": "$GIT_EMAIL",
  "schedule_hour": $SCHEDULE_HOUR,
  "sources": {
    "claude": {
      "enabled": $CLAUDE_ENABLED,
      "source_dir": "~/.claude",
      "include": [
        "CLAUDE.md",
        "config.json",
        "settings.json",
        "remote-settings.json",
        "package.json",
        "projects/*/memory/**",
        "agents/**",
        "commands/**",
        "hooks/**",
        "skills/**"
      ]
    },
    "codex": {
      "enabled": $CODEX_ENABLED,
      "source_dir": "~/.codex",
      "include": [
        "instructions.md",
        "AGENTS.md",
        "config.json",
        "config.yaml",
        "agents/**",
        "memory/**"
      ]
    },
    "gemini": {
      "enabled": $GEMINI_ENABLED,
      "source_dir": "~/.gemini",
      "include": [
        "GEMINI.md",
        "settings.json",
        "config.json",
        "config.yaml",
        "memory/**",
        "styles/**"
      ]
    }
  }
}
CONF
echo "Config written to config.json"

# --- Build notification helper (macOS) ---
if [ "$(uname)" = "Darwin" ]; then
  echo ""
  echo "Building notification helper..."
  APP_DIR="$SCRIPT_DIR/AiSyncing.app"
  mkdir -p "$APP_DIR/Contents/MacOS"

  cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.aisyncing.notifier</string>
    <key>CFBundleName</key>
    <string>AI Syncing</string>
    <key>CFBundleExecutable</key>
    <string>AiSyncing</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

  swiftc -o "$APP_DIR/Contents/MacOS/AiSyncing" "$SCRIPT_DIR/notifier.swift" \
    -framework Cocoa -framework UserNotifications
  codesign --force --sign - "$APP_DIR"
  echo "Built AiSyncing.app"

  # --- Install LaunchAgent ---
  echo ""
  PLIST_LABEL="com.aisyncing.daily"
  PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${SCRIPT_DIR}/sync.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>${SCHEDULE_HOUR}</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>StandardOutPath</key>
    <string>${HOME}/Library/Logs/ai-syncing.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/Library/Logs/ai-syncing.log</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
PLIST

  launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
  echo "LaunchAgent installed (daily at ${SCHEDULE_HOUR}:00)"
fi

# --- Configure git remote ---
echo ""
echo "Configuring git remote..."

CURRENT_ORIGIN=$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || echo "")

# If origin points to the AiSyncing template, save it as upstream for updates
if [[ "$CURRENT_ORIGIN" == *"AiSyncing"* ]] && [[ "$CURRENT_ORIGIN" != "$REPO_URL" ]]; then
  git -C "$SCRIPT_DIR" remote rename origin upstream 2>/dev/null || true
  echo "Template saved as 'upstream' remote (for future updates)."
fi

if git -C "$SCRIPT_DIR" remote get-url origin &>/dev/null 2>&1; then
  git -C "$SCRIPT_DIR" remote set-url origin "$REPO_URL"
else
  git -C "$SCRIPT_DIR" remote add origin "$REPO_URL"
fi
echo "Remote origin: $REPO_URL"

# --- Initial push ---
echo ""
git -C "$SCRIPT_DIR" config --local user.email "$GIT_EMAIL"
git -C "$SCRIPT_DIR" config --local user.name "$GIT_NAME"
git -C "$SCRIPT_DIR" add -A

if git -C "$SCRIPT_DIR" diff --cached --quiet 2>/dev/null; then
  echo "No changes to commit."
else
  git -C "$SCRIPT_DIR" commit -m "setup: configure AI Syncing"
fi

git -C "$SCRIPT_DIR" push -u origin main 2>&1 || echo "Push will happen on next sync."

echo ""
echo "=== Setup complete ==="
echo ""
echo "Backup repo:  https://github.com/$FULL_REPO"
echo "Daily sync:   ${SCHEDULE_HOUR}:00"
echo "Manual sync:  bash $SCRIPT_DIR/sync.sh"
echo "Logs:         ~/Library/Logs/ai-syncing.log"
if [ "$(uname)" = "Darwin" ]; then
  echo ""
  echo "On first notification, macOS will ask to allow notifications from AI Syncing."
fi
