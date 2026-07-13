# Global Git Guidance

Git guidance is deliberately split into three layers.

1. The installer-managed block in `${CODEX_HOME:-$HOME/.codex}/AGENTS.md` supplies small, repository-agnostic safety rules. These are always available: preserve unrelated work, inspect Git state before mutations, stage explicit paths, keep secrets out of commits, avoid destructive history operations, and preserve the authorization boundaries between commit, push, pull-request, merge, tag, and publish outcomes.
2. The global `commit` and `git-workflow` skills supply repeatable procedures when a developer invokes them. `commit` creates logical commits. `git-workflow` handles branches, remotes, upstreams, synchronization, publication, and explicitly requested history or recovery work.
3. A repository's own `AGENTS.md`, contribution guide, hooks, and CI configuration define project policy: branch prefixes, ticket references, commit scopes, merge strategy, required checks, signing, release conventions, and whether direct commits are allowed.

The global layer intentionally does not impose organization-specific rules such as `feat/` versus `feature/`, a fixed default branch or remote, mandatory Conventional Commits, or mandatory pull requests. The skills inspect and follow repository conventions first; when no commit convention exists, `commit` uses Conventional Commits as a portable fallback.

The managed block is bounded by these markers:

```html
<!-- codex-global-skills:git-safety:start -->
<!-- codex-global-skills:git-safety:end -->
```

The installer creates `AGENTS.md` when it is missing, appends the block when no managed block exists, and replaces exactly one valid managed block on later runs. Content before and after the markers remains user-owned and is preserved. A lone, duplicate, or misordered managed marker causes a safe failure before skill mutation. Symbolic links and other non-regular `AGENTS.md` targets are also rejected so a dotfile-managed target is never silently replaced; use a regular file or install the marked block through that dotfile workflow.

See [Commit](commit.md) and [Git workflow](git-workflow.md) for examples and authorization boundaries.
