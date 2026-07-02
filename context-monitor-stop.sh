#!/usr/bin/env bash
# Stop hook: measures current context window size from transcript_path.
# If context > 80k tokens, injects a compact warning into additionalContext.
# Claude Code injects this text into the model's context before it responds.

set -euo pipefail

INPUT=$(cat)

# Skip if this hook is already running (Stop hook loop guard)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
[ "$STOP_HOOK_ACTIVE" = "true" ] && exit 0

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
[ -z "$TRANSCRIPT" ] && exit 0

# Expand ~ in path
TRANSCRIPT="${TRANSCRIPT/#\~/$HOME}"
[ ! -f "$TRANSCRIPT" ] && exit 0

# Read last assistant turn and extract context size
LAST_CTX=$(python3 - "$TRANSCRIPT" << 'PYEOF'
import json, sys

path = sys.argv[1]
last_ctx = 0
with open(path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            if obj.get('type') == 'assistant':
                u = obj.get('message', {}).get('usage', {})
                if u:
                    ctx = (u.get('input_tokens', 0)
                         + u.get('cache_read_input_tokens', 0)
                         + u.get('cache_creation_input_tokens', 0))
                    if ctx > 0:
                        last_ctx = ctx
        except Exception:
            pass

print(last_ctx)
PYEOF
)

[ -z "$LAST_CTX" ] || [ "$LAST_CTX" -eq 0 ] && exit 0

# Thresholds
WARN_THRESHOLD=80000
URGENT_THRESHOLD=120000

if [ "$LAST_CTX" -ge "$URGENT_THRESHOLD" ]; then
  LEVEL="URGENT"
  MSG="Context window is at ${LAST_CTX} tokens — CRITICAL. You MUST run /compact RIGHT NOW before doing anything else. Do not proceed with any task until compaction is done. After compacting, confirm the new context size to the user."
elif [ "$LAST_CTX" -ge "$WARN_THRESHOLD" ]; then
  LEVEL="WARN"
  MSG="Context window is at ${LAST_CTX} tokens (above 80k threshold). Consider running /compact soon. Each turn is burning expensive cache-read tokens. If this session will continue for more than 10 more turns, compact now."
else
  exit 0
fi

# Dedup: only warn once per 20-turn band per session to avoid spam
BAND=$(( LAST_CTX / 20000 ))
SENTINEL="/tmp/ctx-warned-${SESSION_ID}-${BAND}"
[ -f "$SENTINEL" ] && exit 0
touch "$SENTINEL"

cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": "TOKEN EFFICIENCY [${LEVEL}]: ${MSG}"
  }
}
EOF

exit 0
