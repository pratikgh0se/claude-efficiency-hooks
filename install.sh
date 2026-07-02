#!/usr/bin/env bash
# Installs claude-efficiency-hooks into ~/.claude/hooks
# and patches ~/.claude/settings.json

set -euo pipefail

HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing hooks to $HOOKS_DIR"
mkdir -p "$HOOKS_DIR"

for hook in context-monitor-stop.sh bash-cat-block.sh reread-warn.sh; do
  cp "$SCRIPT_DIR/$hook" "$HOOKS_DIR/$hook"
  chmod +x "$HOOKS_DIR/$hook"
  echo "    Installed $hook"
done

# Check for jq
if ! command -v jq &>/dev/null; then
  echo "WARNING: jq not found. Install it: brew install jq / apt install jq"
fi

# Check for md5sum (macOS ships md5, not md5sum)
if ! command -v md5sum &>/dev/null; then
  echo "WARNING: md5sum not found."
  echo "  Install coreutils: brew install coreutils"
  echo "  Or patch reread-warn.sh line 21: replace md5sum with md5"
fi

echo ""
echo "==> Hooks installed."
echo ""
echo "Next step: add the following to your ~/.claude/settings.json hooks section:"
echo ""
cat << 'JSON'
"Stop": [
  {
    "matcher": "*",
    "hooks": [
      {
        "type": "command",
        "command": "$HOME/.claude/hooks/context-monitor-stop.sh",
        "async": false
      }
    ]
  }
],
"PreToolUse": [
  {
    "matcher": "Bash",
    "hooks": [
      {
        "type": "command",
        "command": "$HOME/.claude/hooks/bash-cat-block.sh"
      }
    ]
  },
  {
    "matcher": "Read",
    "hooks": [
      {
        "type": "command",
        "command": "$HOME/.claude/hooks/reread-warn.sh"
      }
    ]
  }
]
JSON

echo ""
echo "See README.md for the full settings.json merge and CLAUDE.md rules."
