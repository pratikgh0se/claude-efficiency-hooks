---
name: graph-first
description: Use when doing code discovery, symbol lookup, caller or callee tracing, or repository exploration where CodeGraph may be available.
---

# Graph First

1. Check whether `.codegraph/` exists and `codegraph_explore` is available.
2. If graph is ready, use `codegraph_explore "<question or symbols>"` before grep/find/Read.
3. Use `codegraph_search query="<name>"` for symbol location.
4. Use `codegraph_node file="<path>"` for file plus dependency context.
5. Fall back to bounded `rg` only when graph is absent, stale, or not suited to the question.
6. Read exact line ranges after the graph identifies target files.
7. If graph is missing, recommend `./install.sh --init-repo "$PWD"` from the efficiency hooks repo.
