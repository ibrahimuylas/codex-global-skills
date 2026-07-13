# Release Readiness

Use `release-readiness` for a final, non-publishing decision before a tag, package, deployment, or release PR.

## Good Prompts

```text
Use $release-readiness to assess version 2.4.0 without tagging or publishing it.
```

```text
Use $release-readiness to check this library for a safe breaking release.
```

## What It Checks

- intended release scope and included changes
- versions, changelog or release notes, and compatibility declarations
- database migrations, rollbacks, configuration, and deployment ordering
- generated files, packages, artifacts, and repository-defined validation
- upgrade guidance, known risks, operational checks, and rollback readiness

The result is `READY`, `NOT READY`, or `INCONCLUSIVE`, with blockers first and supporting evidence. The skill does not change versions, create tags, publish artifacts, deploy, or push unless separately authorized.

Run `$quality-gate` and `$local-review` before this assessment so release readiness can focus on release-specific risk. A quality-gate `PASS` only confirms the checks that ran; it cannot establish release scope, compatibility, migration safety, operational readiness, or rollback viability by itself.
