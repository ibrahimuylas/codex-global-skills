# Codex Global Skills

Portable global Codex skills, packs, and installer for reusable software-development workflows.

This repository installs focused Codex skills that help move work from a vague idea to a verified change: repository orientation, requirement shaping, Ralph implementation loops, quality checks, local review, Git safety, and release readiness. The current catalog is developer-focused; the pack system is ready for future writer, business-analysis, endurance-athlete, or automation-runner collections when those skills exist.

## Quick Start

Open this repository in Codex and say:

```text
install global skills
```

Codex follows [AGENTS.md](AGENTS.md) and runs:

```bash
./install.sh --install-dependencies
```

Then start a new Codex task and invoke a skill by name:

```text
Use $repo-map to show me where this change belongs.
```

Natural-language requests can also trigger skills, but explicit `$skill-name` prompts are clearer when workflows overlap.

## Skills

| Skill | Use it for |
| --- | --- |
| `repo-map` | Read-only orientation in an unfamiliar repository |
| `ee-control-plane` | Bootstrap architecture and convention docs |
| `ee-clarify` | Turn a vague idea into scoped, testable work |
| `ee-breakdown` | Split large or risky work into manageable items |
| `decision-record` | Capture a durable architecture decision |
| `equal-experts-workflow` | Install or select Equal Experts toolkit rules |
| `ralph` | Create specs, make guarded plans, and run implementation iterations |
| `debug` | Reproduce a failure and isolate its root cause |
| `dependency-maintenance` | Assess and update dependencies in safe batches |
| `quality-gate` | Execute repository-native checks and report readiness evidence |
| `local-review` | Review local Git changes for actionable defects |
| `commit` | Create atomic commits using repository conventions |
| `git-workflow` | Manage branches, sync, publication, and explicit history operations |
| `release-readiness` | Assess release readiness without publishing |

See [Skill catalog](docs/skills.md) for example prompts and individual guides.

## Common Delivery Flow

Use only the stages that add value:

```text
$ee-clarify -> $ee-breakdown -> $ralph -> $quality-gate -> $local-review -> $commit -> $git-workflow -> $release-readiness
```

`commit` does not imply push, and push does not imply creating a pull request. Use `git-workflow` only when you explicitly want branch synchronization, publication, pull-request creation, or history work.

See [Delivery lifecycle](docs/lifecycle.md) for when to use each stage.

## Maintenance Commands

```bash
./install.sh --list-packs
./install.sh --pack developer-core
./install.sh --pack developer-core --pack equal-experts
./update.sh
./doctor.sh
./validate.sh
./tests/run.sh
```

For details, see:

- [Install, update, and doctor](docs/install.md)
- [Skill packs](docs/packs.md)
- [Global Git guidance](docs/global-git-guidance.md)
- [Ralph](docs/ralph.md)
- [Equal Experts workflow](docs/equal-experts-workflow.md)
- [Skill evaluations](docs/evaluations.md)
- [Repository layout](docs/repository-layout.md)
- [Adding a skill](docs/adding-a-skill.md)

## Terminal Setup

```bash
git clone <this-repo-url> codex-global-skills
cd codex-global-skills
./install.sh --install-dependencies
./doctor.sh
```
