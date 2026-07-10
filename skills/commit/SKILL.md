---
name: commit
description: Create fine-grained atomic Git commits that follow repository-specific message and staging conventions, using Conventional Commits only as a fallback. Use when the user asks to commit, save changes as commits, create or split commits, or commit current work after implementation or review. Use git-workflow instead for amend, rebase, push, pull-request, or other history and publication operations.
---

# Commit

Create readable, atomic commits. Repository instructions and established conventions override global defaults. Review the diff first and never stage unrelated work.

## Workflow

1. Read applicable `AGENTS.md` files and repository contribution guidance.
2. Inspect `git status --short --branch` and identify user-owned or unrelated changes.
3. Review unstaged and staged diffs with `git diff` and `git diff --staged`.
4. Discover the repository's commit convention from documented policy, commit tooling, and recent history with `git log --oneline -10`. Use documented policy when examples conflict.
5. Group changes into independently understandable and revertible commits.
6. Stage selectively with explicit paths:

```bash
git add -- <paths>
```

7. Recheck the staged diff, including the file list, before each commit. If unrelated changes are already staged, do not unstage or include them. Use a reviewed path-limited commit such as `git commit --only -- <paths>` only when task paths do not overlap; stop when ownership or overlap is ambiguous.
8. Commit each group using the repository's message convention. If none is discoverable, use the Conventional Commit fallback below.
9. Let configured hooks run. If a hook fails, report or fix the underlying issue within scope; never bypass it with `--no-verify`.

## Fallback Message Format

Use this only when the repository defines no commit-message convention:

```text
<type>[optional scope]: <imperative subject>

[optional short body]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`.

Always:

- Subject should be imperative, concise, and specific.
- Prefer one logical change per commit.
- Use a body when motivation, tradeoffs, or consequences are not obvious from the subject and diff.
- Do not use `git add -A` or `git add .` when the tree contains separable concerns.
- Never stage suspected secrets, credentials, private keys, or local environment files. Stop and report them.
- Do not commit local loop artifacts unless the user explicitly asks: `IMPLEMENTATION_PLAN.md`, `PROGRESS.md`, `.ralph/`, `PROMPT_plan.md`, `PROMPT_build.md`.
- Do not add tool-generated signatures unless the repository already uses one.

If the working tree mixes unrelated user changes with your changes, commit only the relevant paths and leave the rest untouched.

Stop after creating the requested commits. A commit request does not authorize pushing, opening a pull request, amending, rebasing, or otherwise rewriting history. Use `$git-workflow` when the user explicitly requests one of those operations.

Report the commit hash and subject for each commit, validation and hooks run, and any remaining working-tree changes.
