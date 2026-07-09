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

OUT="$(HOME="$TMP_HOME" bash "$ROOT/install.sh" --dry-run --repo "$TMP_REPO")"
printf '%s\n' "$OUT" | grep -q 'DRY RUN' || fail "dry-run banner missing"
printf '%s\n' "$OUT" | grep -q 'claude-efficiency-hooks' || fail "managed block name missing"

HOME="$TMP_HOME" bash "$ROOT/install.sh" --apply --repo "$TMP_REPO" --skip-tool-install
[ -x "$TMP_HOME/.claude/hooks/bash-cat-block.sh" ] || fail "bash hook not installed"
[ -x "$TMP_HOME/.claude/hooks/graph-first-block.sh" ] || fail "graph hook not installed"
[ -f "$TMP_HOME/.claude/CLAUDE.md" ] || fail "global CLAUDE.md not created"

HOME="$TMP_HOME" bash "$ROOT/install.sh" --apply --repo "$TMP_REPO" --skip-tool-install
COUNT="$(grep -c 'BEGIN claude-efficiency-hooks' "$TMP_HOME/.claude/CLAUDE.md")"
[ "$COUNT" = "1" ] || fail "managed block duplicated"

HOME="$TMP_HOME" bash "$ROOT/install.sh" --init-repo "$TMP_REPO" --skip-tool-install
[ -f "$TMP_REPO/CLAUDE.md" ] || fail "repo CLAUDE.md not created"
[ -f "$TMP_REPO/AGENTS.md" ] || fail "repo AGENTS.md not created"
[ -f "$TMP_REPO/.codex/hooks.json" ] || fail "codex hooks not created"

echo "test-install: PASS"
