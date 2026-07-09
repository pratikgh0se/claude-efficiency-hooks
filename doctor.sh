#!/usr/bin/env bash
# Read-only audit for Claude/Codex token-efficiency setup.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/efficiency-common.sh
. "$SCRIPT_DIR/lib/efficiency-common.sh"

REPO="$PWD"
NO_MCP_HEALTH=false
JSON=false
HOME_DIR="${CEH_TEST_HOME:-$HOME}"
NEXT_ACTIONS=""
REPORT_TMP="$(mktemp)"
trap 'rm -f "$REPORT_TMP"' EXIT

usage() {
  printf 'Usage: %s [--repo PATH] [--no-mcp-health] [--json]\n' "$0"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      REPO="$2"
      shift 2
      ;;
    --no-mcp-health)
      NO_MCP_HEALTH=true
      shift
      ;;
    --json)
      JSON=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

REPO="$(ceh_repo_root "$REPO")"

add_next_action() {
  NEXT_ACTIONS="${NEXT_ACTIONS}- $1
"
}

record() {
  local section="$1"
  local status="$2"
  local name="$3"
  local detail="$4"
  printf '%s\t%s\t%s\t%s\n' "$section" "$status" "$name" "$detail" >> "$REPORT_TMP"
  case "$status" in
    WARN|FAIL) add_next_action "$name: $detail" ;;
  esac
}

tool_version() {
  "$@" 2>/dev/null | sed -n '1p' || true
}

hash_tool() {
  if ceh_command_exists md5sum; then
    printf 'md5sum'
  elif ceh_command_exists md5; then
    printf 'md5'
  else
    printf ''
  fi
}

check_tools() {
  local version rtk_version hash

  if ceh_command_exists claude; then
    version="$(tool_version claude --version)"
    record "Tools" "PASS" "Claude" "${version:-available}"
  else
    record "Tools" "FAIL" "Claude" "claude command not found"
  fi

  if ceh_command_exists codex; then
    version="$(tool_version codex --version)"
    record "Tools" "PASS" "Codex" "${version:-available}"
  else
    record "Tools" "INFO" "Codex" "codex command not found; optional for Claude-only use"
  fi

  if ceh_command_exists jq; then
    record "Tools" "PASS" "jq" "$(tool_version jq --version)"
  else
    record "Tools" "FAIL" "jq" "required for hook payload parsing"
  fi

  if ceh_command_exists python3; then
    record "Tools" "PASS" "python3" "$(tool_version python3 --version)"
  else
    record "Tools" "FAIL" "python3" "required for config merge and transcript parsing"
  fi

  hash="$(hash_tool)"
  if [ -n "$hash" ]; then
    record "Tools" "PASS" "hash" "$hash"
  else
    record "Tools" "FAIL" "hash" "md5sum or md5 is required"
  fi

  if ceh_command_exists rtk; then
    version="$(tool_version rtk --version)"
    rtk_version="$(printf '%s\n' "$version" | grep -Eo '[0-9]+([.][0-9]+)+' | sed -n '1p')"
    if [ -n "$rtk_version" ] && ceh_version_ge "$rtk_version" "0.43.0"; then
      record "Tools" "PASS" "RTK" "$version"
    else
      record "Tools" "FAIL" "RTK" "${version:-available}; upgrade to >= 0.43.0"
    fi
  else
    record "Tools" "WARN" "RTK" "missing; install after approval with ./install.sh --install-tools"
  fi

  if ceh_command_exists caveman || [ -d "$HOME_DIR/.agents/skills/caveman" ] || [ -d "$HOME_DIR/.claude/skills/caveman" ]; then
    record "Tools" "PASS" "Caveman" "available"
  else
    record "Tools" "WARN" "Caveman" "missing; known-source install is approval-gated"
  fi
}

check_graph() {
  if ceh_has_codegraph_tools; then
    record "Graph" "PASS" "CodeGraph commands" "codegraph_explore/codegraph_node/codegraph_search available"
  else
    record "Graph" "FAIL" "CodeGraph commands" "missing on PATH"
  fi

  if ceh_has_codegraph_index "$REPO"; then
    record "Graph" "PASS" "CodeGraph index" "$REPO/.codegraph"
  else
    record "Graph" "WARN" "CodeGraph index" "repo has no .codegraph index"
  fi

  if jq -e '.graph.install.known_source == true and (.graph.install.command | length > 0)' "$SCRIPT_DIR/bootstrap/tools.json" >/dev/null 2>&1; then
    record "Graph" "PASS" "CodeGraph install source" "configured"
  else
    record "Graph" "WARN" "CodeGraph install source" "not configured; refusing to invent installer"
  fi
}

check_hooks() {
  local claude_settings="$HOME_DIR/.claude/settings.json"
  local codex_hooks_home="$HOME_DIR/.codex/hooks.json"
  local codex_hooks_repo="$REPO/.codex/hooks.json"

  if [ -f "$claude_settings" ]; then
    if grep -qE 'bash-cat-block|graph-first-block|reread-warn|context-monitor-stop' "$claude_settings"; then
      record "Hooks" "PASS" "Claude hooks" "$claude_settings references efficiency hooks"
    else
      record "Hooks" "WARN" "Claude hooks" "$claude_settings exists but efficiency hooks were not found"
    fi
  else
    record "Hooks" "WARN" "Claude hooks" "$claude_settings missing"
  fi

  if [ -f "$codex_hooks_repo" ]; then
    record "Hooks" "PASS" "Codex hooks" "$codex_hooks_repo"
  elif [ -f "$codex_hooks_home" ]; then
    record "Hooks" "PASS" "Codex hooks" "$codex_hooks_home"
  else
    record "Hooks" "WARN" "Codex hooks" "no repo or user hooks.json found"
  fi
}

check_instructions() {
  if [ -f "$REPO/CLAUDE.md" ] || [ -f "$HOME_DIR/.claude/CLAUDE.md" ]; then
    record "Instructions" "PASS" "CLAUDE.md" "present"
  else
    record "Instructions" "WARN" "CLAUDE.md" "missing efficiency instructions"
  fi

  if [ -f "$REPO/AGENTS.md" ] || [ -f "$HOME_DIR/.codex/AGENTS.md" ]; then
    record "Instructions" "PASS" "AGENTS.md" "present"
  else
    record "Instructions" "WARN" "AGENTS.md" "missing Codex efficiency instructions"
  fi

  if [ -f "$REPO/.agents/skills/ponytail/SKILL.md" ] || [ -f "$REPO/.claude/skills/ponytail/SKILL.md" ] || [ -f "$HOME_DIR/.claude/skills/ponytail/SKILL.md" ]; then
    record "Instructions" "PASS" "Ponytail" "skill/instructions present"
  else
    record "Instructions" "WARN" "Ponytail" "skill/instructions missing"
  fi
}

count_claude_mcp() {
  local settings="$HOME_DIR/.claude/settings.json"
  [ -f "$settings" ] || { printf '0'; return; }
  jq '.mcpServers // {} | length' "$settings" 2>/dev/null || printf '0'
}

count_codex_mcp() {
  local total=0
  local file
  for file in "$HOME_DIR/.codex/config.toml" "$REPO/.codex/config.toml"; do
    if [ -f "$file" ]; then
      total=$((total + $(grep -Ec '^\[mcp_servers[.]' "$file" || true)))
    fi
  done
  printf '%s' "$total"
}

check_mcp() {
  local claude_count codex_count
  claude_count="$(count_claude_mcp)"
  codex_count="$(count_codex_mcp)"
  if [ "$NO_MCP_HEALTH" = "true" ]; then
    record "MCP" "INFO" "MCP health" "network/process health skipped"
  else
    record "MCP" "INFO" "MCP health" "read-only count only; no server health checks performed"
  fi
  record "MCP" "INFO" "MCP servers" "Claude=${claude_count}, Codex=${codex_count}"
}

print_text() {
  local section current status name detail
  printf 'Claude Efficiency Doctor\n'
  printf 'Repo: %s\n' "$REPO"
  printf 'Home: %s\n\n' "$HOME_DIR"

  current=""
  while IFS="$(printf '\t')" read -r section status name detail; do
    if [ "$section" != "$current" ]; then
      [ -n "$current" ] && printf '\n'
      printf '%s\n' "$section"
      current="$section"
    fi
    printf '  [%s] %s: %s\n' "$status" "$name" "$detail"
  done < "$REPORT_TMP"

  printf '\nNext actions\n'
  if [ -n "$NEXT_ACTIONS" ]; then
    printf '%s' "$NEXT_ACTIONS"
  else
    printf '- No action required.\n'
  fi
}

print_json() {
  python3 - "$REPO" "$HOME_DIR" "$REPORT_TMP" <<'PY'
import json
import sys

repo, home, path = sys.argv[1:4]
checks = []
with open(path) as f:
    for line in f:
        section, status, name, detail = line.rstrip("\n").split("\t", 3)
        checks.append({"section": section, "status": status, "name": name, "detail": detail})
print(json.dumps({"title": "Claude Efficiency Doctor", "repo": repo, "home": home, "checks": checks}, indent=2))
PY
}

check_tools
check_hooks
check_instructions
check_graph
check_mcp

if [ "$JSON" = "true" ]; then
  print_json
else
  print_text
fi

exit 0
