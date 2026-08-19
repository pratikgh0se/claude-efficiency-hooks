# Efficiency Repair and Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make initialized Codex efficiency hooks executable and merge-safe while adding advisory token-budget guidance.

**Architecture:** `install.sh` owns atomic JSON merging and copies a repo-local helper bundle. Existing hook scripts remain small, but graph enforcement checks executable availability. Doctor reports a configurable MCP budget without changing configuration.

**Tech Stack:** Bash, Python 3 standard library, jq, existing Bash test harness.

**Spec:** `docs/superpowers/specs/2026-08-19-efficiency-repair-upgrade-design.md`

## Global Constraints

- Preserve unrelated user configuration and fail closed on malformed JSON.
- Add no runtime dependency.
- Default MCP behavior is report-only; never disable an MCP server.
- Keep changes minimal and covered by real regression tests.

---

### Task 1: Make Codex initialization self-contained and merge-safe

**Files:**
- Modify: `install.sh`, `templates/codex-hooks.json`, `tests/test-install.sh`

**Interfaces:**
- Produces: `.codex/claude-efficiency-hooks/{bash-cat-block.sh,graph-first-block.sh,reread-warn.sh,context-monitor-stop.sh,lib/efficiency-common.sh}` in initialized repositories.
- Produces: a merged `.codex/hooks.json` retaining existing event entries.

- [x] **Step 1: Write failing tests**

Add assertions that initialization retains a pre-existing `^Write$` hook, has a
`^Bash$` managed hook, installs all helper files, and exits without replacing
malformed Claude or Codex JSON.

- [x] **Step 2: Run the installer tests to verify failure**

Run: `bash tests/test-install.sh`

Expected: failure because helpers are absent and an existing Codex hook is overwritten.

- [x] **Step 3: Implement the minimal installer change**

Copy helpers and `lib/` to `.codex/claude-efficiency-hooks`, point template
commands there, validate JSON before mutation, and merge missing managed hook
commands without changing unrelated event entries.

- [x] **Step 4: Run installer tests to verify success**

Run: `bash tests/test-install.sh`

Expected: `test-install: PASS`.

### Task 2: Make graph enforcement usable and add MCP budget visibility

**Files:**
- Modify: `graph-first-block.sh`, `doctor.sh`, `tests/test-hooks.sh`, `tests/test-doctor.sh`

**Interfaces:**
- `graph-first-block.sh` blocks only when `.codegraph/` and all CodeGraph commands are available.
- `doctor.sh` emits a `WARN` MCP budget check when combined server count is at least `CEH_MCP_WARN_THRESHOLD` (default `20`).

- [x] **Step 1: Write failing tests**

Assert that an index alone permits Grep, three temporary CodeGraph commands
cause the same Grep to block, and a fixture containing 20 Codex server blocks
produces an MCP budget warning.

- [x] **Step 2: Run focused tests to verify failure**

Run: `bash tests/test-hooks.sh && bash tests/test-doctor.sh`

Expected: failure because an index alone currently blocks and Doctor has no budget warning.

- [x] **Step 3: Implement the minimal behavior**

Use existing `ceh_has_codegraph_tools` when available, and add a numeric,
read-only budget check to Doctor after server counts are collected.

- [x] **Step 4: Run focused tests to verify success**

Run: `bash tests/test-hooks.sh && bash tests/test-doctor.sh`

Expected: both scripts print `PASS`.

### Task 3: Document current token-saving operating methods

**Files:**
- Modify: `README.md`, `templates/claude-efficiency-block.md`, `templates/agents-efficiency-block.md`, `docs/CHANGELOG.md`

- [x] **Step 1: Update concise durable guidance**

State lean instructions, task-scoped toolsets, stable model/tool prefixes for
caching, new sessions between unrelated phases, and measurement before changes.

- [x] **Step 2: Run the full verification suite**

Run: `bash tests/run-tests.sh && ./doctor.sh --repo . --no-mcp-health`

Expected: suite passes; Doctor remains read-only and reports any live action items.
