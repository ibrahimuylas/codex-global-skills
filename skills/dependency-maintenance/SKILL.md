---
name: dependency-maintenance
description: Audit, plan, or perform dependency updates in small verified batches across package managers and workspaces. Use when asked to check outdated or vulnerable dependencies, update packages or lockfiles, plan a major framework upgrade, assess release-note impact, or reduce dependency maintenance risk.
---

# Dependency Maintenance

Keep dependency changes intentional, reviewable, and independently verifiable.

## Workflow

1. Read repository instructions and determine whether the request authorizes an audit, a plan, or file changes.
2. Discover manifests, lockfiles, workspaces, package-manager versions, runtime constraints, dependency policies, generated files, and authoritative validation commands.
3. Record the baseline working-tree state and relevant test results before changing dependencies.
4. Identify candidate updates and classify each as direct or transitive, patch or minor or major, security-related, deprecated, unmaintained, or migration-bearing.
5. Verify current compatibility, release notes, migration guides, and advisories from authoritative primary sources when external facts are required. Do not rely on remembered latest versions.
6. Group only tightly related updates. Separate major upgrades, security remediations, framework migrations, and unrelated ecosystems unless they must move together.
7. When changes are authorized, use the repository's package manager to update manifests and lockfiles. Do not hand-edit generated lock data or bypass declared constraints.
8. Inspect each batch's diff, run focused checks, and keep failures attributable to that batch. Run the full repository quality gate after all accepted batches.
9. Preserve failed changes for review unless the user authorizes reverting them. Do not hide incompatibilities with overrides, disabled checks, or broad suppressions.

## Report

Summarize changed or proposed versions, why each batch belongs together, authoritative migration or advisory findings, verification results, unresolved risks, and deferred updates. Clearly distinguish audit findings from changes actually made.
