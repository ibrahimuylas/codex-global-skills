---
name: ralph
description: Use Ralph autonomous development from Codex chat. Use when the user says "use ralph", asks Ralph to create requirements or specs from chat, initialize Ralph in a project, make a Ralph plan, implement requirements with Ralph, run Ralph build iterations, use Codex as the Ralph backend, manage IMPLEMENTATION_PLAN.md or PROGRESS.md, or develop with Ralph without typing terminal commands.
---

# Ralph

Use Ralph as the loop runner while keeping the user in Codex chat. Prefer cautious, reviewable steps: create specs first, plan next, build one iteration at a time unless the user explicitly asks for more.

## Operating Model

- Work in the current project directory unless the user names another path.
- Prefer the Codex backend: `-b codex`.
- Use `--skip-push` for build runs unless the user explicitly asks to push.
- Use one build iteration by default: `-n 1`.
- Before any Ralph command, confirm `ralph` is available with `command -v ralph`; if not, try `$HOME/.local/bin/ralph`.
- If `codex` is missing, explain that Ralph's Codex backend requires the Codex CLI and stop before planning/building.
- If Docker or the devcontainer CLI is unavailable, Ralph can still run outside the sandbox, but mention that Ralph is intended to run inside `ralph sandbox` for isolation.
- Do not manually implement plan items when the user asked Ralph to build. Let Ralph run the loop, then summarize results.

## Requirements From Chat

When the user says "use ralph and implement requirements below", "generate requirements with ralph", or asks to turn chat into Ralph-ready requirements:

1. Create `specs/` if needed.
2. Choose a numbered, descriptive filename rather than overwriting a generic file, for example `specs/001-nunjucks-ui-test.md`.
3. If existing specs are present, inspect their naming and follow the local pattern.
4. Convert the conversation into a concise spec using this structure:

```md
# <Feature or Goal Name>

## Goal

## Background

## User Stories

## Functional Requirements

## Non-Functional Requirements

## Acceptance Criteria

## Applicable Rules

## Out of Scope

## Open Questions
```

Rules for spec authoring:

- Capture only requirements supported by the conversation or repository evidence.
- Put uncertainties in `Open Questions`; do not invent decisions.
- Keep acceptance criteria testable.
- Use `Applicable Rules` to reference relevant local rules, such as Equal Experts rules, when available.
- If the user asks for a single `requirements.md`, comply, but prefer numbered specs for ongoing work.

## Ralph Plan

When the user asks to make or update a Ralph plan:

1. Inspect `specs/`, `AGENTS.md`, package/build files, and existing `IMPLEMENTATION_PLAN.md` if present.
2. Run `ralph init` if Ralph artifacts are missing.
3. Run:

```bash
ralph plan -b codex -n 3 -g "Implement the active specs in specs/"
```

If the user names one spec, use:

```bash
ralph plan -b codex -n 3 -g "Implement <spec path>"
```

After planning:

- Read `IMPLEMENTATION_PLAN.md`.
- Summarize the plan, highest-priority item, open questions, and any generated/updated specs.
- Do not build in the same step unless the user asked for both.

## Ralph Build

When the user asks Ralph to implement requirements, build from the plan, or run development:

1. Read `IMPLEMENTATION_PLAN.md` and identify the highest-priority incomplete item.
2. Run one cautious iteration by default:

```bash
ralph build -b codex -n 1 --skip-push
```

3. If the user asks for multiple iterations, use their number, still defaulting to `--skip-push`.
4. After the run, inspect `git status`, `IMPLEMENTATION_PLAN.md`, `PROGRESS.md`, and relevant test output.
5. Summarize:
   - completed plan item
   - files changed
   - tests run and result
   - whether commits were created
   - next recommended iteration

If Ralph fails, report the failing command, the key error lines, and the safest next step.

## EE Rules Convention

If the project contains Equal Experts LLM toolkit rules or an EE rules skill is available:

- Reference relevant rules from the spec's `Applicable Rules` section.
- Load only the rules needed for the task.
- Keep Ralph specs as the source of product intent and EE rules as development constraints.
- Prefer local project rules over global defaults when both exist.

Do not copy entire external rule sets into specs. Link or name the applicable rule files instead.
