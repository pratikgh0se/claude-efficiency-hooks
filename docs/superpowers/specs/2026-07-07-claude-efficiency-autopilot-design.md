# Claude Efficiency Autopilot Design

Date: 2026-07-07
Status: Approved for specification, pending user review before implementation planning

## Purpose

Turn this repository from a small hook collection into a repeatable Claude/Codex efficiency bootstrap kit. The goal is not to make the user think about token cost. The repo should install guardrails, defaults, and repo-init helpers that keep agents on the cheapest good path during normal work.

Phase one focuses on existing tools working together: Claude Code hooks, Codex hooks, durable instructions, skills, RTK, CodeGraph, Ponytail, Caveman, ccusage, and audit/repair scripts.

## Success Criteria

- A new laptop can reproduce the setup from this repo without manual reconstruction.
- This laptop can be remediated safely with backups and idempotent config merges.
- Claude and Codex prefer graph-first code discovery when a code graph exists.
- Expensive command patterns are blocked or redirected before they pollute context.
- Token-saving behavior is mostly automatic, with manual approval only for installs, secrets, broad MCP changes, or risky global config edits.
- Secrets and auth values from existing user config are never copied into the repo.

## Non-Goals

- Do not hardcode unknown or unverifiable CodeGraph install commands.
- Do not commit user secrets, copied `settings.json`, auth tokens, or machine-specific credentials.
- Do not disable MCP servers automatically without user approval.
- Do not force high-risk model changes or change model/effort mid-session.
- Do not replace the user's habit of opening a repo and typing `claude` or `codex`.

## Architecture

The repository will provide five layers.

### 1. Bootstrap Manifest

Add manifest files that describe what the efficiency stack expects:

- required tools: `claude`, `jq`, `python3`, `md5` or `md5sum`
- recommended tools: `rtk >= 0.43.0`, `ccusage`
- managed modes: Caveman and Ponytail
- graph tools: `codegraph_explore`, `codegraph_node`, `codegraph_search`
- install source metadata, when known
- detection commands
- safe remediation guidance

The manifest is the source of truth for `doctor.sh`, `install.sh`, and future Claude/Codex skills.

### 2. Doctor and Repair

Add `doctor.sh` as a fast read-only audit:

- Claude Code version and hook status
- Codex version and hook/config status
- RTK presence and minimum version
- CodeGraph presence and repo index state
- Ponytail/Caveman rule availability
- ccusage/statusline availability
- MCP count and failed MCP health signals
- global instruction block freshness
- project instruction block freshness

Add repair modes to `install.sh`:

- `--dry-run`: show planned changes
- `--apply`: update current laptop
- `--portable`: print/setup new-laptop bootstrap path
- `--init-repo PATH`: initialize graph/rules for a target repo

All write modes must create timestamped backups before editing home config.

### 3. Claude Code Autopilot

Claude Code gets the strongest enforcement because hooks can intercept tool use.

Install or update these hook behaviors:

- `Bash`: block `cat`, unbounded `find`, raw exploratory `grep`, noisy `git log`, broad `ls`, and unbounded pipelines when safer graph/RTK alternatives exist.
- `Grep` and `Glob`: when `.codegraph/` exists and graph tools are available, block broad exploratory search and instruct `codegraph_explore` first.
- `Read`: preserve the existing reread guard; additionally discourage full-file exploratory reads when a graph query should be used first.
- `Stop`: monitor context size and remind or require `/compact` before expensive continuation.
- `UserPromptSubmit` or session-start equivalent where available: remind model/effort/cache discipline only when useful, not every turn.

The hook messages should be short and actionable. They should say exactly which cheaper command or workflow to use next.

### 4. Codex Autopilot

Codex gets parallel support through its documented durable surfaces:

- repo/global `AGENTS.md` guidance
- `.agents/skills`
- `.codex/hooks.json` or `.codex/config.toml`
- optional plugin packaging later

Codex hooks should mirror Claude behavior where the current Codex hook API supports it:

- pre-tool checks for Bash and MCP graph tools
- stop/context reminders
- project-local hooks that resolve paths from the git root

Codex instructions must state graph-first behavior clearly:

1. If `.codegraph/` exists and graph tools work, use CodeGraph before `rg`, `find`, `cat`, broad `Read`, or raw shell exploration.
2. Use bounded `rg` only when graph is absent, stale, or not suited to the question.
3. Use exact line-range reads after graph search identifies the target.
4. Use Ponytail/minimal-code mode by default.

### 5. Claude/Codex Skills

Add repo-scoped skills:

- `efficiency-bootstrap`: runs doctor, explains findings, and applies setup after explicit user approval.
- `graph-first`: initializes or refreshes CodeGraph for a repo, then guides code discovery through graph tools.
- `ponytail`: minimal-code-generation mode for the smallest correct change.

For Claude Code, equivalent skill/command material should be installed under the user's Claude home when applying global setup. For Codex, skills live in `.agents/skills` and can later be packaged as a plugin.

## CodeGraph Policy

CodeGraph is first-class in phase one. The installer should:

- detect graph tool commands
- detect `.codegraph/`
- initialize or refresh repo graph indexes when commands are available
- add graph-first rules to Claude and Codex instructions
- block broad code discovery patterns when graph is ready

If the CodeGraph installer source is unknown, the system must fail clearly:

> CodeGraph is required for full autopilot, but no install source is configured. Add the installer to `bootstrap/tools.json` or install CodeGraph manually, then rerun doctor.

This avoids pretending a guessed package is the real internal tool.

## Ponytail Policy

Ponytail is implemented as a local mode/skill rather than a binary unless a real tool is later discovered.

Rules:

- prefer the smallest working change
- reuse existing code before adding abstractions
- use stdlib/native APIs before new dependencies
- avoid speculative options and broad rewrites
- mark intentionally minimal code when useful
- expand only when tests, correctness, or maintainability require it

Ponytail should be on by default in instructions, with an escape hatch for work that needs a fuller design.

## Config Safety

Global files are edited only through marked blocks:

```md
<!-- BEGIN claude-efficiency-hooks -->
...
<!-- END claude-efficiency-hooks -->
```

JSON/TOML config merges should preserve existing user settings and avoid touching unrelated keys. The installer must not print, store, or template secret values.

Backups should go under a user-local backup directory, not into the repo.

## Automation Levels

Autopilot should do the routine work:

- install and merge rules
- detect missing tools
- initialize graph indexes
- block expensive command patterns
- prefer graph/RTK routes
- monitor context growth
- surface measurement commands

Smart escalation should still ask for approval:

- network installs
- global MCP disablement
- broad auth/config changes
- unknown CodeGraph installer source
- destructive file operations

Manual decision remains for:

- task quality tradeoffs that truly require higher models or higher effort
- secrets/auth values
- accepting untrusted hooks in Codex

## Testing and Verification

Implementation should include focused shell tests or fixtures for:

- hook payload parsing
- blocked vs allowed Bash commands
- graph-ready vs graph-missing behavior
- reread tracking
- context monitor thresholds
- idempotent config block replacement
- doctor output for present/missing/stale tools

Manual verification should include:

- `./doctor.sh`
- `./install.sh --dry-run`
- hook scripts with sample Claude payloads
- Codex hook shape validation against documented `hooks.json` structure
- no secrets copied into repo files

## Rollout Plan

1. Add manifests, shared helpers, and doctor.
2. Upgrade hooks and add tests.
3. Add Claude/Codex instruction blocks and skills.
4. Replace installer with idempotent dry-run/apply/portable/init-repo modes.
5. Run local verification.
6. Apply to current laptop only after approval for writes outside the repo.

## Phase-One Decisions

- CodeGraph install source: implement the manifest slot, detection, graph-first rules, and repo initialization. Do not invent an installer. If no authoritative source is configured, doctor fails loudly with the action needed.
- MCP cleanup: phase one reports inactive, failed, and high-count MCP surfaces, but does not disable them automatically. An explicit cleanup mode can be added after the user reviews doctor output.
- Graph initialization: `install.sh --init-repo PATH` is the deterministic path. Session-start hooks may detect missing graph state and recommend initialization, but they must not run heavy indexing implicitly unless a future config flag opts in.
