## Git safety and working agreements

- Read repository instructions and inspect recent history before choosing commit, branch, merge, or release conventions.
- Before local Git mutations, inspect the working tree and current branch. Before network or publication operations, also inspect remotes and upstream configuration.
- Preserve unrelated and user-owned changes. Never discard, overwrite, hide, or include them in the current task.
- Never run destructive operations such as `reset --hard`, `clean`, broad restoration, or history rewriting without explicit authorization.
- Stage only task-related paths. Never stage secrets, credentials, local environment files, or unrelated changes; follow repository policy for intentionally tracked environment templates.
- Keep each commit to one logical, reviewable, independently revertible change.
- Follow the repository's commit convention. If none exists, use Conventional Commits with an imperative subject and add a body when motivation or consequences are not obvious.
- Require matching user intent before committing, pushing, opening a pull request, merging, tagging, or publishing. A pull-request request may publish only the current topic branch when that push is necessary and unambiguous. A request to commit does not imply push, a request to push does not imply a pull request, and a pull-request request does not imply merge.
- Before pushing, fetch and verify the intended remote and upstream. Do not silently recreate a deleted upstream or push to an unexpected remote.
- Never force-push a protected or default branch. Use `--force-with-lease` elsewhere only with explicit authorization.
- Do not amend or rebase published commits without explicit authorization.
- Never bypass Git hooks, required checks, reviews, or branch protections.
- Report commit hashes, branch, remote, validation performed, push status, and any remaining working-tree changes.
