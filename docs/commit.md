# Commit

Ask Codex to commit when the current changes are ready to save. The global `commit` skill handles the Git workflow behind the scenes.

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

## Behavior

- reviews `git status` and diffs first
- groups changes by logical concern
- stages explicit paths only
- writes Conventional Commit messages
- avoids committing Ralph loop artifacts unless explicitly requested

Run `quality-gate` and `local-review` first when the change needs verification or review evidence. The `commit` skill does not silently substitute for either workflow.

## Commit Format

```text
feat(scope): add useful behavior
fix(scope): correct broken behavior
docs: update setup instructions
test: add coverage for edge case
```
