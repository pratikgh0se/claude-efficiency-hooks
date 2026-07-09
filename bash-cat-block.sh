#!/usr/bin/env bash
# PreToolUse hook for Bash tool.
# Blocks high-token shell exploration and points the agent to cheaper paths.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/efficiency-common.sh" ]; then
  # shellcheck source=lib/efficiency-common.sh
  . "$SCRIPT_DIR/lib/efficiency-common.sh"
fi

INPUT=$(cat)

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[ "$TOOL" != "Bash" ] && exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
[ -z "$CMD" ] && exit 0

CMD_TRIMMED="${CMD#"${CMD%%[![:space:]]*}"}"

has_rtk() {
  command -v rtk >/dev/null 2>&1
}

emit_block() {
  local reason="$1"
  jq -n --arg reason "TOKEN EFFICIENCY: $reason" \
    '{decision:"block", reason:$reason}'
}

starts_with_rtk_grep() {
  printf '%s' "$CMD_TRIMMED" | grep -Eq '^rtk[[:space:]]+grep[[:space:]]'
}

if printf '%s' "$CMD_TRIMMED" | grep -Eq '^cat([[:space:]]|$)'; then
  if ! printf '%s' "$CMD_TRIMMED" | grep -Eq '<<|^cat[[:space:]]+-$|^cat[[:space:]]+/dev/'; then
    if has_rtk; then
      emit_block "Use rtk read <file> or the Read tool instead of cat; shell output is costly and less cache-friendly."
    else
      emit_block "Use the Read tool instead of cat; shell output is costly and less cache-friendly."
    fi
    exit 0
  fi
fi

if printf '%s' "$CMD_TRIMMED" | grep -Eq '^grep([[:space:]]|$)' && ! starts_with_rtk_grep; then
  if printf '%s' "$CMD_TRIMMED" | grep -Eq '(^|[[:space:]])-[A-Za-z]*[Rr][A-Za-z]*([[:space:]]|$)|[[:space:]]\.[[:space:]]*$'; then
    if has_rtk; then
      emit_block "Use rtk grep <pattern> -r <path> for compact recursive search output."
    else
      emit_block "Use bounded rg, for example: rg -n <pattern> <path> --glob '!node_modules'."
    fi
    exit 0
  fi
fi

if printf '%s' "$CMD_TRIMMED" | grep -Eq '^find[[:space:]]+'; then
  if ! printf '%s' "$CMD_TRIMMED" | grep -Eq '(^|[[:space:]])-maxdepth[[:space:]]+[0-9]+|\|[[:space:]]*(head|wc)([[:space:]]|$)'; then
    emit_block "Bound find with -maxdepth and pipe to head or wc before running it."
    exit 0
  fi
fi

if printf '%s' "$CMD_TRIMMED" | grep -Eq '^ls[[:space:]]+(-la|-al)([[:space:]]+\.?)?$'; then
  if has_rtk; then
    repo_root="${SCRIPT_DIR}"
    if command -v git >/dev/null 2>&1; then
      repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    fi
    if [ "$(pwd -P)" = "$(cd "$repo_root" 2>/dev/null && pwd -P)" ]; then
      emit_block "Use rtk ls for compact directory listings at repo root."
      exit 0
    fi
  fi
fi

if printf '%s' "$CMD_TRIMMED" | grep -Eq '^git[[:space:]]+log\b'; then
  if ! printf '%s' "$CMD_TRIMMED" | grep -Eq -- '--oneline|--format|--pretty|-n[[:space:]]*[0-9]|-[0-9]+'; then
    if has_rtk; then
      emit_block "Use rtk git log --oneline -20 or add an explicit git log limit."
    else
      emit_block "Use git log --oneline -20 or add an explicit --format/-n limit."
    fi
    exit 0
  fi
fi

exit 0
