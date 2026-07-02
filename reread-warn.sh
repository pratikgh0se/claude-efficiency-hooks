#!/usr/bin/env bash
# PreToolUse hook for Read tool.
# Tracks files read per session. Warns Claude when re-reading a file it already has in context.
# Uses /tmp sentinel files keyed by session_id + file_path hash.

set -euo pipefail

INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[ "$TOOL" != "Read" ] && exit 0

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
[ -z "$FILE_PATH" ] || [ -z "$SESSION_ID" ] && exit 0

# Expand ~
FILE_PATH="${FILE_PATH/#\~/$HOME}"

# Hash the file path to a short key
FILE_HASH=$(echo "$FILE_PATH" | md5sum | cut -c1-12)
SENTINEL_DIR="/tmp/reread-track-${SESSION_ID}"
mkdir -p "$SENTINEL_DIR"
SENTINEL="${SENTINEL_DIR}/${FILE_HASH}"

FILENAME=$(basename "$FILE_PATH")

if [ -f "$SENTINEL" ]; then
  COUNT=$(cat "$SENTINEL")
  COUNT=$((COUNT + 1))
  echo "$COUNT" > "$SENTINEL"

  # Only warn starting from 2nd re-read (3rd total read)
  if [ "$COUNT" -ge 2 ]; then
    cat << EOF
{
  "decision": "block",
  "reason": "TOKEN EFFICIENCY: You are re-reading '${FILENAME}' for the $((COUNT + 1))th time this session. The file content is already in your context window — re-reading it wastes input tokens and inflates context size. Instead: reference the content you already read, use grep/Bash to extract specific values, or search your earlier tool results. Only re-read if you need a section you explicitly did NOT read before (specify the line range)."
}
EOF
    exit 0
  fi
else
  echo "1" > "$SENTINEL"
fi

exit 0
