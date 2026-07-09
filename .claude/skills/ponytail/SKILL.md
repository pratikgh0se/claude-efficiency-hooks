---
name: ponytail
description: Use when minimizing generated code, keeping edits surgical, avoiding speculative abstractions, or reducing output size.
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
