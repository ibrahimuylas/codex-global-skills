# Delivery Lifecycle

Use only the stages that add value for the change.

1. **Orient:** use `repo-map` when the codebase or affected flow is unfamiliar.
2. **Align:** use `ee-control-plane` for missing project context and `decision-record` for a durable technical choice.
3. **Shape:** use `ee-clarify`, then `ee-breakdown` when the result is still too large.
4. **Constrain:** use `equal-experts-workflow` to select applicable EE rules for the project or Ralph spec.
5. **Build:** use `ralph` to create specs, plan, and implement small iterations.
6. **Diagnose or maintain:** use `debug` for unexplained failures and `dependency-maintenance` for dependency changes.
7. **Verify:** run `quality-gate`, then `local-review` before committing.
8. **Save and share:** use `commit` to save logical changes, then `git-workflow` when you explicitly want to manage a branch, synchronize it, push it, or open a pull request.
9. **Release:** use `release-readiness` before tagging or publishing.

A common feature flow is:

```text
$ee-clarify -> $ee-breakdown -> $ralph -> $quality-gate -> $local-review -> $commit -> $git-workflow -> $release-readiness
```

`commit` does not imply push, and push does not imply creating a pull request. Omit `git-workflow` when the work should remain local.
