#!/usr/bin/env bash
# PreToolUse hook for Read tool.
# Tracks files read per session and blocks repeated full rereads.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/efficiency-common.sh" ]; then
  # shellcheck source=lib/efficiency-common.sh
  . "$SCRIPT_DIR/lib/efficiency-common.sh"
fi

INPUT=$(cat)

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[ "$TOOL" != "Read" ] && exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
if [ -z "$FILE_PATH" ] || [ -z "$SESSION_ID" ]; then
  exit 0
fi

FILE_PATH="${FILE_PATH/#\~/$HOME}"

hash_key() {
  if command -v md5sum >/dev/null 2>&1; then
    printf '%s' "$1" | md5sum | awk '{print substr($1, 1, 12)}'
  elif command -v md5 >/dev/null 2>&1; then
    printf '%s' "$1" | md5 -q | cut -c1-12
  else
    printf '%s' "$1" | cksum | awk '{print $1}'
  fi
}

FILE_HASH="$(hash_key "$FILE_PATH")"
SENTINEL_DIR="${TMPDIR:-/tmp}/reread-track-${SESSION_ID}"
mkdir -p "$SENTINEL_DIR"
SENTINEL="${SENTINEL_DIR}/${FILE_HASH}"

FILENAME="$(basename "$FILE_PATH")"
COUNT=0
if [ -f "$SENTINEL" ]; then
  COUNT="$(sed -n '1p' "$SENTINEL" 2>/dev/null || printf '0')"
fi
case "$COUNT" in
  ''|*[!0-9]*) COUNT=0 ;;
esac
COUNT=$((COUNT + 1))
printf '%s\n' "$COUNT" > "$SENTINEL"

if [ "$COUNT" -ge 3 ]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  if [ -d "$REPO_ROOT/.codegraph" ]; then
    NEXT="Use codegraph_explore \"where is ${FILENAME} used?\" or codegraph_node file=\"${FILE_PATH}\" before rereading."
  elif command -v rtk >/dev/null 2>&1; then
    NEXT="Use rtk grep <specific term> -r or read an exact line range instead."
  else
    NEXT="Use grep/rg for a specific value or read an exact line range instead."
  fi
  jq -n --arg reason "TOKEN EFFICIENCY: You are re-reading '${FILENAME}' for the ${COUNT}th time this session. The file content is already in context. ${NEXT}" \
    '{decision:"block", reason:$reason}'
  exit 0
fi

exit 0
