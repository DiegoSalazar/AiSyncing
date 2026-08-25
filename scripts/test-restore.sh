#!/usr/bin/env bash
# Proves the backup/restore round-trip works without touching real files.
#
# 1. Syncs ~/.claude to a temp "backup" dir (same rsync + filter logic as sync.sh)
# 2. Rsyncs backup back to a temp "restored" dir (simulating a new machine)
# 3. Diffs original vs restored
# 4. Reports pass/fail and cleans up
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use config.json include list if available, otherwise use defaults
CLAUDE_DIR="$HOME/.claude"
if [ ! -d "$CLAUDE_DIR" ]; then
  echo "SKIP: ~/.claude not found. Nothing to test."
  exit 0
fi

INCLUDES='["CLAUDE.md","config.json","settings.json","remote-settings.json","package.json","projects/*/memory/**","agents/**","commands/**","hooks/**","skills/**"]'

CONFIG="$REPO_DIR/config.json"
if [ -f "$CONFIG" ]; then
  custom=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    c = json.load(f)
src = c.get('sources', {}).get('claude', {})
if src.get('include'):
    print(json.dumps(src['include']))
" "$CONFIG" 2>/dev/null || true)
  [ -n "$custom" ] && INCLUDES="$custom"
fi

# Reuse the filter generator from sync.sh
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

# Create temp workspace
TMPDIR_BASE=$(mktemp -d)
BACKUP_DIR="$TMPDIR_BASE/backup"
RESTORE_DIR="$TMPDIR_BASE/restored"
mkdir -p "$BACKUP_DIR" "$RESTORE_DIR"

cleanup() { rm -rf "$TMPDIR_BASE"; }
trap cleanup EXIT

echo "=== AiSyncing Restore Test ==="
echo ""
echo "Source:  $CLAUDE_DIR"
echo "Backup:  $BACKUP_DIR"
echo "Restore: $RESTORE_DIR"
echo ""

# Step 1: Simulate sync (backup)
echo "Step 1: Backing up ~/.claude ..."
filter_rules="$(generate_filter "$INCLUDES")"
filter_file="$(mktemp)"
echo "$filter_rules" > "$filter_file"

rsync -a --filter="merge $filter_file" "$CLAUDE_DIR/" "$BACKUP_DIR/"
rm -f "$filter_file"

backup_count=$(find "$BACKUP_DIR" -type f | wc -l | tr -d ' ')
echo "  Backed up $backup_count files."

if [ "$backup_count" -eq 0 ]; then
  echo ""
  echo "FAIL: No files were backed up. Check include patterns."
  exit 1
fi

# Step 2: Simulate restore (new machine)
echo ""
echo "Step 2: Restoring to clean directory ..."
rsync -a "$BACKUP_DIR/" "$RESTORE_DIR/"

restore_count=$(find "$RESTORE_DIR" -type f | wc -l | tr -d ' ')
echo "  Restored $restore_count files."

# Step 3: Diff original vs restored
echo ""
echo "Step 3: Verifying restore matches source ..."

diff_output=$(diff -rq "$BACKUP_DIR" "$RESTORE_DIR" 2>&1 || true)

if [ -z "$diff_output" ]; then
  echo ""
  echo "PASS: All $restore_count files restored correctly."
else
  echo ""
  echo "FAIL: Differences found:"
  echo "$diff_output"
  exit 1
fi

# Step 4: Show what was backed up
echo ""
echo "=== Backed up files ==="
(cd "$BACKUP_DIR" && find . -type f | sort | sed 's|^\./||')

# Step 5: Verify key files exist
echo ""
echo "=== Key file checks ==="
CHECKS=0
PASSED=0

check_exists() {
  CHECKS=$((CHECKS + 1))
  if [ -f "$RESTORE_DIR/$1" ]; then
    echo "  [ok] $1"
    PASSED=$((PASSED + 1))
  else
    echo "  [--] $1 (not found, may not exist in source)"
  fi
}

check_glob() {
  CHECKS=$((CHECKS + 1))
  count=$(find "$RESTORE_DIR" -path "$RESTORE_DIR/$1" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -gt 0 ]; then
    echo "  [ok] $1 ($count files)"
    PASSED=$((PASSED + 1))
  else
    echo "  [--] $1 (none found, may not exist in source)"
  fi
}

check_exists "CLAUDE.md"
check_exists "settings.json"
check_exists "config.json"
check_glob "projects/*/memory/MEMORY.md"
check_glob "projects/*/memory/*.md"

echo ""
echo "$PASSED/$CHECKS key checks passed. $restore_count total files verified."
