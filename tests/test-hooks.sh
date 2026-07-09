#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export TMPDIR="$TMP_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

run_hook() {
  local hook="$1"
  local payload="$2"
  printf '%s' "$payload" | bash "$ROOT/$hook"
}

OUT="$(run_hook bash-cat-block.sh '{"tool_name":"Bash","tool_input":{"command":"cat README.md"}}')"
printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null || fail "cat should block"
printf '%s' "$OUT" | jq -e '.reason | contains("rtk read") or contains("Read tool")' >/dev/null || fail "cat reason should name cheaper read path"

OUT="$(run_hook bash-cat-block.sh '{"tool_name":"Bash","tool_input":{"command":"git log"}}')"
printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null || fail "unbounded git log should block"

OUT="$(run_hook bash-cat-block.sh '{"tool_name":"Bash","tool_input":{"command":"grep -R token ."}}')"
printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null || fail "raw broad grep should block"

OUT="$(run_hook bash-cat-block.sh '{"tool_name":"Bash","tool_input":{"command":"rtk grep token -r ."}}')"
[ -z "$OUT" ] || fail "rtk grep should pass"

mkdir -p "$TMP_DIR/repo/.codegraph"
OUT="$(cd "$TMP_DIR/repo" && run_hook graph-first-block.sh '{"tool_name":"Grep","tool_input":{"pattern":"AuthService","path":"."}}')"
printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null || fail "Grep should block when graph index exists"

OUT="$(run_hook reread-warn.sh '{"tool_name":"Read","session_id":"s1","tool_input":{"file_path":"README.md"}}')"
[ -z "$OUT" ] || fail "first read should pass"
OUT="$(run_hook reread-warn.sh '{"tool_name":"Read","session_id":"s1","tool_input":{"file_path":"README.md"}}')"
[ -z "$OUT" ] || fail "second read should pass"
OUT="$(run_hook reread-warn.sh '{"tool_name":"Read","session_id":"s1","tool_input":{"file_path":"README.md"}}')"
printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null || fail "third read should block"

echo "test-hooks: PASS"
