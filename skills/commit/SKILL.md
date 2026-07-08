---
name: commit
description: Create fine-grained atomic Git commits with Conventional Commit messages. Use when the user asks to commit, save changes, create commits, split commits, or commit current work after implementation or review.
---

# Commit

Create readable, atomic commits. Review the diff first; never stage unrelated work.

## Workflow

1. Inspect `git status --short`.
2. Review unstaged and staged diffs with `git diff` and `git diff --staged`.
3. Check recent style with `git log --oneline -10`.
4. Group changes into logical commits.
5. Stage selectively with explicit paths:

```bash
git add -- <paths>
```

6. Commit each group with a Conventional Commit message.

## Message Format

```text
<type>[optional scope]: <imperative subject>

[optional short body]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`.

Rules:

- Subject should be imperative, concise, and specific.
- Prefer one logical change per commit.
- Use a body only when the subject is not enough.
- Do not use `git add -A` or `git add .` when the tree contains separable concerns.
- Do not commit local loop artifacts unless the user explicitly asks: `IMPLEMENTATION_PLAN.md`, `PROGRESS.md`, `.ralph/`, `PROMPT_plan.md`, `PROMPT_build.md`.
- Do not add tool-generated signatures unless the repository already uses one.

If the working tree mixes unrelated user changes with your changes, commit only the relevant paths and leave the rest untouched.
