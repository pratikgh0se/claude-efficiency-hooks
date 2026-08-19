# claude-efficiency-hooks

Portable Claude/Codex token-efficiency autopilot: hooks, durable instructions, skills, tool audits, and repo initialization for lower-noise agent work.

The goal is simple: keep your normal `claude` and `codex` habits, while this repo quietly steers agents toward graph-first discovery, compact shell output, fewer rereads, and safer context management.

## What It Installs

- Claude Code hooks for context monitoring, reread blocking, graph-first discovery, and expensive shell command blocking.
- Codex repo hooks in `.codex/hooks.json`.
- Durable `CLAUDE.md` and `AGENTS.md` instruction blocks.
- Claude and Codex skills for efficiency bootstrap, graph-first exploration, and Ponytail minimal-code mode.
- `doctor.sh` for read-only setup audits.
- `install.sh` for idempotent global setup and target-repo initialization.
- `bootstrap/tools.json` as the source of truth for known tools and approval-gated installers.

## Quick Start

Audit first:

```bash
./doctor.sh --repo .
```

Preview global writes:

```bash
./install.sh --dry-run --repo .
```

Apply the user-level Claude setup after reviewing the dry-run:

```bash
./install.sh --apply --repo .
```

Preview tool installs without running network commands:

```bash
./install.sh --install-tools --dry-run --repo .
```

Initialize a target repo:

```bash
./install.sh --init-repo /absolute/path/to/repo
```

## New Laptop Flow

```bash
git clone <this-repo-url> claude-efficiency-hooks
cd claude-efficiency-hooks
./doctor.sh --repo .
./install.sh --dry-run --repo .
./install.sh --apply --install-tools --repo .
./install.sh --init-repo /absolute/path/to/repo
```

For a printable version:

```bash
./install.sh --portable
```

## Tool Policy

- RTK is known-source and must be `>= 0.43.0`; the installer reports the exact command but requires approval before network install.
- Caveman uses the known upstream init command and remains approval-gated.
- Ponytail is installed as local Claude/Codex skills and durable instructions.
- CodeGraph is enforced when `.codegraph/` exists, but installation is disabled until `bootstrap/tools.json` contains a real trusted source.
- MCP cleanup is report-only; this repo does not disable servers automatically. Doctor warns when the combined inventory reaches the advisory budget of 20 servers; set `CEH_MCP_WARN_THRESHOLD` to tune that warning.

## Hooks

`bash-cat-block.sh` blocks file-reading `cat`, broad raw `grep`, unbounded `find`, noisy repo-root `ls -la`, and unbounded `git log`. It recommends RTK commands when RTK is available.

`reread-warn.sh` tracks per-session file reads under `${TMPDIR:-/tmp}` and blocks the third full reread with graph-first or targeted-search guidance.

`graph-first-block.sh` blocks broad `Grep`, `Glob`, and exploratory full-file `Read` when a `.codegraph/` index is present.

`context-monitor-stop.sh` warns at 80k context tokens and urgent-blocks at 120k, with cache guidance to keep model/effort stable and compact related work before continuing.

## Current Token-Saving Methods

- Keep durable instructions and tool descriptions concise; state a policy once rather than repeating it.
- Enable only task-relevant MCP servers and tools. Their schemas are recurring context, so a large catalog can cost more than the task itself.
- Keep model, reasoning effort, system instructions, and toolsets stable during related work to preserve cache locality. Start a new session for unrelated work.
- Start with the lowest reasoning effort that satisfies the task, then compare one level higher only when a representative evaluation shows a quality gain.
- For API-backed workflows, cache stable prompt prefixes and process large, predictable tool outputs in code before returning a small result to the model.
- Measure task success, tokens, cache reads/writes, latency, and cost together. A lower-token run is useful only when it still meets the acceptance criteria.

## Safety

- Dry-run before writes.
- Backups are written under `$HOME/.claude-efficiency-hooks/backups/<timestamp>/`.
- Secrets and full user config are never copied into this repo.
- Global files are updated only inside `<!-- BEGIN claude-efficiency-hooks -->` managed blocks where possible.
- Tool installs are approval-gated; dry-run never runs network commands.

## Verification

Run the full local suite:

```bash
bash tests/run-tests.sh
```

Run the real setup audit:

```bash
./doctor.sh --repo .
```

Useful runtime measurements:

```bash
rtk gain
rtk gain --history
rtk discover
```

Use Claude Code `/usage` for session-level cost visibility.

## License

MIT
