# Dependency Maintenance

Use `dependency-maintenance` to assess or perform intentional dependency updates without combining unrelated risk.

## Good Prompts

```text
Use $dependency-maintenance to identify safe patch updates. Do not change files yet.
```

```text
Use $dependency-maintenance to update the logging dependencies in one verified batch.
```

```text
Use $dependency-maintenance to plan the React major-version upgrade and identify migration work.
```

## Workflow

- discover manifests, lockfiles, workspace boundaries, runtime constraints, and repository policy
- classify direct and transitive updates by purpose, compatibility, security relevance, and migration risk
- consult authoritative release notes or advisories when current external facts are required
- group tightly related changes into small batches
- update manifests and lockfiles with the repository's package manager only when requested
- run focused tests after each batch and the full repository gate before declaring success

Do not mix cleanup or broad formatting into an update. Major upgrades and security fixes should receive explicit migration, compatibility, and rollback attention. End with changed versions, evidence, remaining risk, and deferred updates.
