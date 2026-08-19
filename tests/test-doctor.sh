#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
TMP_REPO="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME" "$TMP_REPO"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

OUT="$(CEH_TEST_HOME="$ROOT/tests/fixtures/doctor/home" bash "$ROOT/doctor.sh" --repo "$ROOT" --no-mcp-health)"

printf '%s\n' "$OUT" | grep -q 'Claude Efficiency Doctor' || fail "missing title"
printf '%s\n' "$OUT" | grep -q 'RTK' || fail "missing RTK check"
printf '%s\n' "$OUT" | grep -q 'CodeGraph' || fail "missing CodeGraph check"
printf '%s\n' "$OUT" | grep -q 'Ponytail' || fail "missing Ponytail check"
printf '%s\n' "$OUT" | grep -q 'MCP' || fail "missing MCP check"
printf '%s\n' "$OUT" | grep -q 'Next actions' || fail "missing next actions"

mkdir -p "$TMP_HOME/.codex"
for n in $(seq 1 20); do
  printf '[mcp_servers.server_%s]\ncommand = "true"\n' "$n" >> "$TMP_HOME/.codex/config.toml"
done
OUT="$(CEH_TEST_HOME="$TMP_HOME" bash "$ROOT/doctor.sh" --repo "$TMP_REPO" --no-mcp-health)"
printf '%s\n' "$OUT" | grep -q '\[WARN\] MCP budget' || fail "large MCP inventory should warn"

echo "test-doctor: PASS"
