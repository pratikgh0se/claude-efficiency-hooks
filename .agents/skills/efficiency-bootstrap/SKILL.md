---
name: efficiency-bootstrap
description: Use when setting up Claude or Codex token-efficiency autopilot, installing hooks, auditing missing tools, or preparing a new laptop from this repo.
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
