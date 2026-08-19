#!/usr/bin/env bash
# PreToolUse hook for graph-first code discovery.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/efficiency-common.sh
. "$SCRIPT_DIR/lib/efficiency-common.sh"

INPUT=$(cat)

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
case "$TOOL" in
  Grep|Glob|Read) ;;
  *) exit 0 ;;
esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[ -d "$REPO_ROOT/.codegraph" ] && ceh_has_codegraph_tools || exit 0

emit_block() {
  local reason="$1"
  jq -n --arg reason "TOKEN EFFICIENCY: $reason" \
    '{decision:"block", reason:$reason}'
}

is_exempt_path() {
  local path="$1"
  case "$path" in
    .git/*|*/.git/*|.codegraph/*|*/.codegraph/*) return 0 ;;
    *bash-cat-block.sh|*reread-warn.sh|*context-monitor-stop.sh|*graph-first-block.sh) return 0 ;;
    *.lock|*package-lock.json|*pnpm-lock.yaml|*yarn.lock|*Cargo.lock|*go.sum) return 0 ;;
    *.json|*.toml|*.yaml|*.yml|*.ini|*.conf) return 0 ;;
    *.md|*.txt|*.rst) return 0 ;;
    */.agents/skills/*|*/.claude/skills/*|*/.codex/*) return 0 ;;
  esac
  return 1
}

if [ "$TOOL" = "Grep" ] || [ "$TOOL" = "Glob" ]; then
  QUERY="$(printf '%s' "$INPUT" | jq -r '.tool_input.pattern // .tool_input.query // .tool_input.glob // "symbols"' 2>/dev/null || echo "symbols")"
  emit_block "CodeGraph index exists. Use codegraph_explore \"${QUERY}\" before broad ${TOOL} exploration."
  exit 0
fi

FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")"
[ -z "$FILE_PATH" ] && exit 0

OFFSET="$(printf '%s' "$INPUT" | jq -r '.tool_input.offset // empty' 2>/dev/null || echo "")"
LIMIT="$(printf '%s' "$INPUT" | jq -r '.tool_input.limit // empty' 2>/dev/null || echo "")"
if [ -n "$OFFSET" ] || [ -n "$LIMIT" ]; then
  exit 0
fi

if is_exempt_path "$FILE_PATH"; then
  exit 0
fi

emit_block "CodeGraph index exists. Use codegraph_node file=\"${FILE_PATH}\" or codegraph_explore \"what do I need in ${FILE_PATH}?\" before full-file Read."
exit 0
