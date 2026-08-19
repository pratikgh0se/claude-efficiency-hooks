#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
TMP_REPO="$(mktemp -d)"
TMP_INVALID_HOME="$(mktemp -d)"
TMP_INVALID_REPO="$(mktemp -d)"
TMP_SYMLINK_HOME="$(mktemp -d)"
TMP_SYMLINK_REPO="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME" "$TMP_REPO" "$TMP_INVALID_HOME" "$TMP_INVALID_REPO" "$TMP_SYMLINK_HOME" "$TMP_SYMLINK_REPO"' EXIT

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

mkdir -p "$TMP_REPO/.codex"
printf '{"hooks":{"PreToolUse":[{"matcher":"^Write$","hooks":[{"type":"command","command":"echo keep"}]}]}}\n' > "$TMP_REPO/.codex/hooks.json"

HOME="$TMP_HOME" bash "$ROOT/install.sh" --init-repo "$TMP_REPO" --skip-tool-install
[ -f "$TMP_REPO/CLAUDE.md" ] || fail "repo CLAUDE.md not created"
[ -f "$TMP_REPO/AGENTS.md" ] || fail "repo AGENTS.md not created"
[ -f "$TMP_REPO/.codex/hooks.json" ] || fail "codex hooks not created"
jq -e '.hooks.PreToolUse[] | select(.matcher == "^Write$")' "$TMP_REPO/.codex/hooks.json" >/dev/null || fail "existing Codex hook not preserved"
for matcher in '^Bash$' '^(Grep|Glob|Read)$' '^Read$'; do
  jq -e --arg matcher "$matcher" '.hooks.PreToolUse[] | select(.matcher == $matcher)' "$TMP_REPO/.codex/hooks.json" >/dev/null || fail "managed Codex hook missing: $matcher"
done
for helper in bash-cat-block.sh graph-first-block.sh reread-warn.sh context-monitor-stop.sh lib/efficiency-common.sh; do
  [ -f "$TMP_REPO/.codex/claude-efficiency-hooks/$helper" ] || fail "Codex helper not installed: $helper"
done

mkdir -p "$TMP_INVALID_HOME/.claude" "$TMP_INVALID_REPO/.codex"
printf '{broken\n' > "$TMP_INVALID_HOME/.claude/settings.json"
if HOME="$TMP_INVALID_HOME" bash "$ROOT/install.sh" --apply --repo "$TMP_REPO" --skip-tool-install >/dev/null 2>&1; then
  fail "invalid Claude settings should fail closed"
fi
grep -q '{broken' "$TMP_INVALID_HOME/.claude/settings.json" || fail "invalid Claude settings were replaced"

printf '{broken\n' > "$TMP_INVALID_REPO/.codex/hooks.json"
if HOME="$TMP_INVALID_HOME" bash "$ROOT/install.sh" --init-repo "$TMP_INVALID_REPO" --skip-tool-install >/dev/null 2>&1; then
  fail "invalid Codex hooks should fail closed"
fi
grep -q '{broken' "$TMP_INVALID_REPO/.codex/hooks.json" || fail "invalid Codex hooks were replaced"

mkdir -p "$TMP_SYMLINK_HOME/.claude" "$TMP_SYMLINK_REPO/.codex"
printf 'do not overwrite\n' > "$TMP_SYMLINK_HOME/victim"
ln -s "$TMP_SYMLINK_HOME/victim" "$TMP_SYMLINK_HOME/.claude/settings.json.claude-efficiency-hooks.tmp"
HOME="$TMP_SYMLINK_HOME" bash "$ROOT/install.sh" --apply --repo "$TMP_REPO" --skip-tool-install >/dev/null
grep -qx 'do not overwrite' "$TMP_SYMLINK_HOME/victim" || fail "Claude temporary file followed a symlink"
jq empty "$TMP_SYMLINK_HOME/.claude/settings.json" || fail "Claude settings were not written atomically"

printf 'do not overwrite\n' > "$TMP_SYMLINK_REPO/victim"
ln -s "$TMP_SYMLINK_REPO/victim" "$TMP_SYMLINK_REPO/.codex/hooks.json.claude-efficiency-hooks.tmp"
HOME="$TMP_SYMLINK_HOME" bash "$ROOT/install.sh" --init-repo "$TMP_SYMLINK_REPO" --skip-tool-install >/dev/null
grep -qx 'do not overwrite' "$TMP_SYMLINK_REPO/victim" || fail "Codex temporary file followed a symlink"
jq empty "$TMP_SYMLINK_REPO/.codex/hooks.json" || fail "Codex hooks were not written atomically"

echo "test-install: PASS"
