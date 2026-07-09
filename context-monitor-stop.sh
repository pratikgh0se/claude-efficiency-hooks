#!/usr/bin/env bash
# Stop hook: measures current context window size from transcript_path.

set -euo pipefail

INPUT=$(cat)

STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
[ "$STOP_HOOK_ACTIVE" = "true" ] && exit 0

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
[ -z "$TRANSCRIPT" ] && exit 0

TRANSCRIPT="${TRANSCRIPT/#\~/$HOME}"
[ ! -f "$TRANSCRIPT" ] && exit 0

LAST_CTX=$(python3 - "$TRANSCRIPT" <<'PYEOF'
import json
import sys

path = sys.argv[1]
last_ctx = 0
with open(path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            if obj.get("type") == "assistant":
                usage = obj.get("message", {}).get("usage", {})
                if usage:
                    ctx = (
                        usage.get("input_tokens", 0)
                        + usage.get("cache_read_input_tokens", 0)
                        + usage.get("cache_creation_input_tokens", 0)
                    )
                    if ctx > 0:
                        last_ctx = ctx
        except Exception:
            pass

print(last_ctx)
PYEOF
)

if [ -z "$LAST_CTX" ] || [ "$LAST_CTX" -eq 0 ]; then
  exit 0
fi

WARN_THRESHOLD=80000
URGENT_THRESHOLD=120000
CACHE_HINT="Keep model/effort stable for the task to preserve cache; use /compact before continuing related work."

if [ "$LAST_CTX" -ge "$URGENT_THRESHOLD" ]; then
  LEVEL="URGENT"
  MSG="Context window is at ${LAST_CTX} tokens. Run /compact before more work. ${CACHE_HINT}"
elif [ "$LAST_CTX" -ge "$WARN_THRESHOLD" ]; then
  LEVEL="WARN"
  MSG="Context window is at ${LAST_CTX} tokens. Compact soon if this task will continue. ${CACHE_HINT}"
else
  exit 0
fi

BAND=$(( LAST_CTX / 20000 ))
SENTINEL="${TMPDIR:-/tmp}/ctx-warned-${SESSION_ID}-${BAND}"
[ -f "$SENTINEL" ] && exit 0
touch "$SENTINEL"

jq -n --arg context "TOKEN EFFICIENCY [${LEVEL}]: ${MSG}" \
  '{hookSpecificOutput:{hookEventName:"Stop", additionalContext:$context}}'

exit 0
