# Codex Global Skills

Portable global Codex skills for taking software work from an unclear idea to a verified release. The collection combines focused repository workflows, Ralph's implementation loop, selected Equal Experts (EE) workflows, and a small set of Git safety rules that apply across repositories.

The current catalog is developer-focused. Packs now provide the reusable architecture for future writer, business-analysis, endurance-athlete, or automation-runner collections, but those role-specific skills are not claimed or installed yet.

## How To Use The Skills

Install the default `developer` pack once, then start a new Codex task. Codex discovers each installed skill from its `SKILL.md` metadata and loads the full instructions when a request matches. Name a skill explicitly when you want a particular workflow:

```text
Use $repo-map to show me where this change belongs.
```

Natural-language requests such as `Run every project check and tell me whether this is ready` can also trigger the matching skill. Explicit `$skill-name` prompts are the clearest choice when several workflows could apply.

## Skills

| Skill | Use it for | Example prompt |
| --- | --- | --- |
| `repo-map` | Read-only orientation in an unfamiliar repository | `Use $repo-map to map the entry points, commands, and request flow.` |
| `ee-control-plane` | Bootstrap architecture and convention docs | `Use $ee-control-plane to set up shared project context.` |
| `ee-clarify` | Turn a vague idea into scoped, testable work | `Use $ee-clarify to refine this checkout idea.` |
| `ee-breakdown` | Split large or risky work into manageable items | `Use $ee-breakdown to create Ralph-sized tasks.` |
| `decision-record` | Capture a durable architecture decision (ADR) | `Use $decision-record to record why we chose PostgreSQL.` |
| `equal-experts-workflow` | Safely install or update the EE toolkit and select relevant rules | `Use $equal-experts-workflow to apply the EE toolkit to this repo.` |
| `ralph` | Create specs, make guarded plans, and run explicitly invoked uncommitted implementation iterations | `Use $ralph to implement one iteration and leave the result uncommitted.` |
| `debug` | Reproduce a failure and isolate its root cause | `Use $debug to diagnose this intermittent test failure.` |
| `dependency-maintenance` | Assess and update dependencies in safe batches | `Use $dependency-maintenance to update patch versions and verify them.` |
| `quality-gate` | Execute repository-native checks and report PASS, FAIL, or INCONCLUSIVE | `Use $quality-gate to run all required checks.` |
| `local-review` | Review local Git changes for actionable defects | `Use $local-review to review the current diff.` |
| `commit` | Create atomic commits using the repository's convention | `Use $commit to commit only the documentation changes.` |
| `git-workflow` | Safely manage branches, sync, publication, and explicit history operations | `Use $git-workflow to push this branch without creating a PR.` |
| `release-readiness` | Make a holistic release decision from checks, compatibility, operations, and rollback evidence | `Use $release-readiness to assess this release without publishing it.` |

Detailed guides:

- [Repository map](docs/repo-map.md)
- [EE control plane](docs/ee-control-plane.md)
- [EE clarify](docs/ee-clarify.md)
- [EE breakdown](docs/ee-breakdown.md)
- [Decision record](docs/decision-record.md)
- [Equal Experts workflow](docs/equal-experts-workflow.md)
- [Ralph](docs/ralph.md)
- [Debug](docs/debug.md)
- [Dependency maintenance](docs/dependency-maintenance.md)
- [Quality gate](docs/quality-gate.md)
- [Local review](docs/local-review.md)
- [Commit](docs/commit.md)
- [Git workflow](docs/git-workflow.md)
- [Release readiness](docs/release-readiness.md)
- [Skill packs](docs/packs.md)
- [Skill evaluations](docs/evaluations.md)

## Recommended Delivery Lifecycle

Use only the stages that add value for the change:

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

`local-review` and `release-readiness` are read-only by default. `quality-gate` executes checks and reports evidence; it does not make the broader release decision. Repository checks can generate files, so the skill reports any such changes. Ask separately if you want Codex to implement findings or publish anything.

`commit` does not imply push, and push does not imply creating a pull request. Omit `git-workflow` when the work should remain local.

## Global Git Rules And Repository Policy

Git guidance is deliberately split into three layers:

1. The installer-managed block in `${CODEX_HOME:-$HOME/.codex}/AGENTS.md` supplies small, repository-agnostic safety rules. These are always available: preserve unrelated work, inspect Git state before mutations, stage explicit paths, keep secrets out of commits, avoid destructive history operations, and preserve the authorization boundaries between commit, push, pull-request, merge, tag, and publish outcomes. An explicit pull-request request may publish only the current topic branch when that push is a necessary and unambiguous prerequisite.
2. The global `commit` and `git-workflow` skills supply repeatable procedures when a developer invokes them. `commit` creates logical commits. `git-workflow` handles branches, remotes, upstreams, synchronization, publication, and explicitly requested history or recovery work.
3. A repository's own `AGENTS.md`, contribution guide, hooks, and CI configuration define project policy: branch prefixes, ticket references, commit scopes, merge strategy, required checks, signing, release conventions, and whether direct commits are allowed.

The global layer intentionally does not impose organization-specific rules such as `feat/` versus `feature/`, a fixed default branch or remote, mandatory Conventional Commits, or mandatory pull requests. The skills inspect and follow repository conventions first; when no commit convention exists, `commit` uses Conventional Commits as a portable fallback.

See [Commit](docs/commit.md) and [Git workflow](docs/git-workflow.md) for examples and authorization boundaries.

## Why EE Has Global Skills And A Submodule

Keep the high-value EE wrapper skills global. The two layers serve different purposes:

- `vendor/equalexperts/llm-toolkit` is the pinned upstream **source and resource library**. It owns the reusable rules, prompts, commands, and templates.
- `equal-experts-workflow` and the `ee-*` skills are small **discovery and workflow wrappers**. Their metadata tells Codex when to use the toolkit and their instructions define a dependable chat workflow.

Codex does not discover a generic vendor directory as a named skill, so the wrappers make common workflows easy to invoke. They reference or link to the submodule; they must not copy its rule content. Keep only wrappers that provide a distinct, frequently used workflow. Do not create one global skill for every EE rule or command.

The global toolkit copy is enough for one-off guidance. Apply the toolkit as a submodule at `prompts/library` inside a target project when the project should pin the rules, share them with the team, or reference them from Ralph specs and project guidance.

Installed EE wrappers contain absolute links to this repository's pinned toolkit checkout. The v2 managed manifest fingerprints that target, so rerunning the installer from a moved clone can relocate an otherwise unchanged managed link without trusting an arbitrary redirect. `doctor.sh` rejects unrecorded, locally changed, or stale links. Ralph's guarded container deliberately mounts a dedicated Codex home rather than the host profile, so use a project-local `prompts/library` submodule when EE rules must also be available inside that container.

See [Using the Equal Experts toolkit](docs/equal-experts-workflow.md) for the decision guide.

## Install Global Skills

Open this repository in Codex and say:

```text
install global skills
```

Codex follows [AGENTS.md](AGENTS.md) and runs:

```bash
./install.sh --install-dependencies
```

The explicit dependency flag installs missing or mismatched pinned CLIs and synchronizes the managed Ralph checkout. If selected dependencies already match, `./install.sh` alone performs no network installation.

The repository currently ships developer workflows. The installer defaults to the complete `developer` pack on its first run; `all` is a separate future-proof superset so later writer, business-analysis, or athlete packs do not silently enter the developer profile. It reuses the previous managed selection later, or accepts one or more explicit packs:

```bash
./install.sh --list-packs
./install.sh --pack all
./install.sh --pack developer-core
./install.sh --pack developer-core --pack equal-experts
```

The installer:

- resolves the union of selected pack manifests under `packs/`
- checks dependencies without changing them unless `--install-dependencies` is supplied
- verifies OpenAI Codex CLI `0.143.0` and devcontainer CLI `0.87.0`, and installs missing or mismatched selected versions from exact npm packages only when explicitly requested
- initializes the pinned EE toolkit only when selected and explicitly requested
- synchronizes Ralph source at pinned commit `3c53c0ed8ed549c6aa15d9f364ae474b2b19ac10`, then publishes only its reviewed CLI, plan/build prompts, and source container files into managed state; it never runs Ralph's upstream installer against personal `~/.config/ralph` content
- verifies existing skill ownership, content hashes, symlink targets, and executable modes before staging a replacement
- adopts only previously published pre-manifest copies whose content and executable modes both match a recorded historical source; local modifications still fail safely
- applies the selected skill set with rollback, removing an omitted skill only when the previous managed copy is unchanged
- links the EE toolkit into the EE wrapper skills
- installs `guidance/git-safety.md` as a clearly marked managed block in `${CODEX_HOME:-$HOME/.codex}/AGENTS.md`
- records selected packs and their source hashes, dependencies, guidance, skill hashes, the EE target fingerprint when applicable, and a canonical state checksum in `${CODEX_HOME:-$HOME/.codex}/.codex-global-skills/manifest`

State is fail-closed: a missing pack or skill selection, unsupported dependency, duplicate entry, checksum mismatch, pack-union mismatch, or claim for an unknown skill stops before profile mutation. Recorded pack hashes let a valid old manifest remain an ownership baseline when pack definitions evolve, while unchanged pack contracts must exactly match their recorded skill/dependency/guidance union. A per-profile lock serializes installers, destinations are revalidated immediately before replacement, and the new manifest is staged before skill changes. Failure or interruption before atomic manifest publication restores both skill changes and managed `AGENTS.md` guidance while preserving concurrent edits for review; interruption after publication retains the complete committed selection rather than creating mixed state.

The managed block is bounded by these markers:

```html
<!-- codex-global-skills:git-safety:start -->
<!-- codex-global-skills:git-safety:end -->
```

The installer creates `AGENTS.md` when it is missing, appends the block when no managed block exists, and replaces exactly one valid managed block on later runs. Content before and after the markers remains user-owned and is preserved. A lone, duplicate, or misordered managed marker causes a safe failure before skill mutation. Symbolic links and other non-regular `AGENTS.md` targets are also rejected so a dotfile-managed target is never silently replaced; use a regular file or install the marked block through that dotfile workflow.

The installer never edits `.zshrc`, `.bashrc`, or another shell profile. Ralph does not need to be on `PATH`: the skill resolves its checksum-verified executable directly from managed state.

Each Ralph source/CLI/config contract has its own `${CODEX_GLOBAL_SKILLS_HOME:-$HOME/.local/share/codex-global-skills}/ralph-runtimes/<runtime-id>/` directory, separate from personal Ralph configuration and older managed pins. This makes a pin upgrade additive and non-destructive; an interrupted new contract is rolled back without touching the previous runtime. The guarded devcontainer uses a checksum-pinned reduced configuration without the host Docker socket, host networking, or the host home/credential directories. It mounts the project, a read-only verified Ralph skill, and a dedicated sandbox home under the same managed state root. On first use, run `codex login` inside the container; that dedicated credential is available to the backend and the container retains outbound network access, so this is a workspace-containment layer, not an absolute security or publication boundary. See [Ralph](docs/ralph.md).

See [Skill packs](docs/packs.md) for selection, desired-state, and future role-pack design guidance.

Start a new Codex task or restart Codex if newly installed skills are not immediately visible.

## Update And Check

From this repository, ask Codex to `update global skills` or run:

```bash
./update.sh
```

The update script requires a clean branch with a configured upstream, fast-forwards the repository, synchronizes submodule URLs and pinned gitlinks, validates the updated source, reinstalls the previously selected packs with explicit dependency synchronization, and runs the doctor. It stops before pulling when the repository has local changes, is detached, lacks an upstream, or cannot fast-forward.

To verify the installation, ask Codex to `check global skills` or run:

```bash
./doctor.sh
```

The doctor verifies the state checksum and pack contracts, reconstructs the selected union, compares source and installed directory hashes with the recorded state, verifies every EE toolkit link resolves to the exact pinned toolkit, verifies Ralph's source, isolated managed runtime, plan/build prompts, source container contract, and exact CLI versions, detects stale or locally changed copies, and checks only the dependencies relevant to the selected packs. Legacy or repository skills installed outside the managed selection are reported as warnings rather than deleted.

## Terminal Setup

```bash
git clone <this-repo-url> codex-global-skills
cd codex-global-skills
./install.sh --install-dependencies
./doctor.sh
```

## Repository Layout

```text
AGENTS.md
install.sh
update.sh
doctor.sh
validate.sh
lib/
  common.sh              # shared hashing and pack parsing helpers
packs/
  <pack-name>.pack       # declarative skill, dependency, and guidance selection
skills/
  <skill-name>/
    SKILL.md
    agents/openai.yaml
    assets/                 # optional reviewed runtime templates
    scripts/                # optional skill-scoped helpers
guidance/
  git-safety.md         # source for the installer-managed global guidance block
evals/
  routing.tsv           # positive and adjacent-negative trigger fixtures
  workflow-safety.tsv   # mutation-safety forward-test fixtures
migrations/
  legacy-skill-hashes.tsv # approved upgrade hashes from pre-manifest releases
pins/
  cli.env                 # exact managed Codex/devcontainer versions
tests/
  run.sh                # regression suite; pinned-runtime smoke may skip
  test-installer.sh     # installer and doctor state-transition tests
  test-ee-toolkit.sh    # exact submodule identity and cleanliness tests
  test-ralph-safety.sh  # safe prompt and remote-write guard tests
  test-ralph-pinned-integration.sh # optional installed-runtime dry-run
vendor/
  equalexperts/
    llm-toolkit/       # upstream git submodule; do not copy into skills
docs/
  <skill-name>.md
```

## Adding A Skill

Add each workflow under `skills/<skill-name>/` with:

- a concise `SKILL.md` containing accurate `name` and trigger-oriented `description` metadata
- `agents/openai.yaml` containing the display name, short description, and a useful default prompt
- a developer guide at `docs/<skill-name>.md`
- a row and documentation link in this README
- membership in every applicable `packs/*.pack` manifest
- positive and adjacent-negative cases in `evals/routing.tsv`
- a workflow-safety case when the skill performs fragile mutations

Use lowercase hyphenated names, keep third-party libraries as submodules under `vendor/`, and never copy large upstream rule sets into a skill.

Validate source files before installation:

```bash
./validate.sh
```

The repository validator checks shell syntax, canonical skill frontmatter constraints, UI metadata, pack grammar and coverage, developer guides, README catalog entries, routing and safety-evaluation schemas, TODO markers, and whitespace without requiring Python packages. For new or substantially changed skills, also use Codex's `$skill-creator` workflow and blind forward tests from [Skill evaluations](docs/evaluations.md).

Run the disposable-fixture behavioral suite (the installed pinned-runtime smoke skips when unavailable) and a temporary-profile installation before changing the real global profile:

```bash
./tests/run.sh
temp_home="$(mktemp -d)"
CODEX_HOME="$temp_home/codex" CODEX_GLOBAL_SKILLS_HOME="$temp_home/state" ./install.sh --pack developer-core
CODEX_HOME="$temp_home/codex" CODEX_GLOBAL_SKILLS_HOME="$temp_home/state" ./doctor.sh
```
