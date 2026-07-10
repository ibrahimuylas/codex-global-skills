# Git Workflow

Use the global `git-workflow` skill for branch, remote, upstream, synchronization, push, pull-request, merge, tag, history, and recovery operations. It complements `commit`: `commit` creates new commits, while `git-workflow` manages the surrounding repository state and how committed work is shared.

## Good Prompts

```text
Use $git-workflow to create a branch for this work using the repository's naming convention.
```

```text
Use $git-workflow to check whether this branch is safe to push. Do not push yet.
```

```text
Push the current branch to its existing upstream. Do not create a pull request.
```

```text
Push this branch and open a draft pull request with a summary and test evidence.
```

```text
Use $git-workflow to inspect the bad rebase and explain the safest recovery option. Do not change anything yet.
```

```text
Use $git-workflow to revert commit abc123. Do not push.
```

## Behavior

Before changing Git state, the skill reads repository guidance and inspects:

- the worktree and staged changes
- the current and default branches
- configured remotes and the branch's upstream
- ahead, behind, and divergence state
- recent branch and commit conventions

It preserves unrelated work, detects the repository's actual default branch and remote, and follows project-local naming and review policy. It does not assume `main`, `origin`, a particular branch prefix, or one merge strategy.

For synchronization, the skill fetches first and reports divergence before choosing a safe repository-compatible action. It does not silently recreate a deleted upstream, rebase published work, or overwrite unexpected remote history. Force pushes require explicit authorization, use `--force-with-lease`, and are never performed against a protected or default branch.

For pull requests, the skill prepares a focused summary, records validation performed, calls out follow-up work, and respects repository templates and required checks. It opens a pull request only when explicitly requested and does not merge it unless separately authorized. A pull-request request may publish the current topic branch when that push is a necessary and unambiguous prerequisite.

History operations such as amend, rebase, reset, cherry-pick, revert, branch deletion, and reflog recovery are performed only when the request specifically requires them. The skill inspects whether affected commits are published, prefers additive or recoverable options when they meet the request, and never stashes, discards, or moves existing work as automatic cleanup.

## Authorization Boundaries

Each external or history-changing operation needs matching user intent:

| Request | Authorized result |
| --- | --- |
| `Commit the changes` | Local commit only; no push |
| `Push the branch` | Push to the verified destination; no pull request |
| `Open a pull request` | Create the pull request; no merge |
| `Merge the pull request` | Merge using repository policy; no tag or release |
| `Tag` or `publish` | Only the explicitly requested tag or release action |

Destructive operations such as hard resets, cleaning untracked files, broad restoration, history rewriting, bypassing hooks, or bypassing branch protection are outside the normal workflow. They require explicit authorization, and repository protections are never silently circumvented.

## Where Git Rules Belong

- `${CODEX_HOME:-$HOME/.codex}/AGENTS.md` contains the installer-managed, always-on safety baseline.
- `commit` and `git-workflow` contain reusable procedures invoked for a task.
- A repository's `AGENTS.md`, contribution guide, hooks, and CI define its concrete branch, commit, review, merge, signing, and release policy.

This separation keeps global behavior safe without imposing one team's conventions on every repository.
