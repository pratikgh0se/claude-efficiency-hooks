# Claude Efficiency Autopilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a portable Claude/Codex efficiency bootstrap kit that installs token-saving tools, hooks, rules, skills, and repo initialization helpers.

**Architecture:** Keep deterministic logic in small shell scripts and reusable helpers. Use manifests as the source of truth, hooks for enforcement, durable instruction files for agent behavior, and skills for Claude/Codex-native workflows. All global writes are idempotent, backed up, and approval-gated.

**Tech Stack:** POSIX-ish Bash with `set -euo pipefail`, `jq`, `python3` stdlib for JSON merge work, Markdown skills/instructions, Claude Code hooks, Codex `AGENTS.md`/`.agents/skills`/`.codex/hooks.json`.

## Global Constraints

- Do not commit user secrets, copied `settings.json`, auth tokens, or machine-specific credentials.
- Do not disable MCP servers automatically without user approval.
- Do not force high-risk model changes or change model/effort mid-session.
- Missing or outdated known tools are installed or upgraded only after explicit approval.
- RTK must be `>= 0.43.0`.
- CodeGraph install requires an authoritative source in `bootstrap/tools.json`; do not invent an installer.
- Ponytail is local instruction/skill setup unless a real binary/source is later discovered.
- Global file changes must use marked blocks: `<!-- BEGIN claude-efficiency-hooks -->` through `<!-- END claude-efficiency-hooks -->`.
- Backups must live under a user-local backup directory outside the repo.

---

## File Structure

- `bootstrap/tools.json`: manifest for required, recommended, and source-configured tools.
- `lib/efficiency-common.sh`: shared shell functions for path detection, version checks, manifest lookup, marked-block replacement, and dry-run logging.
- `doctor.sh`: read-only audit of current machine/repo efficiency state.
- `install.sh`: idempotent installer with `--dry-run`, `--apply`, `--install-tools`, `--portable`, and `--init-repo PATH`.
- `bash-cat-block.sh`: expanded Claude Code PreToolUse Bash guard.
- `reread-warn.sh`: reread guard with macOS/Linux hash fallback and graph-first messaging.
- `context-monitor-stop.sh`: context-size Stop hook with compact/cache guidance.
- `graph-first-block.sh`: Claude Code PreToolUse guard for `Grep`, `Glob`, and broad `Read` when graph is ready.
- `.codex/hooks.json`: repo-local Codex hook definitions mirroring supported enforcement.
- `AGENTS.md`: Codex durable project instructions.
- `CLAUDE.md`: Claude Code durable project instructions.
- `.agents/skills/efficiency-bootstrap/SKILL.md`: Codex repo skill for doctor/install workflow.
- `.agents/skills/graph-first/SKILL.md`: Codex repo skill for CodeGraph-first discovery.
- `.agents/skills/ponytail/SKILL.md`: Codex repo skill for minimal-code mode.
- `.claude/skills/efficiency-bootstrap/SKILL.md`: Claude-installable copy of the bootstrap skill.
- `.claude/skills/graph-first/SKILL.md`: Claude-installable copy of the graph-first skill.
- `.claude/skills/ponytail/SKILL.md`: Claude-installable copy of Ponytail mode.
- `tests/fixtures/`: JSON payloads and sample configs.
- `tests/run-tests.sh`: full local verification runner.
- `tests/test-hooks.sh`: hook behavior tests.
- `tests/test-common.sh`: shared helper tests.
- `tests/test-doctor.sh`: doctor output tests.
- `tests/test-install.sh`: installer dry-run/idempotency tests.
- `README.md`: user-facing bootstrap instructions.
- `docs/CHANGELOG.md`: changelog updates.

---

### Task 1: Manifest and Shared Helpers

**Files:**
- Create: `bootstrap/tools.json`
- Create: `lib/efficiency-common.sh`
- Create: `tests/test-common.sh`
- Modify: `tests/run-tests.sh` if created in this task as the aggregate runner

**Interfaces:**
- Produces: `ceh_command_exists CMD -> 0|1`
- Produces: `ceh_version_ge ACTUAL REQUIRED -> 0|1`
- Produces: `ceh_repo_root [PATH] -> prints absolute git root or input path`
- Produces: `ceh_has_codegraph_tools -> 0|1`
- Produces: `ceh_has_codegraph_index PATH -> 0|1`
- Produces: `ceh_replace_marked_block FILE BEGIN END CONTENT_FILE DRY_RUN -> writes or previews block replacement`
- Produces: `bootstrap/tools.json` keys consumed by `doctor.sh` and `install.sh`

- [ ] **Step 1: Write failing helper tests**

Create `tests/test-common.sh` with these exact test cases:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/efficiency-common.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

ceh_version_ge "0.43.0" "0.43.0" || fail "equal versions should pass"
ceh_version_ge "0.44.0" "0.43.0" || fail "newer version should pass"
if ceh_version_ge "0.42.3" "0.43.0"; then
  fail "older version should fail"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
TARGET="$TMP_DIR/CLAUDE.md"
CONTENT="$TMP_DIR/block.md"
printf 'before\n' > "$TARGET"
printf 'managed\n' > "$CONTENT"
ceh_replace_marked_block "$TARGET" "<!-- BEGIN test -->" "<!-- END test -->" "$CONTENT" "false"
grep -q '<!-- BEGIN test -->' "$TARGET" || fail "begin marker missing"
grep -q '^managed$' "$TARGET" || fail "managed content missing"
grep -q '<!-- END test -->' "$TARGET" || fail "end marker missing"

printf 'managed-two\n' > "$CONTENT"
ceh_replace_marked_block "$TARGET" "<!-- BEGIN test -->" "<!-- END test -->" "$CONTENT" "false"
COUNT="$(grep -c '<!-- BEGIN test -->' "$TARGET")"
[ "$COUNT" = "1" ] || fail "marker duplicated: $COUNT"
grep -q '^managed-two$' "$TARGET" || fail "replacement content missing"

echo "test-common: PASS"
```

- [ ] **Step 2: Run helper tests and verify they fail**

Run:

```bash
bash tests/test-common.sh
```

Expected: FAIL because `lib/efficiency-common.sh` does not exist.

- [ ] **Step 3: Create manifest**

Create `bootstrap/tools.json` with this structure:

```json
{
  "required": [
    {
      "name": "claude",
      "commands": ["claude"],
      "purpose": "Claude Code CLI"
    },
    {
      "name": "jq",
      "commands": ["jq"],
      "purpose": "Hook payload parsing and config inspection"
    },
    {
      "name": "python3",
      "commands": ["python3"],
      "purpose": "Safe JSON merge and transcript parsing"
    },
    {
      "name": "hash",
      "commands_any": ["md5sum", "md5"],
      "purpose": "Session reread sentinel keys"
    }
  ],
  "recommended": [
    {
      "name": "rtk",
      "commands": ["rtk"],
      "minimum_version": "0.43.0",
      "version_command": "rtk --version",
      "install": {
        "known_source": true,
        "approval_required": true,
        "command": "curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh",
        "url": "https://github.com/rtk-ai/rtk"
      },
      "purpose": "Filtered shell output and compact grep/read/git commands"
    },
    {
      "name": "ccusage",
      "commands": ["npx"],
      "purpose": "Statusline and usage visibility"
    },
    {
      "name": "caveman",
      "commands_any": ["caveman"],
      "install": {
        "known_source": true,
        "approval_required": true,
        "command": "curl -fsSL https://raw.githubusercontent.com/JuliusBrussee/caveman/main/src/tools/caveman-init.js | node -",
        "url": "https://github.com/JuliusBrussee/caveman"
      },
      "purpose": "Compressed output mode"
    }
  ],
  "managed_modes": [
    {
      "name": "ponytail",
      "type": "instruction_skill",
      "purpose": "Minimal code generation"
    }
  ],
  "graph": {
    "name": "codegraph",
    "commands": ["codegraph_explore", "codegraph_node", "codegraph_search"],
    "index_dir": ".codegraph",
    "install": {
      "known_source": false,
      "approval_required": true,
      "command": "",
      "url": ""
    },
    "purpose": "Graph-first code discovery"
  }
}
```

- [ ] **Step 4: Implement shared helpers**

Create `lib/efficiency-common.sh` with functions matching the interfaces above. Use these implementation details:

```bash
#!/usr/bin/env bash

ceh_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ceh_version_ge() {
  local actual="$1"
  local required="$2"
  local first
  first="$(printf '%s\n%s\n' "$required" "$actual" | sort -V | head -n 1)"
  [ "$first" = "$required" ]
}

ceh_repo_root() {
  local start="${1:-$PWD}"
  git -C "$start" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$start"
}

ceh_has_codegraph_tools() {
  ceh_command_exists codegraph_explore &&
    ceh_command_exists codegraph_node &&
    ceh_command_exists codegraph_search
}

ceh_has_codegraph_index() {
  local repo="${1:-$PWD}"
  [ -d "$repo/.codegraph" ]
}

ceh_replace_marked_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local content_file="$4"
  local dry_run="${5:-true}"
  local tmp
  tmp="$(mktemp)"
  if [ -f "$file" ] && grep -Fq "$begin" "$file" && grep -Fq "$end" "$file"; then
    awk -v begin="$begin" -v end="$end" -v content_file="$content_file" '
      $0 == begin {
        print begin
        while ((getline line < content_file) > 0) print line
        close(content_file)
        in_block = 1
        next
      }
      $0 == end {
        print end
        in_block = 0
        next
      }
      !in_block { print }
    ' "$file" > "$tmp"
  else
    { [ -f "$file" ] && cat "$file"; printf '\n%s\n' "$begin"; cat "$content_file"; printf '%s\n' "$end"; } > "$tmp"
  fi
  if [ "$dry_run" = "true" ]; then
    diff -u "$file" "$tmp" || true
    rm -f "$tmp"
  else
    mkdir -p "$(dirname "$file")"
    mv "$tmp" "$file"
  fi
}
```

- [ ] **Step 5: Add aggregate test runner**

Create `tests/run-tests.sh`:

```bash
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
```

- [ ] **Step 6: Run tests and verify pass**

Run:

```bash
chmod +x tests/run-tests.sh tests/test-common.sh
bash tests/run-tests.sh
```

Expected: `test-common: PASS` and `all tests: PASS`.

- [ ] **Step 7: Commit task 1**

Run:

```bash
git add bootstrap/tools.json lib/efficiency-common.sh tests/test-common.sh tests/run-tests.sh
git commit -m "feat: add efficiency manifest helpers"
```

---

### Task 2: Hook Guards and Hook Tests

**Files:**
- Modify: `bash-cat-block.sh`
- Modify: `reread-warn.sh`
- Modify: `context-monitor-stop.sh`
- Create: `graph-first-block.sh`
- Create: `tests/test-hooks.sh`

**Interfaces:**
- Consumes: `lib/efficiency-common.sh`
- Produces: Claude hook JSON responses with `decision: "block"` for PreToolUse blocks.
- Produces: Stop hook `hookSpecificOutput.additionalContext` for context warnings.

- [ ] **Step 1: Write failing hook tests**

Create `tests/test-hooks.sh` with these exact cases:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

run_hook() {
  local hook="$1"
  local payload="$2"
  printf '%s' "$payload" | bash "$ROOT/$hook"
}

OUT="$(run_hook bash-cat-block.sh '{"tool_name":"Bash","tool_input":{"command":"cat README.md"}}')"
printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null || fail "cat should block"
printf '%s' "$OUT" | jq -e '.reason | contains("rtk read") or contains("Read tool")' >/dev/null || fail "cat reason should name cheaper read path"

OUT="$(run_hook bash-cat-block.sh '{"tool_name":"Bash","tool_input":{"command":"git log"}}')"
printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null || fail "unbounded git log should block"

OUT="$(run_hook bash-cat-block.sh '{"tool_name":"Bash","tool_input":{"command":"grep -R token ."}}')"
printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null || fail "raw broad grep should block"

OUT="$(run_hook bash-cat-block.sh '{"tool_name":"Bash","tool_input":{"command":"rtk grep token -r ."}}')"
[ -z "$OUT" ] || fail "rtk grep should pass"

mkdir -p "$TMP_DIR/repo/.codegraph"
OUT="$(cd "$TMP_DIR/repo" && run_hook graph-first-block.sh '{"tool_name":"Grep","tool_input":{"pattern":"AuthService","path":"."}}')"
printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null || fail "Grep should block when graph index exists"

OUT="$(run_hook reread-warn.sh '{"tool_name":"Read","session_id":"s1","tool_input":{"file_path":"README.md"}}')"
[ -z "$OUT" ] || fail "first read should pass"
OUT="$(run_hook reread-warn.sh '{"tool_name":"Read","session_id":"s1","tool_input":{"file_path":"README.md"}}')"
[ -z "$OUT" ] || fail "second read should pass"
OUT="$(run_hook reread-warn.sh '{"tool_name":"Read","session_id":"s1","tool_input":{"file_path":"README.md"}}')"
printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null || fail "third read should block"

echo "test-hooks: PASS"
```

- [ ] **Step 2: Run hook tests and verify they fail**

Run:

```bash
bash tests/test-hooks.sh
```

Expected: FAIL because `graph-first-block.sh` does not exist and raw broad grep is not blocked yet.

- [ ] **Step 3: Update Bash guard**

Modify `bash-cat-block.sh` so it:

- sources `lib/efficiency-common.sh` when present
- keeps heredoc and stdin `cat` allowed
- blocks file-reading `cat`
- blocks broad raw `grep`/`grep -R`/`grep -r` unless command starts with `rtk grep`
- blocks broad raw `find` without `-maxdepth`, `head`, or `wc`
- blocks noisy `ls -la` from repo root when `rtk ls` is available
- blocks unbounded `git log`
- recommends `rtk read`, `rtk grep <pattern> -r`, `rtk ls`, and `rtk git ...` when RTK exists
- falls back to bounded `rg`, `find -maxdepth`, or Claude Read when RTK is absent

The block response shape must remain:

```json
{
  "decision": "block",
  "reason": "TOKEN EFFICIENCY: <specific next command>"
}
```

- [ ] **Step 4: Update reread guard**

Modify `reread-warn.sh` so it:

- uses `md5sum` when available and `md5 -q` on macOS
- stores sentinels under `${TMPDIR:-/tmp}/reread-track-$SESSION_ID`
- preserves the third-read block behavior
- adds graph-first guidance when `.codegraph/` exists in the current repo

The third-read reason must mention one of:

- `codegraph_explore` when graph exists
- `rtk grep` or `grep` when graph does not exist

- [ ] **Step 5: Add graph-first guard**

Create `graph-first-block.sh` so it:

- accepts Claude `PreToolUse` payloads for `Grep`, `Glob`, and `Read`
- exits silently when `.codegraph/` is absent
- exits silently for precise line-range reads
- blocks broad `Grep`/`Glob` with a `codegraph_explore "<question or symbols>"` recommendation
- blocks full-file exploratory `Read` only when the path is not a generated/config/small documentation file
- never blocks files under `.git`, `.codegraph`, or hook/skill files in this repo

- [ ] **Step 6: Keep context monitor behavior**

Modify `context-monitor-stop.sh` only where needed:

- replace hardcoded `/tmp` with `${TMPDIR:-/tmp}`
- mention cache discipline: set model/effort at session start, use `/compact` before continuing related work
- keep thresholds at 80k warn and 120k urgent

- [ ] **Step 7: Run hook tests**

Run:

```bash
bash tests/test-hooks.sh
bash tests/run-tests.sh
```

Expected: `test-hooks: PASS` and `all tests: PASS`.

- [ ] **Step 8: Commit task 2**

Run:

```bash
git add bash-cat-block.sh reread-warn.sh context-monitor-stop.sh graph-first-block.sh tests/test-hooks.sh
git commit -m "feat: add graph-first hook guards"
```

---

### Task 3: Read-Only Doctor

**Files:**
- Create: `doctor.sh`
- Create: `tests/test-doctor.sh`
- Create: `tests/fixtures/doctor/claude-settings.json`
- Create: `tests/fixtures/doctor/codex-config.toml`

**Interfaces:**
- Consumes: `bootstrap/tools.json`
- Consumes: `lib/efficiency-common.sh`
- Produces: text audit with statuses `PASS`, `WARN`, `FAIL`, and `INFO`
- Produces: exit code `0` for audit completion even when checks fail

- [ ] **Step 1: Write failing doctor tests**

Create `tests/test-doctor.sh`:

```bash
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
```

- [ ] **Step 2: Run doctor test and verify it fails**

Run:

```bash
bash tests/test-doctor.sh
```

Expected: FAIL because `doctor.sh` does not exist.

- [ ] **Step 3: Implement doctor**

Create `doctor.sh` with:

- options: `--repo PATH`, `--no-mcp-health`, `--json`
- default repo: current git root
- home override: `CEH_TEST_HOME` for tests, otherwise `$HOME`
- checks:
  - Claude CLI exists and version prints
  - Codex CLI exists when available
  - `jq`, `python3`, and hash command exist
  - RTK exists and version is `>= 0.43.0`
  - CodeGraph commands exist
  - repo has `.codegraph/`
  - Caveman local plugin/cache or command exists
  - Ponytail skills/instructions exist in repo or user home
  - Claude hooks are present in `~/.claude/settings.json` when file exists
  - Codex hooks/config are present in `~/.codex/hooks.json` or repo `.codex/hooks.json`
  - MCP count is reported from Claude/Codex config without performing network health unless explicitly enabled later
- output sections:
  - `Tools`
  - `Hooks`
  - `Instructions`
  - `Graph`
  - `MCP`
  - `Next actions`

- [ ] **Step 4: Run doctor tests**

Run:

```bash
bash tests/test-doctor.sh
bash tests/run-tests.sh
```

Expected: doctor test and aggregate tests pass.

- [ ] **Step 5: Run doctor manually**

Run:

```bash
./doctor.sh --repo .
```

Expected on current machine:

- RTK reports `PASS` with version `0.43.0`.
- CodeGraph commands report `FAIL` or `WARN` because they are not on PATH.
- CodeGraph install source reports missing unless configured in `bootstrap/tools.json`.

- [ ] **Step 6: Commit task 3**

Run:

```bash
chmod +x doctor.sh
git add doctor.sh tests/test-doctor.sh tests/fixtures/doctor
git commit -m "feat: add efficiency doctor"
```

---

### Task 4: Installer and Repo Initialization

**Files:**
- Replace: `install.sh`
- Create: `templates/claude-efficiency-block.md`
- Create: `templates/agents-efficiency-block.md`
- Create: `templates/codex-hooks.json`
- Create: `tests/test-install.sh`

**Interfaces:**
- Consumes: `bootstrap/tools.json`
- Consumes: `lib/efficiency-common.sh`
- Consumes: hook scripts and skills
- Produces: idempotent installer modes `--dry-run`, `--apply`, `--install-tools`, `--portable`, `--init-repo PATH`

- [ ] **Step 1: Write failing installer tests**

Create `tests/test-install.sh`:

```bash
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
```

- [ ] **Step 2: Run installer test and verify it fails**

Run:

```bash
bash tests/test-install.sh
```

Expected: FAIL because the current installer does not support the required flags.

- [ ] **Step 3: Create instruction templates**

Create `templates/claude-efficiency-block.md` with:

```md
## Token efficiency autopilot

- Set `/model` and `/effort` at session start; avoid switching mid-task because it can invalidate cache.
- Use `/clear` between unrelated tasks and `/compact` when switching context inside related work.
- Keep `CLAUDE.md` concise; every instruction rides along every turn.
- If `.codegraph/` exists and `codegraph_explore` works, use CodeGraph before grep/find/Read.
- Use `rtk grep <pattern> -r`, `rtk read`, `rtk ls`, and `rtk git status/diff/log` for shell exploration.
- Prefer Caveman-style concise output for routine status.
- Use Ponytail mode by default: smallest working change, reuse existing code, no speculative abstractions.
- Measure with `rtk gain`, `rtk gain --history`, `rtk discover`, and `/usage`.
```

Create `templates/agents-efficiency-block.md` with the same content adapted to Codex terms:

```md
## Token efficiency autopilot

- Prefer graph-first discovery: if `.codegraph/` exists and `codegraph_explore` works, use it before raw `rg`, `find`, full-file reads, or broad shell exploration.
- Use bounded `rg` only when graph is absent, stale, or not suited to the question.
- Read exact line ranges after graph or search identifies the target.
- Use RTK commands for shell output when available: `rtk grep <pattern> -r`, `rtk read`, `rtk ls`, and `rtk git status/diff/log`.
- Use Ponytail mode by default: smallest working change, reuse existing code, no speculative abstractions.
- Keep durable instructions concise because they consume context every turn.
```

- [ ] **Step 4: Create Codex hook template**

Create `templates/codex-hooks.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "^Bash$",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$(git rev-parse --show-toplevel)/bash-cat-block.sh\"",
            "timeout": 30,
            "statusMessage": "Checking shell output size"
          }
        ]
      },
      {
        "matcher": "^(Grep|Glob|Read)$",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$(git rev-parse --show-toplevel)/graph-first-block.sh\"",
            "timeout": 30,
            "statusMessage": "Checking graph-first policy"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$(git rev-parse --show-toplevel)/context-monitor-stop.sh\"",
            "timeout": 30,
            "statusMessage": "Checking context size"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 5: Implement installer**

Replace `install.sh` with a mode-based script:

- parse flags without external dependencies
- support `--repo PATH`
- copy hooks to `$HOME/.claude/hooks`
- copy `.claude/skills/*` to `$HOME/.claude/skills/*`
- merge global `~/.claude/CLAUDE.md` marked block
- merge repo `CLAUDE.md` and `AGENTS.md` marked blocks in `--init-repo`
- write repo `.codex/hooks.json` in `--init-repo`
- create backups under `$HOME/.claude-efficiency-hooks/backups/<timestamp>/`
- implement `--install-tools`:
  - RTK: if missing or below `0.43.0`, print the exact install command and require non-dry-run approval outside the script via prompt or environment flag
  - Caveman: if missing, print the exact install command
  - Ponytail: install local skills/instructions
  - CodeGraph: install only if manifest has non-empty command and `known_source: true`; otherwise print the missing-source action
- implement `--portable` to print:
  - clone repo
  - run `./doctor.sh`
  - run `./install.sh --dry-run`
  - run `./install.sh --apply --install-tools`
  - run `./install.sh --init-repo /path/to/repo`

- [ ] **Step 6: Run installer tests**

Run:

```bash
bash tests/test-install.sh
bash tests/run-tests.sh
```

Expected: `test-install: PASS` and `all tests: PASS`.

- [ ] **Step 7: Run installer dry run**

Run:

```bash
./install.sh --dry-run --repo .
./install.sh --install-tools --dry-run --repo .
```

Expected:

- dry-run prints planned writes without modifying home files
- install-tools dry-run reports RTK already OK if local version is `0.43.0`
- CodeGraph reports source missing

- [ ] **Step 8: Commit task 4**

Run:

```bash
chmod +x install.sh
git add install.sh templates tests/test-install.sh
git commit -m "feat: add efficiency installer"
```

---

### Task 5: Skills and Durable Instructions

**Files:**
- Create: `AGENTS.md`
- Create: `CLAUDE.md`
- Create: `.agents/skills/efficiency-bootstrap/SKILL.md`
- Create: `.agents/skills/graph-first/SKILL.md`
- Create: `.agents/skills/ponytail/SKILL.md`
- Create: `.claude/skills/efficiency-bootstrap/SKILL.md`
- Create: `.claude/skills/graph-first/SKILL.md`
- Create: `.claude/skills/ponytail/SKILL.md`
- Create: `.codex/hooks.json`

**Interfaces:**
- Produces: Codex skills discoverable from `.agents/skills`
- Produces: Claude skills installable by `install.sh`
- Produces: durable graph-first and Ponytail rules for both agents

- [ ] **Step 1: Create repo instruction files**

Create root `AGENTS.md` with:

```md
# Repository Instructions

<!-- BEGIN claude-efficiency-hooks -->
## Token efficiency autopilot

- Prefer graph-first discovery: if `.codegraph/` exists and `codegraph_explore` works, use it before raw `rg`, `find`, full-file reads, or broad shell exploration.
- Use bounded `rg` only when graph is absent, stale, or not suited to the question.
- Read exact line ranges after graph or search identifies the target.
- Use RTK commands for shell output when available: `rtk grep <pattern> -r`, `rtk read`, `rtk ls`, and `rtk git status/diff/log`.
- Use Ponytail mode by default: smallest working change, reuse existing code, no speculative abstractions.
- Keep durable instructions concise because they consume context every turn.
<!-- END claude-efficiency-hooks -->
```

Create root `CLAUDE.md` with the Claude template from task 4.

- [ ] **Step 2: Create efficiency-bootstrap skill**

Create both `.agents/skills/efficiency-bootstrap/SKILL.md` and `.claude/skills/efficiency-bootstrap/SKILL.md` with:

```md
---
name: efficiency-bootstrap
description: Run when setting up Claude/Codex token-efficiency autopilot, installing hooks, auditing missing tools, or preparing a new laptop from this repo.
---

# Efficiency Bootstrap

1. Run `./doctor.sh --repo .` first and summarize only failures and next actions.
2. Run `./install.sh --dry-run --repo .` before any write.
3. For missing known tools, run `./install.sh --install-tools --dry-run --repo .`.
4. Ask for approval before any network install or global config write.
5. After approval, run `./install.sh --apply --repo .`.
6. For each target repository, run `./install.sh --init-repo /absolute/path/to/repo`.
7. Verify with `./doctor.sh --repo .` and `./tests/run-tests.sh`.

Never copy secrets or full user config into this repo.
```

- [ ] **Step 3: Create graph-first skill**

Create both graph-first skill files with:

```md
---
name: graph-first
description: Use for code discovery, symbol lookup, caller/callee tracing, or repo exploration when CodeGraph may be available.
---

# Graph First

1. Check whether `.codegraph/` exists and `codegraph_explore` is available.
2. If graph is ready, use `codegraph_explore "<question or symbols>"` before grep/find/Read.
3. Use `codegraph_search query="<name>"` for symbol location.
4. Use `codegraph_node file="<path>"` for file plus dependency context.
5. Fall back to bounded `rg` only when graph is absent, stale, or not suited to the question.
6. Read exact line ranges after the graph identifies target files.
7. If graph is missing, recommend `./install.sh --init-repo "$PWD"` from the efficiency hooks repo.
```

- [ ] **Step 4: Create Ponytail skill**

Create both Ponytail skill files with:

```md
---
name: ponytail
description: Use for minimal-code generation, surgical edits, reducing speculative code, or keeping output/code size low.
---

# Ponytail Mode

Use the smallest correct change.

Decision ladder:

1. Does new code need to exist at all?
2. Can existing code be reused?
3. Can stdlib or native platform APIs solve it?
4. Is an installed dependency already available?
5. Can one direct function or command solve it?
6. Write the minimum code that passes the test.

Rules:

- No speculative abstractions.
- No broad rewrites for narrow requests.
- No new production dependency without explicit approval.
- Mark intentionally minimal code with `ponytail:` only when a future maintainer might otherwise overbuild it.
- Expand the solution only when tests, correctness, or maintainability require it.
```

- [ ] **Step 5: Create Codex hooks**

Create `.codex/hooks.json` by copying `templates/codex-hooks.json`.

- [ ] **Step 6: Validate skill files**

Run:

```bash
for f in .agents/skills/*/SKILL.md .claude/skills/*/SKILL.md; do
  grep -q '^---$' "$f" || exit 1
  grep -q '^name:' "$f" || exit 1
  grep -q '^description:' "$f" || exit 1
done
bash tests/run-tests.sh
```

Expected: command exits `0` and tests pass.

- [ ] **Step 7: Commit task 5**

Run:

```bash
git add AGENTS.md CLAUDE.md .agents .claude .codex
git commit -m "feat: add efficiency skills"
```

---

### Task 6: Documentation and End-to-End Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/CHANGELOG.md`
- Verify: all scripts and skills

**Interfaces:**
- Consumes: completed tasks 1-5
- Produces: user-facing setup docs and final verification evidence

- [ ] **Step 1: Update README**

Rewrite README sections to include:

- what autopilot installs
- quick start for current machine:
  - `./doctor.sh --repo .`
  - `./install.sh --dry-run --repo .`
  - `./install.sh --apply --repo .`
  - `./install.sh --install-tools --dry-run --repo .`
- new laptop flow:
  - clone repo
  - run doctor
  - run dry-run
  - apply install
  - initialize target repos
- tool policy:
  - RTK known-source install
  - Caveman known-source install
  - Ponytail as local skill/instructions
  - CodeGraph requires configured source
- safety:
  - backups
  - no secrets copied
  - MCP cleanup report-only
- verification:
  - `tests/run-tests.sh`
  - `doctor.sh`

- [ ] **Step 2: Update changelog**

Add an Unreleased entry:

```md
### Added
- Portable Claude/Codex efficiency autopilot with doctor, installer, graph-first hooks, skills, and tool manifest.
```

- [ ] **Step 3: Run full tests**

Run:

```bash
bash tests/run-tests.sh
./doctor.sh --repo .
./install.sh --dry-run --repo .
./install.sh --install-tools --dry-run --repo .
```

Expected:

- tests pass
- doctor completes without crashing
- install dry-run performs no global writes
- install-tools dry-run does not run network commands
- CodeGraph reports missing source if no source is configured

- [ ] **Step 4: Check for secrets**

Run:

```bash
rg -n "ANTHROPIC_AUTH_TOKEN|Bearer |BEGIN PRIVATE|SECRET|TOKEN|password|api[_-]?key" .
```

Expected: no committed secrets. Mentions in docs are allowed only as generic warning text and must not contain real values.

- [ ] **Step 5: Check Git status**

Run:

```bash
git status --short --untracked-files=all
```

Expected: only intentional files are modified or untracked.

- [ ] **Step 6: Commit task 6**

Run:

```bash
git add README.md docs/CHANGELOG.md
git commit -m "docs: document efficiency autopilot"
```

---

## Plan Self-Review

- Spec coverage: tasks cover manifest, doctor, installer, hooks, skills, durable instructions, graph-first policy, Ponytail, testing, docs, and safety.
- Placeholder scan: no unresolved marker text or open-ended implementation placeholders are intentional in this plan.
- Interface consistency: `doctor.sh` and `install.sh` both consume `bootstrap/tools.json` and `lib/efficiency-common.sh`; hook tests use the existing hook script names plus new `graph-first-block.sh`; skills are duplicated under `.agents/skills` and `.claude/skills` for Codex and Claude install paths.
