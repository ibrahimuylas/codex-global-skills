---
name: git-workflow
description: Safely manage Git branches, remotes, upstreams, synchronization, pushes, pull requests, and explicitly requested history operations. Use when the user asks to create or switch branches, fetch or pull, inspect or configure tracking, push, open a pull request, merge, tag, cherry-pick, revert, amend, rebase, recover, or perform another Git operation beyond creating new commits.
---

# Git Workflow

Perform only the requested Git operation. Preserve user-owned work and follow repository policy before global defaults.

## Preserve Authorization Boundaries

- Treat commit, push, pull-request creation, merge, tag, release, and history rewrite as distinct actions.
- A request to commit does not authorize a push. Use `$commit` for new commits.
- A request to push does not authorize a pull request. A pull-request request may publish only the current topic branch when that push is necessary and unambiguous; it does not authorize merging.
- Do not amend, rebase, reset, cherry-pick, revert, delete, restore, clean, force-push, or otherwise change history or worktree state unless the request requires that specific operation.
- Do not bypass hooks, signing policy, required checks, reviews, or branch protection. Never use `--no-verify` to make an operation pass.

## Inspect Before Mutating

1. Read applicable `AGENTS.md` files and repository documentation.
2. Inspect the worktree, current branch, remotes, tracking configuration, and recent history:

```bash
git status --short --branch
git branch --show-current
git remote
git config --get-regexp '^branch\..*\.(remote|merge)$'
git worktree list --porcelain
git log --oneline -10
```

3. Determine the repository's default branch from local remote metadata or the hosting provider. Do not assume `main`, `master`, or `origin`.
4. Identify staged, unstaged, and untracked work before switching or rewriting. Check linked worktrees before switching, deleting, or rewriting a branch. Never stash, discard, or move another person's changes automatically.
5. Check ahead/behind state against the intended upstream. Fetch the selected remote without pruning when fresh remote state is required. When upstream existence matters, verify it read-only with `git ls-remote --exit-code --heads <verified-remote> <upstream-ref>`; do not treat a stale remote-tracking ref as proof that the upstream still exists.
6. Do not print raw remote URLs. If a URL must be inspected, redact any embedded credentials before it reaches command output.

Treat the default branch, and any branch reported as protected by repository policy or the hosting provider, as protected.

## Manage Branches and Synchronization

- Follow repository or environment branch naming rules. Otherwise use a short descriptive topic-branch name.
- Create or switch branches only when doing so will not overwrite or entangle existing work. Stop if the dirty worktree makes ownership or intent ambiguous.
- Use the configured upstream when it is valid. Do not silently change remotes or recreate a tracking branch that disappeared.
- For a newly created local branch with no tracking configuration, verify the intended remote and destination branch name and check for an existing remote-ref collision before creating the remote branch and setting upstream.
- Prefer fast-forward-only pulls when no integration strategy is specified. If fast-forwarding is impossible, report the divergence before merging or rebasing.
- Never merge, rebase, or update the default branch merely as a side effect of another request.

## Push Safely

Push only when explicitly requested or when publishing the current topic branch is a necessary, unambiguous prerequisite of an explicitly requested pull request.

1. Fetch and verify the intended remote, current branch, upstream, and divergence.
2. Push only the current branch unless the user names another ref. Do not push all branches or tags implicitly.
3. If a normal push is rejected, inspect and report the divergence. Do not automatically pull, rebase, merge, or force-push.
4. Never force-push the default branch or another protected branch.
5. Force-push a non-protected branch only when the user explicitly authorizes it, and use `--force-with-lease`, never `--force`.

## Create Pull Requests

- Create a pull request only when explicitly requested.
- Verify the base branch, head branch, remote, and included commits before publication.
- Follow the repository template and conventions. Summarize the change, list validation performed, and disclose limitations or follow-up work.
- Do not merge, enable auto-merge, request reviewers, or modify labels unless requested or required by documented repository policy.

## Handle History and Recovery

- Inspect affected commits and whether they are published before amending or rebasing. Rewriting published history requires explicit authorization.
- Prefer additive or recoverable operations, such as `git revert` or creating a recovery branch from the reflog, when they satisfy the request.
- Before destructive operations such as `reset --hard`, `clean`, forced branch deletion, or discarding file changes, show the exact scope and obtain explicit authorization. Never run them as automatic cleanup.
- Do not delete unknown untracked files or automatic stashes.

## Report the Result

State the resulting branch and upstream, the operation performed, relevant commit hashes or pull-request URL, validation or hooks run, push status, and any remaining worktree changes. Report failures and ambiguity instead of claiming completion.
