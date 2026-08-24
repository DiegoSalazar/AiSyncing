#!/usr/bin/env bash
# Removes the AI Syncing LaunchAgent and compiled app.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Uninstalling AI Syncing..."

if [ "$(uname)" = "Darwin" ]; then
  PLIST_LABEL="com.aisyncing.daily"
  PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

  launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null && echo "Agent stopped." || echo "Agent was not running."

  [ -f "$PLIST_PATH" ] && rm "$PLIST_PATH" && echo "Removed LaunchAgent."
  [ -d "$SCRIPT_DIR/AiSyncing.app" ] && rm -rf "$SCRIPT_DIR/AiSyncing.app" && echo "Removed AiSyncing.app."
fi

echo "Done. Run setup.sh to reinstall."
echo "Your backup data in data/ and config.json are untouched."
