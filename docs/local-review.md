# Local Review

Use `local-review` for a read-only code review of staged, unstaged, untracked, or branch-local changes before committing or opening a PR.

## Good Prompts

```text
Use $local-review to review all current local changes.
```

```text
Use $local-review to compare this branch with main and focus on compatibility and missing tests.
```

## What It Reviews

- correctness, security, data loss, reliability, and concurrency
- API, schema, and behavioral compatibility
- meaningful performance regressions
- test gaps for changed behavior

Findings are ordered from `P0` (catastrophic) to `P3` (small but actionable), cite the narrowest useful changed lines, and explain the trigger and impact. Style preferences and speculative concerns are excluded.

The skill does not modify the working tree. If findings are valid, ask Codex to fix selected items, rerun `$quality-gate`, and review again.
