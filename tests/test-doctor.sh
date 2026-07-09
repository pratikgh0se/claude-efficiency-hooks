#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

echo "test-doctor: PASS"
