# Adding A Skill

Add each workflow under `skills/<skill-name>/` with:

- a concise `SKILL.md` containing accurate `name` and trigger-oriented `description` metadata
- `agents/openai.yaml` containing the display name, short description, and a useful default prompt
- a developer guide at `docs/<skill-name>.md`
- a row in the README skill table and the full [Skill catalog](skills.md)
- membership in every applicable `packs/*.pack` manifest
- positive and adjacent-negative cases in `installer/evals/routing.tsv`
- a workflow-safety case in `installer/evals/workflow-safety.tsv` when the skill performs fragile mutations

Use lowercase hyphenated names, keep third-party libraries as submodules under `vendor/`, and never copy large upstream rule sets into a skill.

Validate source files before installation:

```bash
./validate.sh
```

The repository validator checks shell syntax, canonical skill frontmatter constraints, UI metadata, pack grammar and coverage, developer guides, README catalog entries, routing and safety-evaluation schemas, TODO markers, and whitespace without requiring Python packages.

For new or substantially changed skills, also use Codex's `$skill-creator` workflow and blind forward tests from [Skill evaluations](evaluations.md).

Run the disposable-fixture behavioral suite and a temporary-profile installation before changing the real global profile:

```bash
./tests/run.sh
temp_home="$(mktemp -d)"
CODEX_HOME="$temp_home/codex" CODEX_GLOBAL_SKILLS_HOME="$temp_home/state" ./install.sh --pack developer-core
CODEX_HOME="$temp_home/codex" CODEX_GLOBAL_SKILLS_HOME="$temp_home/state" ./doctor.sh
```
