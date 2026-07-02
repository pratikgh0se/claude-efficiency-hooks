#!/usr/bin/env bash
# PreToolUse hook for Bash tool.
# Blocks `cat <file>` commands and redirects Claude to use the Read tool.
# Also warns on large git log / pipeline JSON commands.

set -euo pipefail

INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[ "$TOOL" != "Bash" ] && exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
[ -z "$CMD" ] && exit 0

# Trim leading whitespace
CMD_TRIMMED="${CMD#"${CMD%%[![:space:]]*}"}"

# --- Block: cat <file> ---
# Match: cat <path>, cat -n <path>, etc. (not cat << EOF or cat /dev/stdin)
if echo "$CMD_TRIMMED" | grep -qE '^cat\s+(-[A-Za-z]+\s+)?[^<|&]'; then
  # Allow heredocs and pipes from cat
  if ! echo "$CMD_TRIMMED" | grep -qE '<<|cat\s+-$|cat\s+/dev/'; then
    FILENAME=$(echo "$CMD_TRIMMED" | sed 's/^cat\s*-[A-Za-z]*\s*//' | awk '{print $1}')
    cat << EOF
{
  "decision": "block",
  "reason": "TOKEN EFFICIENCY: Do not use 'cat' to read files — bash output lands in context as uncacheable tokens and bloats the context window permanently. Use the Read tool instead: it reads the file efficiently, is cacheable, and doesn't pollute context. File to read: ${FILENAME}"
}
EOF
    exit 0
  fi
fi

# --- Warn: git log without --oneline or -n limit ---
if echo "$CMD_TRIMMED" | grep -qE '^git\s+log\b' && ! echo "$CMD_TRIMMED" | grep -qE '\-\-oneline|--format|--pretty|-n\s*[0-9]|-[0-9]+'; then
  cat << EOF
{
  "decision": "block",
  "reason": "TOKEN EFFICIENCY: 'git log' without --oneline or -n limit can dump thousands of lines into context. Use: git log --oneline -20  (or appropriate limit). Rewrite the command with a line limit before proceeding."
}
EOF
  exit 0
fi

# --- Warn: unbounded find that might return massive output ---
if echo "$CMD_TRIMMED" | grep -qE '^find\s+' && ! echo "$CMD_TRIMMED" | grep -qE '\|\s*head|\|\s*wc|\-maxdepth'; then
  # Only block if it's a broad find (root or home)
  if echo "$CMD_TRIMMED" | grep -qE '^find\s+(\/|~|\$HOME)\s'; then
    cat << EOF
{
  "decision": "block",
  "reason": "TOKEN EFFICIENCY: Broad 'find /' or 'find ~' without -maxdepth or pipe to head can return massive output. Add -maxdepth 3 and pipe to head -50 to limit context pollution."
}
EOF
    exit 0
  fi
fi

exit 0
