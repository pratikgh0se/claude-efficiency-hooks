## Token efficiency autopilot

- Prefer graph-first discovery: if `.codegraph/` exists and `codegraph_explore` works, use it before raw `rg`, `find`, full-file reads, or broad shell exploration.
- Use bounded `rg` only when graph is absent, stale, or not suited to the question.
- Read exact line ranges after graph or search identifies the target.
- Use RTK commands for shell output when available: `rtk grep <pattern> -r`, `rtk read`, `rtk ls`, and `rtk git status/diff/log`.
- Use Ponytail mode by default: smallest working change, reuse existing code, no speculative abstractions.
- Keep durable instructions concise because they consume context every turn.
