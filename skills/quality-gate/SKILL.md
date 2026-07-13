---
name: quality-gate
description: Execute repository-native formatting, linting, type-checking, testing, build, and other validation commands, then report PASS, FAIL, or INCONCLUSIVE with evidence. Use for requests to run checks or verify a local change before commit or pull request. Use release-readiness for a holistic tag, publication, deployment, or release decision.
---

# Quality Gate

Execute the requested validation without silently fixing findings or making a release decision.

## Workflow

1. Read repository instructions and inspect `git status`, the relevant diff, manifests, task runners, and CI configuration.
2. Determine the authoritative checks from repository documentation and automation. Prefer repository-defined commands over guessed tool invocations.
3. Match the checks to the requested scope. Include formatting, linting, type-checking, tests, builds, generated-file checks, migrations, or other gates only when the repository requires them.
4. Run each independent check even when another check fails. Skip a downstream check only when a failed prerequisite makes its result invalid.
5. Record the exact command, exit status, and concise failure evidence. Preserve useful file, line, test, and error identifiers.
6. Avoid installing dependencies, starting external services, changing configuration, applying fixes, staging files, or committing unless the user explicitly requests it.
7. Inspect `git status` again. Report any files produced or changed by validation; do not delete or revert them without permission.
8. Assign the gate result:
   - `PASS`: run every required check and observe no failures.
   - `FAIL`: observe at least one required check fail.
   - `INCONCLUSIVE`: leave a required check unidentified, skipped, blocked, or unable to run.

## Report

Report in this order:

1. State the gate result and the scope checked.
2. List failures first with exact commands and actionable evidence.
3. List blocked or skipped checks with reasons.
4. Summarize passing checks without dumping successful logs.
5. State any validation-created working-tree changes and the smallest useful next step.

Treat `PASS` as evidence that the identified checks passed, not as a merge or release decision. Never report `PASS` for a partial or inconclusive run. Never hide a failure by rerunning it with weaker options.
