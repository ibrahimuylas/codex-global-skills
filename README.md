# Codex Global Skills

Portable global Codex skills for software development with Ralph and the Equal Experts LLM toolkit.

The intended workflow is:

1. Install these global skills once per machine.
2. Apply the EE toolkit once per project when you want EE rules/templates in that repo.
3. Use EE skills to clarify and break down work.
4. Use Ralph as the main planning and implementation loop.

## Skills

| Skill | Use it for | Example prompt |
| --- | --- | --- |
| `ralph` | Specs, Ralph planning, Ralph build iterations | `Use ralph and implement the requirements below. Do not push.` |
| `equal-experts-workflow` | Apply EE toolkit to a repo and select EE rules | `Apply EE toolkit to this repo.` |
| `ee-clarify` | Refine vague ideas into scoped work | `Use ee-clarify to refine this idea.` |
| `ee-breakdown` | Split large work into small tasks | `Use ee-breakdown to split this feature for Ralph.` |
| `ee-control-plane` | Bootstrap architecture/convention docs | `Use ee-control-plane to set up project context.` |
| `commit` | Atomic Conventional Commits | `Commit current changes.` |

Detailed docs:

- [Ralph](docs/ralph.md)
- [Equal Experts workflow](docs/equal-experts-workflow.md)
- [EE clarify](docs/ee-clarify.md)
- [EE breakdown](docs/ee-breakdown.md)
- [EE control plane](docs/ee-control-plane.md)
- [Commit](docs/commit.md)

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

- initializes submodules
- installs or updates Ralph from `https://github.com/marc0der/ralph.git`
- installs OpenAI Codex CLI if missing
- installs devcontainer CLI if missing
- installs all skills into `${CODEX_HOME:-$HOME/.codex}/skills`
- links the EE toolkit into each EE skill
- adds Ralph's default binary directory to `~/.zshrc` when needed

After install, start a new Codex chat or restart Codex if skills are not visible immediately.

## Update Global Skills

Open this repository in Codex and say:

```text
update global skills
```

Codex runs:

```bash
./update.sh
```

## Check Installation

Open this repository in Codex and say:

```text
check global skills
```

Codex runs:

```bash
./doctor.sh
```

The doctor checks installed commands, installed skills, EE toolkit links, Ralph, and Docker reachability.

## Terminal Usage

```bash
git clone <this-repo-url> codex-global-skills
cd codex-global-skills
./install.sh
./doctor.sh
```

To update later:

```bash
cd codex-global-skills
./update.sh
```

## Recommended Project Workflow

In a target project, apply the EE toolkit once:

```text
Apply EE toolkit to this repo.
```

This adds the EE toolkit at:

```text
prompts/library
```

Then shape work:

```text
Use ee-clarify to refine this idea.
```

```text
Use ee-breakdown to split this feature into Ralph-sized tasks.
```

Then use Ralph:

```text
Use ralph to create a spec from this.
```

```text
Use ralph to plan the active specs.
```

```text
Use ralph to implement one iteration. Do not push.
```

## Repository Layout

```text
AGENTS.md
install.sh
update.sh
doctor.sh
skills/
  ralph/
  equal-experts-workflow/
  ee-clarify/
  ee-breakdown/
  ee-control-plane/
  commit/
vendor/
  equalexperts/
    llm-toolkit/
docs/
```

## Adding Skills

Add new skills under `skills/<skill-name>/`.

Rules:

- Use lowercase hyphenated names.
- Keep `SKILL.md` concise.
- Put human docs in `docs/`.
- Put third-party libraries under `vendor/` as submodules.
- Re-run `./install.sh` after adding or editing skills.
