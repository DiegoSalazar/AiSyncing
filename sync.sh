#!/usr/bin/env bash
# Syncs AI harness memories and config to a private GitHub repo.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$REPO_DIR/config.json"

if [ ! -f "$CONFIG" ]; then
  echo "No config.json found. Run setup.sh first."
  exit 1
fi

# Read a config value by dot-separated path
read_config() {
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    c = json.load(f)
keys = sys.argv[2].split('.')
v = c
for k in keys:
    v = v[k] if isinstance(v, dict) else v[int(k)]
if isinstance(v, bool):
    print('true' if v else 'false')
elif isinstance(v, (dict, list)):
    print(json.dumps(v))
else:
    print(v)
" "$CONFIG" "$1"
}

GIT_NAME="$(read_config git_user_name)"
GIT_EMAIL="$(read_config git_email)"
COMMITS_URL="$(read_config commits_url)"

# Ensure SSH agent is reachable in LaunchAgent context
if [ -z "${SSH_AUTH_SOCK:-}" ]; then
  _sock="$(launchctl getenv SSH_AUTH_SOCK 2>/dev/null || true)"
  [ -n "$_sock" ] && export SSH_AUTH_SOCK="$_sock"
fi

notify() {
  local title="$1" message="$2" url="${3:-}"
  if [ -d "$REPO_DIR/AiSyncing.app" ]; then
    open "$REPO_DIR/AiSyncing.app" --args "$title" "$message" "$url"
  else
    osascript -e "display notification \"$message\" with title \"$title\" sound name \"default\"" 2>/dev/null || true
  fi
}

# Generate rsync filter rules from an include list.
# Automatically adds parent directory includes for nested paths.
generate_filter() {
  python3 -c "
import json, sys
includes = json.loads(sys.argv[1])
seen = set()
rules = []
for pattern in includes:
    parts = pattern.rstrip('/').split('/')
    for i in range(1, len(parts)):
        parent = '/'.join(parts[:i])
        rule = '+ /' + parent + '/'
        if rule not in seen:
            rules.append(rule)
            seen.add(rule)
    rule = '+ /' + pattern
    if rule not in seen:
        rules.append(rule)
        seen.add(rule)
rules.append('- *')
print('\n'.join(rules))
" "$1"
}

# Sync each enabled source
SOURCES=$(python3 -c "
import json, sys, os
with open(sys.argv[1]) as f:
    c = json.load(f)
for name, src in c.get('sources', {}).items():
    if src.get('enabled', False):
        d = os.path.expanduser(src['source_dir'])
        inc = json.dumps(src.get('include', []))
        print(name + '|' + d + '|' + inc)
" "$CONFIG")

SYNCED=0
SYNCED_NAMES=()

while IFS='|' read -r name source_dir includes_json; do
  [ -z "$name" ] && continue

  if [ ! -d "$source_dir" ]; then
    echo "Skipping $name: $source_dir not found"
    continue
  fi

  dest="$REPO_DIR/data/$name"
  mkdir -p "$dest"

  # Generate filter from include list
  filter_rules="$(generate_filter "$includes_json")"
  filter_file="$(mktemp)"
  echo "$filter_rules" > "$filter_file"

  echo "Syncing $name..."
  if rsync -av --delete --filter="merge $filter_file" "$source_dir/" "$dest/"; then
    SYNCED=$((SYNCED + 1))
    SYNCED_NAMES+=("$name")
  else
    echo "Warning: rsync failed for $name"
  fi

  rm -f "$filter_file"
done <<< "$SOURCES"

if [ "$SYNCED" -eq 0 ]; then
  notify "AI Syncing" "No sources synced - check config.json"
  exit 1
fi

SOURCES_LABEL=$(IFS=,; echo "${SYNCED_NAMES[*]}")

cd "$REPO_DIR"

git config --local user.email "$GIT_EMAIL"
git config --local user.name "$GIT_NAME"

if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  notify "AI Syncing" "Nothing changed - already up to date" "$COMMITS_URL"
  echo "Nothing changed."
  exit 0
fi

git add -A
COMMIT_MSG="sync($SOURCES_LABEL): $(date '+%Y-%m-%d %H:%M:%S')"
git commit -m "$COMMIT_MSG"

if git push -u origin main; then
  notify "AI Syncing" "Pushed: $COMMIT_MSG" "$COMMITS_URL"
else
  notify "AI Syncing Failed" "Push failed - check connection or logs"
  exit 1
fi

echo "Done."
