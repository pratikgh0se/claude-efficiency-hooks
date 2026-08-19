## Token efficiency autopilot

- Set `/model` and `/effort` at session start; avoid switching mid-task because it can invalidate cache.
- Use `/clear` between unrelated tasks and `/compact` when switching context inside related work.
- Keep `CLAUDE.md` concise; every instruction rides along every turn.
- Enable only task-relevant MCP servers and tools; large tool schemas consume context every turn.
- Keep stable instructions, toolsets, and task context at the prompt prefix to improve cache reuse.
- Start with the lowest reasoning effort that passes the task; raise it only when verification shows a quality gain.
- If `.codegraph/` exists and `codegraph_explore` works, use CodeGraph before grep/find/Read.
- Use `rtk grep <pattern> -r`, `rtk read`, `rtk ls`, and `rtk git status/diff/log` for shell exploration.
- Prefer Caveman-style concise output for routine status.
- Use Ponytail mode by default: smallest working change, reuse existing code, no speculative abstractions.
- Measure with `rtk gain`, `rtk gain --history`, `rtk discover`, and `/usage`.
