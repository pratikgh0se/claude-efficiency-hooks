# Efficiency Repair and Upgrade Design

## Goal

Repair unsafe or non-functional target-repository initialization, then add the current low-risk token-efficiency guidance without mutating a user's enabled MCP set.

## Design

`--init-repo` will install a self-contained helper bundle at
`.codex/claude-efficiency-hooks/` and generate Codex hooks that invoke that
bundle. The installer will merge its hook entries into an existing
`.codex/hooks.json`, preserving unrelated entries and rejecting malformed or
structurally incompatible JSON before writing.

Graph-first blocking will require both an index and all three CodeGraph
commands. Doctor will continue to be read-only, but warn once the combined
Codex and Claude MCP count reaches a configurable advisory budget (default
20). The warning recommends task-scoped tool selection; it does not disable or
rewrite any server configuration.

## Error Handling

- Existing invalid JSON is backed up then leaves the active file untouched; the
  installer exits non-zero with a precise error.
- Existing valid Codex hook objects are retained verbatim unless they are an
  exact duplicate of an entry managed by this installer.
- A stale `.codegraph/` directory does not block discovery when the commands
  are unavailable.

## Verification

Regression tests prove the old failures: copied helpers are executable,
existing hooks survive initialization, malformed Claude and Codex JSON is not
replaced, graph blocking requires usable commands, and Doctor warns at the MCP
budget. The complete Bash suite and a real read-only Doctor audit are required.

## Documentation

README and installed instruction templates will describe lean durable context,
task-scoped tools/MCPs, stable cache prefixes, phase/session boundaries, and
measurement. API-specific cache controls remain guidance only because this
repository does not own an API client.
