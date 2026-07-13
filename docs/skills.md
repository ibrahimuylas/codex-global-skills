# Skill Catalog

The repository currently ships developer-focused global Codex skills. Install a pack, start a new Codex task, then invoke a workflow explicitly with `$skill-name` when you want deterministic routing.

| Skill | Use it for | Example prompt | Guide |
| --- | --- | --- | --- |
| `repo-map` | Read-only orientation in an unfamiliar repository | `Use $repo-map to map the entry points, commands, and request flow.` | [Guide](repo-map.md) |
| `ee-control-plane` | Bootstrap architecture and convention docs | `Use $ee-control-plane to set up shared project context.` | [Guide](ee-control-plane.md) |
| `ee-clarify` | Turn a vague idea into scoped, testable work | `Use $ee-clarify to refine this checkout idea.` | [Guide](ee-clarify.md) |
| `ee-breakdown` | Split large or risky work into manageable items | `Use $ee-breakdown to create Ralph-sized tasks.` | [Guide](ee-breakdown.md) |
| `decision-record` | Capture a durable architecture decision | `Use $decision-record to record why we chose PostgreSQL.` | [Guide](decision-record.md) |
| `equal-experts-workflow` | Safely install or update the EE toolkit and select relevant rules | `Use $equal-experts-workflow to apply the EE toolkit to this repo.` | [Guide](equal-experts-workflow.md) |
| `ralph` | Create specs, make guarded plans, and run explicitly invoked uncommitted implementation iterations | `Use $ralph to implement one iteration and leave the result uncommitted.` | [Guide](ralph.md) |
| `debug` | Reproduce a failure and isolate its root cause | `Use $debug to diagnose this intermittent test failure.` | [Guide](debug.md) |
| `dependency-maintenance` | Assess and update dependencies in safe batches | `Use $dependency-maintenance to update patch versions and verify them.` | [Guide](dependency-maintenance.md) |
| `quality-gate` | Execute repository-native checks and report PASS, FAIL, or INCONCLUSIVE | `Use $quality-gate to run all required checks.` | [Guide](quality-gate.md) |
| `local-review` | Review local Git changes for actionable defects | `Use $local-review to review the current diff.` | [Guide](local-review.md) |
| `commit` | Create atomic commits using the repository's convention | `Use $commit to commit only the documentation changes.` | [Guide](commit.md) |
| `git-workflow` | Safely manage branches, sync, publication, and explicit history operations | `Use $git-workflow to push this branch without creating a PR.` | [Guide](git-workflow.md) |
| `release-readiness` | Make a holistic release decision from checks, compatibility, operations, and rollback evidence | `Use $release-readiness to assess this release without publishing it.` | [Guide](release-readiness.md) |

## Routing Notes

Natural-language requests can trigger matching skills, but explicit invocation is the safest choice when several workflows could apply. For example, a request about “checking readiness” might mean `quality-gate` when you only want commands run, or `release-readiness` when you want a broader release decision.

`local-review` and `release-readiness` are read-only by default. `quality-gate` executes checks and reports evidence; it does not make the broader release decision. Repository checks can generate files, so the skill reports any such changes.
