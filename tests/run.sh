#!/usr/bin/env bash
# E2E test suite for AiSyncing
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "${GREEN}PASS${NC}: %s\n" "$desc"
    PASS=$((PASS + 1))
  else
    printf "${RED}FAIL${NC}: %s\n" "$desc"
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    printf "${GREEN}PASS${NC}: %s\n" "$desc"
    PASS=$((PASS + 1))
  else
    printf "${RED}FAIL${NC}: %s\n" "$desc"
    echo "  Expected to contain: $needle"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [ -e "$path" ]; then
    printf "${GREEN}PASS${NC}: %s\n" "$desc"
    PASS=$((PASS + 1))
  else
    printf "${RED}FAIL${NC}: %s\n" "$desc"
    echo "  Not found: $path"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists() {
  local desc="$1" path="$2"
  if [ ! -e "$path" ]; then
    printf "${GREEN}PASS${NC}: %s\n" "$desc"
    PASS=$((PASS + 1))
  else
    printf "${RED}FAIL${NC}: %s\n" "$desc"
    echo "  Should not exist: $path"
    FAIL=$((FAIL + 1))
  fi
}

WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

echo "=== AiSyncing Test Suite ==="
echo ""

# ============================================================
echo "--- 1. Filter Generation ---"
# ============================================================

# Extract generate_filter's Python code from sync.sh so tests stay in sync
FILTER_PY=$(sed -n '/^generate_filter()/,/^}/p' "$REPO_DIR/sync.sh" | sed -n '/python3 -c/,/" "\$1"/p' | sed '1s/.*python3 -c "//' | sed '$s/" "\$1"//')

run_filter() {
  python3 -c "$FILTER_PY" "$1"
}

# Simple file patterns
FILTER=$(run_filter '["CLAUDE.md", "config.json"]')
assert_contains "includes CLAUDE.md" "+ /CLAUDE.md" "$FILTER"
assert_contains "includes config.json" "+ /config.json" "$FILTER"
assert_contains "ends with exclude-all" "- *" "$FILTER"

# Nested glob pattern generates parent includes
FILTER=$(run_filter '["projects/*/memory/**"]')
assert_contains "parent: projects/" "+ /projects/" "$FILTER"
assert_contains "parent: projects/*/" "+ /projects/*/" "$FILTER"
assert_contains "parent: projects/*/memory/" "+ /projects/*/memory/" "$FILTER"
assert_contains "leaf: projects/*/memory/**" "+ /projects/*/memory/**" "$FILTER"

# Single-level glob
FILTER=$(run_filter '["agents/**"]')
assert_contains "parent: agents/" "+ /agents/" "$FILTER"
assert_contains "leaf: agents/**" "+ /agents/**" "$FILTER"

# No duplicate rules when patterns share parents
FILTER=$(run_filter '["agents/**", "agents/special.md"]')
AGENT_DIR_COUNT=$(echo "$FILTER" | grep -cx '+ /agents/' || true)
assert_eq "no duplicate parent rules" "1" "$AGENT_DIR_COUNT"

echo ""

# ============================================================
echo "--- 2. Config Reading ---"
# ============================================================

TEST_CONFIG="$WORK_DIR/config.json"
cat > "$TEST_CONFIG" <<'CONF'
{
  "backup_repo": "git@github.com:test/repo.git",
  "commits_url": "https://github.com/test/repo/commits/main",
  "git_user_name": "Test User",
  "git_email": "test@example.com",
  "schedule_hour": 15,
  "sources": {
    "claude": {
      "enabled": true,
      "source_dir": "~/.claude",
      "include": ["CLAUDE.md", "agents/**"]
    },
    "codex": {
      "enabled": false,
      "source_dir": "~/.codex",
      "include": ["AGENTS.md"]
    }
  }
}
CONF

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
" "$TEST_CONFIG" "$1"
}

assert_eq "reads string" "Test User" "$(read_config git_user_name)"
assert_eq "reads email" "test@example.com" "$(read_config git_email)"
assert_eq "reads int" "15" "$(read_config schedule_hour)"
assert_eq "reads nested bool true" "true" "$(read_config sources.claude.enabled)"
assert_eq "reads nested bool false" "false" "$(read_config sources.codex.enabled)"
assert_eq "reads nested string" "~/.claude" "$(read_config sources.claude.source_dir)"

echo ""

# ============================================================
echo "--- 3. E2E Single Source Sync ---"
# ============================================================

# Create fake AI tool directory
FAKE_CLAUDE="$WORK_DIR/fake-claude"
mkdir -p "$FAKE_CLAUDE/projects/proj1/memory"
mkdir -p "$FAKE_CLAUDE/agents"
mkdir -p "$FAKE_CLAUDE/cache"
echo "global instructions" > "$FAKE_CLAUDE/CLAUDE.md"
echo '{"key":"value"}' > "$FAKE_CLAUDE/config.json"
echo "memory content" > "$FAKE_CLAUDE/projects/proj1/memory/MEMORY.md"
echo "agent def" > "$FAKE_CLAUDE/agents/helper.md"
echo "should be excluded" > "$FAKE_CLAUDE/cache/temp.dat"
echo "also excluded" > "$FAKE_CLAUDE/history.jsonl"

# Create bare git remote
BARE_REPO="$WORK_DIR/remote.git"
git init --bare "$BARE_REPO" -b main >/dev/null 2>&1

# Create sync workspace
SYNC_DIR="$WORK_DIR/workspace"
mkdir -p "$SYNC_DIR"
cp "$REPO_DIR/sync.sh" "$SYNC_DIR/"
git -C "$SYNC_DIR" init -b main >/dev/null 2>&1
git -C "$SYNC_DIR" remote add origin "$BARE_REPO"

cat > "$SYNC_DIR/config.json" <<CONF
{
  "backup_repo": "$BARE_REPO",
  "commits_url": "https://example.com/commits",
  "git_user_name": "Test Bot",
  "git_email": "bot@test.com",
  "schedule_hour": 15,
  "sources": {
    "claude": {
      "enabled": true,
      "source_dir": "$FAKE_CLAUDE",
      "include": [
        "CLAUDE.md",
        "config.json",
        "projects/*/memory/**",
        "agents/**"
      ]
    }
  }
}
CONF

bash "$SYNC_DIR/sync.sh" > "$WORK_DIR/sync1.log" 2>&1

# Included files synced
assert_file_exists "syncs CLAUDE.md" "$SYNC_DIR/data/claude/CLAUDE.md"
assert_file_exists "syncs config.json" "$SYNC_DIR/data/claude/config.json"
assert_file_exists "syncs nested memory" "$SYNC_DIR/data/claude/projects/proj1/memory/MEMORY.md"
assert_file_exists "syncs agents" "$SYNC_DIR/data/claude/agents/helper.md"

# Excluded files not synced
assert_file_not_exists "excludes cache/" "$SYNC_DIR/data/claude/cache"
assert_file_not_exists "excludes history.jsonl" "$SYNC_DIR/data/claude/history.jsonl"

# Git commit created with source label
COMMIT_MSG=$(git -C "$SYNC_DIR" log -1 --pretty=%s 2>/dev/null)
assert_contains "commit has sync( prefix" "sync(" "$COMMIT_MSG"
assert_contains "commit has source name" "claude" "$COMMIT_MSG"

# Pushed to remote
REMOTE_COMMITS=$(git -C "$BARE_REPO" log --oneline 2>/dev/null | wc -l | tr -d ' ')
assert_eq "pushed to remote" "1" "$REMOTE_COMMITS"

echo ""

# ============================================================
echo "--- 4. Multi-Source Sync ---"
# ============================================================

# Create second fake source
FAKE_CODEX="$WORK_DIR/fake-codex"
mkdir -p "$FAKE_CODEX/memory"
echo "codex instructions" > "$FAKE_CODEX/AGENTS.md"
echo "codex memory" > "$FAKE_CODEX/memory/context.md"
echo "should be excluded" > "$FAKE_CODEX/cache.db"

cat > "$SYNC_DIR/config.json" <<CONF
{
  "backup_repo": "$BARE_REPO",
  "commits_url": "https://example.com/commits",
  "git_user_name": "Test Bot",
  "git_email": "bot@test.com",
  "schedule_hour": 15,
  "sources": {
    "claude": {
      "enabled": true,
      "source_dir": "$FAKE_CLAUDE",
      "include": ["CLAUDE.md", "config.json", "projects/*/memory/**", "agents/**"]
    },
    "codex": {
      "enabled": true,
      "source_dir": "$FAKE_CODEX",
      "include": ["AGENTS.md", "memory/**"]
    }
  }
}
CONF

bash "$SYNC_DIR/sync.sh" > "$WORK_DIR/sync2.log" 2>&1

assert_file_exists "multi: claude data present" "$SYNC_DIR/data/claude/CLAUDE.md"
assert_file_exists "multi: codex AGENTS.md synced" "$SYNC_DIR/data/codex/AGENTS.md"
assert_file_exists "multi: codex memory synced" "$SYNC_DIR/data/codex/memory/context.md"
assert_file_not_exists "multi: codex cache excluded" "$SYNC_DIR/data/codex/cache.db"

COMMIT_MSG=$(git -C "$SYNC_DIR" log -1 --pretty=%s 2>/dev/null)
assert_contains "multi: commit has claude" "claude" "$COMMIT_MSG"
assert_contains "multi: commit has codex" "codex" "$COMMIT_MSG"

echo ""

# ============================================================
echo "--- 5. Idempotent (no changes = no commit) ---"
# ============================================================

BEFORE=$(git -C "$BARE_REPO" log --oneline 2>/dev/null | wc -l | tr -d ' ')
bash "$SYNC_DIR/sync.sh" > "$WORK_DIR/sync3.log" 2>&1
AFTER=$(git -C "$BARE_REPO" log --oneline 2>/dev/null | wc -l | tr -d ' ')

assert_eq "no changes = no new commit" "$BEFORE" "$AFTER"
assert_contains "logs nothing changed" "Nothing changed" "$(cat "$WORK_DIR/sync3.log")"

echo ""

# ============================================================
echo "--- 6. Disabled Source Skipped ---"
# ============================================================

FAKE_GEMINI="$WORK_DIR/fake-gemini"
mkdir -p "$FAKE_GEMINI"
echo "gemini config" > "$FAKE_GEMINI/GEMINI.md"

cat > "$SYNC_DIR/config.json" <<CONF
{
  "backup_repo": "$BARE_REPO",
  "commits_url": "https://example.com/commits",
  "git_user_name": "Test Bot",
  "git_email": "bot@test.com",
  "schedule_hour": 15,
  "sources": {
    "claude": {
      "enabled": true,
      "source_dir": "$FAKE_CLAUDE",
      "include": ["CLAUDE.md"]
    },
    "gemini": {
      "enabled": false,
      "source_dir": "$FAKE_GEMINI",
      "include": ["GEMINI.md"]
    }
  }
}
CONF

bash "$SYNC_DIR/sync.sh" > "$WORK_DIR/sync4.log" 2>&1
assert_file_not_exists "disabled source not synced" "$SYNC_DIR/data/gemini"

echo ""

# ============================================================
echo "--- 7. Missing Source Dir Skipped Gracefully ---"
# ============================================================

cat > "$SYNC_DIR/config.json" <<CONF
{
  "backup_repo": "$BARE_REPO",
  "commits_url": "https://example.com/commits",
  "git_user_name": "Test Bot",
  "git_email": "bot@test.com",
  "schedule_hour": 15,
  "sources": {
    "claude": {
      "enabled": true,
      "source_dir": "$FAKE_CLAUDE",
      "include": ["CLAUDE.md"]
    },
    "ghost": {
      "enabled": true,
      "source_dir": "/tmp/aisyncing-does-not-exist",
      "include": ["*.md"]
    }
  }
}
CONF

bash "$SYNC_DIR/sync.sh" > "$WORK_DIR/sync5.log" 2>&1
assert_contains "logs skip for missing dir" "Skipping ghost" "$(cat "$WORK_DIR/sync5.log")"
assert_file_exists "existing source still syncs" "$SYNC_DIR/data/claude/CLAUDE.md"

echo ""

# ============================================================
echo "--- 8. Source Changes Detected ---"
# ============================================================

echo "updated content" > "$FAKE_CLAUDE/CLAUDE.md"
bash "$SYNC_DIR/sync.sh" > "$WORK_DIR/sync6.log" 2>&1

SYNCED_CONTENT=$(cat "$SYNC_DIR/data/claude/CLAUDE.md")
assert_eq "picks up file changes" "updated content" "$SYNCED_CONTENT"

echo ""

# ============================================================
echo "--- 9. Deleted Files Removed from Backup ---"
# ============================================================

# Restore full include list so rsync manages agents/ and can detect deletions
cat > "$SYNC_DIR/config.json" <<CONF
{
  "backup_repo": "$BARE_REPO",
  "commits_url": "https://example.com/commits",
  "git_user_name": "Test Bot",
  "git_email": "bot@test.com",
  "schedule_hour": 15,
  "sources": {
    "claude": {
      "enabled": true,
      "source_dir": "$FAKE_CLAUDE",
      "include": ["CLAUDE.md", "config.json", "projects/*/memory/**", "agents/**"]
    }
  }
}
CONF

rm -f "$FAKE_CLAUDE/agents/helper.md"
bash "$SYNC_DIR/sync.sh" > "$WORK_DIR/sync7.log" 2>&1

assert_file_not_exists "deleted file removed from backup" "$SYNC_DIR/data/claude/agents/helper.md"

echo ""

# ============================================================
echo "--- 10. No Config = Exit with Error ---"
# ============================================================

NO_CONFIG_DIR="$WORK_DIR/no-config"
mkdir -p "$NO_CONFIG_DIR"
cp "$REPO_DIR/sync.sh" "$NO_CONFIG_DIR/"

OUTPUT=$(bash "$NO_CONFIG_DIR/sync.sh" 2>&1 || true)
assert_contains "missing config error" "No config.json found" "$OUTPUT"

echo ""

# ============================================================
# Summary
# ============================================================
echo "==========================="
TOTAL=$((PASS + FAIL))
echo "Tests: $TOTAL | Pass: $PASS | Fail: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  printf "${RED}FAILED${NC}\n"
  exit 1
else
  printf "${GREEN}ALL PASSED${NC}\n"
  exit 0
fi
