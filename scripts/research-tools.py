#!/usr/bin/env python3
"""
Checks official AI tool documentation for changes that might affect our
config defaults. Uses hash-based change detection on known doc URLs.

When a doc page changes or becomes unreachable, it flags the tool for
human review. Does NOT auto-modify config files.

Exit 0 = no changes. Exit 1 = changes detected (triggers issue creation in CI).
"""

import hashlib
import json
import os
import sys
import urllib.request
import urllib.error

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HASHES_FILE = os.path.join(REPO_ROOT, "scripts", "doc-hashes.json")

# Verified doc URLs per tool. Key = tool name, value = list of (label, url).
# These are raw GitHub URLs or stable doc pages we monitor for changes.
DOC_URLS = {
    "claude": [
        ("README", "https://raw.githubusercontent.com/anthropics/claude-code/refs/heads/main/README.md"),
    ],
    "codex": [
        ("AGENTS.md guide", "https://raw.githubusercontent.com/openai/codex/refs/heads/main/docs/agents_md.md"),
        ("Config docs", "https://raw.githubusercontent.com/openai/codex/refs/heads/main/docs/config.md"),
        ("Skills docs", "https://raw.githubusercontent.com/openai/codex/refs/heads/main/docs/skills.md"),
    ],
    "gemini": [
        ("Configuration ref", "https://raw.githubusercontent.com/google-gemini/gemini-cli/refs/heads/main/docs/reference/configuration.md"),
        ("GEMINI.md guide", "https://raw.githubusercontent.com/google-gemini/gemini-cli/refs/heads/main/docs/cli/gemini-md.md"),
        ("Memory tool", "https://raw.githubusercontent.com/google-gemini/gemini-cli/refs/heads/main/docs/tools/memory.md"),
        ("Custom commands", "https://raw.githubusercontent.com/google-gemini/gemini-cli/refs/heads/main/docs/cli/custom-commands.md"),
        ("Settings", "https://raw.githubusercontent.com/google-gemini/gemini-cli/refs/heads/main/docs/cli/settings.md"),
    ],
    "cursor": [
        ("Rules docs", "https://docs.cursor.com/context/rules"),
    ],
}


def fetch(url, timeout=15):
    """Fetch URL content. Returns (content, status) or (None, error_string)."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "AiSyncing/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read().decode("utf-8", errors="replace"), resp.status
    except urllib.error.HTTPError as e:
        return None, f"HTTP {e.code}"
    except (urllib.error.URLError, OSError) as e:
        return None, str(e)


def sha256(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def load_hashes():
    if os.path.exists(HASHES_FILE):
        with open(HASHES_FILE) as f:
            return json.load(f)
    return {}


def save_hashes(hashes):
    with open(HASHES_FILE, "w") as f:
        json.dump(hashes, f, indent=2, sort_keys=True)
        f.write("\n")


def main():
    old_hashes = load_hashes()
    new_hashes = {}
    changes = {}  # tool -> list of change descriptions

    for tool, urls in DOC_URLS.items():
        tool_changes = []

        for label, url in urls:
            key = f"{tool}:{label}"
            content, status = fetch(url)

            if content is None:
                new_hashes[key] = f"error:{status}"
                if old_hashes.get(key, "").startswith("error:"):
                    pass  # was already broken, don't re-flag
                else:
                    tool_changes.append(f"**{label}** became unreachable ({status}). URL may have moved.")
                print(f"  SKIP {tool}/{label}: {status}", file=sys.stderr)
            else:
                h = sha256(content)
                new_hashes[key] = h
                old_h = old_hashes.get(key)

                if old_h is None:
                    print(f"  NEW  {tool}/{label}: {h}", file=sys.stderr)
                elif old_h.startswith("error:"):
                    tool_changes.append(f"**{label}** is reachable again. Review for config changes.")
                    print(f"  BACK {tool}/{label}: was {old_h}, now {h}", file=sys.stderr)
                elif old_h != h:
                    tool_changes.append(f"**{label}** content changed (was `{old_h}`, now `{h}`). Review for config/directory structure updates.")
                    print(f"  CHANGED {tool}/{label}: {old_h} -> {h}", file=sys.stderr)
                else:
                    print(f"  OK   {tool}/{label}: {h}", file=sys.stderr)

        if tool_changes:
            changes[tool] = tool_changes

    save_hashes(new_hashes)

    if not changes:
        print("\nNo doc changes detected.", file=sys.stderr)
        report = "# AI Tool Config Research Report\n\nNo documentation changes detected. All include lists are current.\n"
        write_report(report)
        return 0

    report = build_report(changes)
    write_report(report)
    print(f"\nChanges detected in {len(changes)} tool(s). See research-report.md", file=sys.stderr)
    return 1


def build_report(changes):
    lines = ["# AI Tool Config Research Report\n"]
    lines.append(f"Documentation changes detected in **{len(changes)}** tool(s). ")
    lines.append("Review the changes below and update `config.example.json` and `setup.sh` if the tool's config structure changed.\n")

    for tool, items in changes.items():
        lines.append(f"## {tool.title()}\n")
        for item in items:
            lines.append(f"- {item}")
        lines.append("")

    doc_urls = []
    for tool in changes:
        for label, url in DOC_URLS.get(tool, []):
            doc_urls.append(f"- [{tool.title()}: {label}]({url})")

    if doc_urls:
        lines.append("### Doc URLs to review\n")
        lines.extend(doc_urls)
        lines.append("")

    lines.append("---\n")
    lines.append("*Auto-generated by `scripts/research-tools.py`. Run `python3 scripts/research-tools.py` locally to refresh hashes after reviewing.*\n")
    return "\n".join(lines)


def write_report(report):
    path = os.path.join(REPO_ROOT, "research-report.md")
    with open(path, "w") as f:
        f.write(report)


if __name__ == "__main__":
    sys.exit(main())
