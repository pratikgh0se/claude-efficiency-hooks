#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$ROOT/tests/test-common.sh"

if [ -f "$ROOT/tests/test-hooks.sh" ]; then
  bash "$ROOT/tests/test-hooks.sh"
fi
if [ -f "$ROOT/tests/test-doctor.sh" ]; then
  bash "$ROOT/tests/test-doctor.sh"
fi
if [ -f "$ROOT/tests/test-install.sh" ]; then
  bash "$ROOT/tests/test-install.sh"
fi

echo "all tests: PASS"
