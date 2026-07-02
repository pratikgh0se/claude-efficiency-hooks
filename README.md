# claude-efficiency-hooks

Three Claude Code hooks that automatically block wasteful token patterns and keep context size in check.

Hooks wire into Claude Code's hook system (`~/.claude/settings.json`) and fire before or after tool calls — no changes to your workflow needed.

---

## Hooks

### 1. `context-monitor-stop.sh` — Context size watchdog

**Event:** `Stop` (fires after every assistant response)

Reads the current session's JSONL transcript, measures the last assistant turn's context token count (`input + cache_read + cache_creation`), and warns Claude before it responds next turn.

| Threshold | Action |
|-----------|--------|
| > 80k tokens | Injects warning into `additionalContext` — Claude is told to consider `/compact` |
| > 120k tokens | Injects urgent block — Claude is instructed to run `/compact` immediately |

Deduplicates per 20k-token band so you don't get spammed every turn.

**Dependencies:** `python3`, `jq`

---

### 2. `bash-cat-block.sh` — Bash command guard

**Event:** `PreToolUse` matching `Bash`

Blocks three categories of wasteful Bash commands before they execute:

| Pattern | Why blocked |
|---------|-------------|
| `cat <file>` | Bash output is uncacheable and permanently inflates context. Use the Read tool instead — it's cacheable and doesn't pollute the window. |
| `git log` without `--oneline` or `-n` limit | Can dump thousands of commit lines into context. |
| `find / ~` without `-maxdepth` or pipe to `head` | Broad finds can return massive output with no value. |

Returns `{"decision": "block", "reason": "..."}` with a specific remediation message.

Heredocs (`cat << EOF`) and pipes (`cat /dev/stdin`) are allowed through.

**Dependencies:** `jq`, `grep`, `sed`

---

### 3. `reread-warn.sh` — File re-read tracker

**Event:** `PreToolUse` matching `Read`

Tracks every file read per session using sentinel files in `/tmp/reread-track-<session_id>/`. On the **3rd read** of the same file in the same session, blocks with a message explaining the file is already in context and suggesting `grep` instead.

Sentinel files are keyed by MD5 hash of the file path, so they survive path variations.

**Dependencies:** `jq`, `md5sum`

---

## Installation

### 1. Copy hooks

```bash
git clone https://github.com/YOUR_USERNAME/claude-efficiency-hooks.git
cd claude-efficiency-hooks

mkdir -p ~/.claude/hooks
cp context-monitor-stop.sh ~/.claude/hooks/
cp bash-cat-block.sh ~/.claude/hooks/
cp reread-warn.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/context-monitor-stop.sh \
         ~/.claude/hooks/bash-cat-block.sh \
         ~/.claude/hooks/reread-warn.sh
```

### 2. Wire into `~/.claude/settings.json`

Add to your `hooks` section:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/context-monitor-stop.sh",
            "async": false
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/bash-cat-block.sh"
          }
        ]
      },
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/reread-warn.sh"
          }
        ]
      }
    ]
  }
}
```

> If you already have hooks, merge carefully — `Stop` and `PreToolUse` can each have multiple matcher entries.

### 3. Add CLAUDE.md rules (optional but recommended)

Add to `~/.claude/CLAUDE.md` so Claude reinforces the same rules via instructions:

```markdown
# Token efficiency rules
- Never use `cat` to read files — use the Read tool
- Never re-read a file already read this session — grep for specific values instead
- Don't acknowledge tool results with a message before the next tool call — proceed directly
- When pipeline/MCP output is large, pipe through `head -50` or `jq` to extract only relevant lines
- If context warning appears in additionalContext, run /compact immediately before doing anything else
- Batch independent tool calls in a single response rather than sequentially with commentary between
```

---

## Requirements

- Claude Code CLI
- `bash` ≥ 4, `jq`, `python3` (stdlib only), `md5sum` (or `md5` on macOS — see note below)

### macOS note: `md5sum`

`reread-warn.sh` uses `md5sum`. macOS ships `md5` not `md5sum`. Either install coreutils:

```bash
brew install coreutils
```

Or patch line 21 of `reread-warn.sh`:

```bash
# Replace:
FILE_HASH=$(echo "$FILE_PATH" | md5sum | cut -c1-12)
# With:
FILE_HASH=$(echo "$FILE_PATH" | md5 | cut -c1-12)
```

---

## How Claude Code hooks work

Claude Code fires hooks at specific lifecycle events. Each hook receives a JSON payload on stdin and can return a JSON response to influence Claude's behaviour.

- **`Stop` hooks** run after every assistant response. They can inject `additionalContext` that Claude reads before its next turn.
- **`PreToolUse` hooks** run before a tool executes. Returning `{"decision": "block", "reason": "..."}` cancels the tool call and shows the reason to Claude.

Full docs: [Claude Code hooks reference](https://docs.anthropic.com/en/docs/claude-code/hooks)

---

## Token savings

The exact savings depend on your workflow. Typical patterns:

- `cat` on a 500-line file = ~2k uncacheable tokens added to context permanently. Blocked by `bash-cat-block.sh`.
- Re-reading a file 5× in a session = ~8k wasted tokens. Blocked after 3rd read by `reread-warn.sh`.
- Sessions running past 120k context = exponentially expensive cache rebuilds. Caught by `context-monitor-stop.sh`.

---

## License

MIT
