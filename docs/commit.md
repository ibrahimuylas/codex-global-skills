# Commit

Use `commit` to create clean atomic commits.

## Good Prompts

```text
Use commit to commit the current changes.
```

```text
Use commit and split unrelated changes into separate commits.
```

## Behavior

- reviews `git status` and diffs first
- groups changes by logical concern
- stages explicit paths only
- writes Conventional Commit messages
- avoids committing Ralph loop artifacts unless explicitly requested

## Commit Format

```text
feat(scope): add useful behavior
fix(scope): correct broken behavior
docs: update setup instructions
test: add coverage for edge case
```
