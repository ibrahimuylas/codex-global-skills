---
name: local-review
description: Review staged, unstaged, untracked, or branch-local Git changes for actionable correctness, security, reliability, compatibility, performance, and test defects. Use for local code review, pre-commit or pre-PR review, reviewing a diff against a base branch, or checking current changes for regressions and missing tests.
---

# Local Review

Review changes without modifying the working tree.

## Workflow

1. Read repository instructions before evaluating the change.
2. Establish the review scope from the request. When unspecified, review staged, unstaged, and untracked local changes; state the chosen scope.
3. Inspect `git status`, the applicable diffs, and untracked files. For branch review, compare against the merge base of the requested or discovered base branch.
4. Read enough surrounding code, tests, callers, schemas, configuration, and history to understand changed behavior. Do not judge a patch in isolation.
5. Trace affected paths and validate suspected defects with targeted read-only checks when practical.
6. Prioritize correctness, security, data loss, concurrency, error handling, API or schema compatibility, performance regressions, and missing tests for changed behavior.
7. Exclude preferences and speculative concerns. Report style only when it violates repository rules, obscures a defect, or causes an automated check to fail.
8. Do not edit, format, stage, commit, or otherwise alter files unless the user separately asks for fixes.

## Findings

Report findings first, ordered by severity:

- `P0`: causes catastrophic or broadly unrecoverable impact.
- `P1`: causes a likely serious regression, vulnerability, or data-loss risk.
- `P2`: causes a real defect in a meaningful scenario.
- `P3`: causes a small but actionable defect worth fixing.

For each finding:

1. Use a concise, action-oriented title.
2. Cite the narrowest changed file and line range that demonstrates the problem.
3. Explain the concrete trigger and impact.
4. State why existing handling or tests do not prevent it.
5. Suggest the smallest credible fix direction without implementing it.

After the findings, state the reviewed scope and any residual testing or evidence gaps. If no actionable findings remain, say so explicitly and still report residual risks or unverified areas.
