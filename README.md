# Codex Global Skills

Portable global Codex skills for taking software work from an unclear idea to a verified release. The collection combines focused repository workflows, Ralph's implementation loop, and selected Equal Experts (EE) workflows.

## How To Use The Skills

Run `./install.sh` once, then start a new Codex task. Codex discovers each installed skill from its `SKILL.md` metadata and loads the full instructions when a request matches. Name a skill explicitly when you want a particular workflow:

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
| `equal-experts-workflow` | Apply the EE toolkit and select relevant rules | `Use $equal-experts-workflow to apply the EE toolkit to this repo.` |
| `ralph` | Create specs, plan work, and run implementation iterations | `Use $ralph to implement one iteration. Do not push.` |
| `debug` | Reproduce a failure and isolate its root cause | `Use $debug to diagnose this intermittent test failure.` |
| `dependency-maintenance` | Assess and update dependencies in safe batches | `Use $dependency-maintenance to update patch versions and verify them.` |
| `quality-gate` | Run repository-native checks and report readiness | `Use $quality-gate to run all required checks.` |
| `local-review` | Review local Git changes for actionable defects | `Use $local-review to review the current diff.` |
| `commit` | Create atomic Conventional Commits | `Use $commit to commit only the documentation changes.` |
| `release-readiness` | Check versioning, notes, migrations, compatibility, and artifacts | `Use $release-readiness to assess this release without publishing it.` |

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
- [Release readiness](docs/release-readiness.md)

## Recommended Delivery Lifecycle

Use only the stages that add value for the change:

1. **Orient:** use `repo-map` when the codebase or affected flow is unfamiliar.
2. **Align:** use `ee-control-plane` for missing project context and `decision-record` for a durable technical choice.
3. **Shape:** use `ee-clarify`, then `ee-breakdown` when the result is still too large.
4. **Constrain:** use `equal-experts-workflow` to select applicable EE rules for the project or Ralph spec.
5. **Build:** use `ralph` to create specs, plan, and implement small iterations.
6. **Diagnose or maintain:** use `debug` for unexplained failures and `dependency-maintenance` for dependency changes.
7. **Verify:** run `quality-gate`, then `local-review` before committing.
8. **Save and release:** use `commit`, then `release-readiness` before tagging or publishing.

A common feature flow is:

```text
$ee-clarify -> $ee-breakdown -> $ralph -> $quality-gate -> $local-review -> $commit -> $release-readiness
```

`local-review` and `release-readiness` are read-only by default. `quality-gate` does not intentionally fix files, but repository checks can generate files; it reports any such changes. Ask separately if you want Codex to implement findings or publish anything.

## Why EE Has Global Skills And A Submodule

Keep the high-value EE wrapper skills global. The two layers serve different purposes:

- `vendor/equalexperts/llm-toolkit` is the pinned upstream **source and resource library**. It owns the reusable rules, prompts, commands, and templates.
- `equal-experts-workflow` and the `ee-*` skills are small **discovery and workflow wrappers**. Their metadata tells Codex when to use the toolkit and their instructions define a dependable chat workflow.

Codex does not discover a generic vendor directory as a named skill, so the wrappers make common workflows easy to invoke. They reference or link to the submodule; they must not copy its rule content. Keep only wrappers that provide a distinct, frequently used workflow. Do not create one global skill for every EE rule or command.

The global toolkit copy is enough for one-off guidance. Apply the toolkit as a submodule at `prompts/library` inside a target project when the project should pin the rules, share them with the team, or reference them from Ralph specs and project guidance.

See [Using the Equal Experts toolkit](docs/equal-experts-workflow.md) for the decision guide.

## Install Global Skills

Open this repository in Codex and say:

```text
install global skills
```

Codex follows [AGENTS.md](AGENTS.md) and runs:

```bash
./install.sh
```

The installer:

- initializes the EE toolkit submodule
- installs or updates Ralph
- installs OpenAI Codex CLI and devcontainer CLI when missing
- copies every directory under `skills/` to `${CODEX_HOME:-$HOME/.codex}/skills`
- links the EE toolkit into the EE wrapper skills
- adds Ralph's default binary directory to `~/.zshrc` when needed

Start a new Codex task or restart Codex if newly installed skills are not immediately visible.

## Update And Check

From this repository, ask Codex to `update global skills` or run:

```bash
./update.sh
```

To verify the installation, ask Codex to `check global skills` or run:

```bash
./doctor.sh
```

The doctor discovers skill directories dynamically, checks each source and installed `SKILL.md` and `agents/openai.yaml`, verifies EE toolkit links only for EE wrappers, and checks required commands, Ralph, and Docker reachability.

## Terminal Setup

```bash
git clone <this-repo-url> codex-global-skills
cd codex-global-skills
./install.sh
./doctor.sh
```

## Repository Layout

```text
AGENTS.md
install.sh
update.sh
doctor.sh
validate.sh
skills/
  <skill-name>/
    SKILL.md
    agents/openai.yaml
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

Use lowercase hyphenated names, keep third-party libraries as submodules under `vendor/`, and never copy large upstream rule sets into a skill.

Validate source files before installation:

```bash
./validate.sh
```

The repository validator checks shell syntax, skill frontmatter, UI metadata, developer guides, README catalog entries, TODO markers, and whitespace without requiring Python packages. For new or substantially changed skills, also use Codex's `$skill-creator` validator. Then run `./install.sh` and `./doctor.sh`.
