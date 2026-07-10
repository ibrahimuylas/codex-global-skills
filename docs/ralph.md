# Ralph Skill

The `ralph` global Codex skill lets a developer use Ralph from chat without manually typing Ralph commands.

## Common Prompts

```text
Use ralph and create requirements from this chat.
```

```text
Use ralph and implement the requirements below.
```

```text
Use ralph to plan specs/001-feature.md, but do not build yet.
```

```text
Use ralph to run one build iteration. Do not push.
```

```text
Use ralph with EE rules to create a spec and plan it.
```

## Behavior

- Creates numbered specs under `specs/`.
- Runs `ralph init` when Ralph artifacts are missing.
- Uses the Codex backend by default: `-b codex`.
- Uses cautious build defaults: `-n 1 --skip-push`.
- Reads and summarizes `IMPLEMENTATION_PLAN.md` and `PROGRESS.md`.

## Dependencies

The global installer installs or updates:

- Ralph CLI from `https://github.com/marc0der/ralph.git`
- OpenAI Codex CLI via `npm install -g @openai/codex`
- Devcontainer CLI via `npm install -g @devcontainers/cli`

Project-specific `ralph init` still happens inside each target project when the skill is used there.

## Recommended Flow

1. Use `ee-clarify` if the request is vague.
2. Use `ee-breakdown` if the work is too large.
3. Apply EE toolkit to the repo once if you want project-local rules.
4. Use `ralph` to create specs, plan, and run build iterations.
5. Use `quality-gate` and `local-review` before `commit`.
6. Use `release-readiness` before tagging or publishing.
