---
name: release-readiness
description: Assess whether a repository is ready for a tag, package publication, deployment, release pull request, or breaking release without publishing it. Use for pre-release checks covering scope, versions, release notes, compatibility, migrations, artifacts, validation evidence, operational risk, and rollback readiness.
---

# Release Readiness

Evaluate release-specific risk without tagging, publishing, deploying, pushing, or changing versions.

## Workflow

1. Read repository instructions and establish the release target, intended version, audience, base tag or commit, included components, and delivery mechanism.
2. Inspect the working tree and changes since the release base. Confirm that the candidate contains the intended changes and no unrelated or uncommitted material.
3. Check version declarations, changelog or release notes, API and schema compatibility, deprecations, upgrade guidance, and declared support ranges.
4. Check database migrations, configuration changes, secrets or permissions, feature flags, deployment ordering, backward compatibility, rollback steps, and operational monitoring when relevant.
5. Check generated files, distributable artifacts, lockfiles, licenses, provenance, packaging metadata, and reproducible build expectations required by the repository.
6. Reuse recent `quality-gate` and `local-review` evidence when it matches the exact candidate. Otherwise run only safe, authorized checks and mark missing evidence as inconclusive.
7. Compare documentation and examples with the candidate behavior. Identify consumer or operator actions that must happen before, during, or after release.
8. Assign the result:
   - `READY`: find no blockers and obtain all required evidence.
   - `NOT READY`: find at least one release blocker.
   - `INCONCLUSIVE`: leave required scope or evidence unresolved.

## Report

Report blockers first, then material risks, passing evidence, unresolved checks, rollout and rollback notes, and the smallest next action. Never treat a dirty candidate, partial validation, or missing migration plan as ready.
