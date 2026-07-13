# Quality Gate

Use `quality-gate` when you need to execute and report the repository's own validation commands for a local change.

## Good Prompts

```text
Use $quality-gate to run every required check for the current change.
```

```text
Use $quality-gate to verify only the backend package before I open a PR.
```

## What It Does

- discovers authoritative format, lint, type-check, test, build, migration, and generated-file checks from repository docs, scripts, and CI
- runs independent checks even if another check fails
- reports exact failing commands and concise evidence
- returns `PASS`, `FAIL`, or `INCONCLUSIVE`
- reports files created or changed by validation

It does not install dependencies, weaken commands, fix findings, stage files, or commit unless asked separately. A partial or blocked run is `INCONCLUSIVE`, never `PASS`.

`PASS` means every identified check in scope passed. It is validation evidence, not a merge, deployment, or release decision. Use `release-readiness` for the holistic decision that also considers scope, versions, compatibility, migrations, artifacts, operations, and rollback.

## Typical Handoff

After a pass, use `$local-review`; before a release, use `$release-readiness`. After a failure, ask Codex to fix the reported issue, then run `$quality-gate` again.
