#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/efficiency-common.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

ceh_version_ge "0.43.0" "0.43.0" || fail "equal versions should pass"
ceh_version_ge "0.44.0" "0.43.0" || fail "newer version should pass"
if ceh_version_ge "0.42.3" "0.43.0"; then
  fail "older version should fail"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
TARGET="$TMP_DIR/CLAUDE.md"
CONTENT="$TMP_DIR/block.md"
printf 'before\n' > "$TARGET"
printf 'managed\n' > "$CONTENT"
ceh_replace_marked_block "$TARGET" "<!-- BEGIN test -->" "<!-- END test -->" "$CONTENT" "false"
grep -q '<!-- BEGIN test -->' "$TARGET" || fail "begin marker missing"
grep -q '^managed$' "$TARGET" || fail "managed content missing"
grep -q '<!-- END test -->' "$TARGET" || fail "end marker missing"

printf 'managed-two\n' > "$CONTENT"
ceh_replace_marked_block "$TARGET" "<!-- BEGIN test -->" "<!-- END test -->" "$CONTENT" "false"
COUNT="$(grep -c '<!-- BEGIN test -->' "$TARGET")"
[ "$COUNT" = "1" ] || fail "marker duplicated: $COUNT"
grep -q '^managed-two$' "$TARGET" || fail "replacement content missing"

echo "test-common: PASS"
