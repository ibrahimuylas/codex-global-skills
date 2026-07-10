# Commit

Ask Codex to commit when current changes are ready to save locally. The global `commit` skill inspects the worktree, isolates the requested scope, and creates logical commits. It does not push or create a pull request.

## Good Prompts

```text
Commit current changes.
```

```text
Commit current changes as separate atomic commits.
```

```text
Commit only the documentation changes.
```

```text
Commit the parser fix, but leave the generated files and README changes unstaged. Do not push.
```

## Behavior

- reviews `git status` and diffs first
- reads repository instructions and recent history before choosing a message convention
- groups changes by logical concern
- stages explicit paths only
- follows the repository's commit convention when one exists
- uses an imperative Conventional Commit message when no repository convention exists
- lets configured hooks run and never bypasses them
- reports the resulting commit hashes and any remaining changes
- avoids committing Ralph loop artifacts unless explicitly requested
- does not amend published commits or rewrite history without explicit authorization
- does not push, open a pull request, merge, tag, or publish

Run `quality-gate` and `local-review` first when the change needs verification or review evidence. The `commit` skill does not silently substitute for either workflow.

## Commit Convention

Repository policy comes first. Codex checks `AGENTS.md`, contribution documentation, commit tooling, and recent history for an established format. Conventional Commits are the portable fallback, not a global requirement:

```text
feat(scope): add useful behavior
fix(scope): correct broken behavior
docs: update setup instructions
test: add coverage for edge case
```

Keep each commit to one logical, reviewable, independently revertible change. Add a body when the motivation, trade-off, or consequence is not clear from the subject and diff.

## Commit Is Not Push

Authorization is intentionally narrow:

- `Commit these changes` authorizes commits only.
- `Commit and push these changes` authorizes both operations.
- `Push this branch` does not authorize creating a pull request.
- Creating a pull request does not authorize merging it.

Use `git-workflow` for branch creation, upstream checks, synchronization, pushes, and pull requests. Keeping these workflows separate makes the destination and external side effects visible before they happen.
