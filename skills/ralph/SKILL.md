---
name: ralph
description: Operate Ralph autonomous development from Codex chat when the user explicitly invokes Ralph or asks to create or update Ralph specs, initialize Ralph, make a Ralph plan, run Ralph build iterations, or manage IMPLEMENTATION_PLAN.md or PROGRESS.md. Use ee-clarify for vague work and ee-breakdown for decomposition before Ralph; do not trigger for generic implementation requests.
---

# Ralph

Use Ralph as the loop runner while keeping the user in Codex chat. Prefer cautious, reviewable steps: create specs first, plan next, build one iteration at a time unless the user explicitly asks for more.

## Repository Preflight

1. Read repository instructions and inspect the current branch, `git status`, relevant diffs, existing specs, `IMPLEMENTATION_PLAN.md`, `PROGRESS.md`, and Ralph configuration before any mutation.
2. Classify the requested phase as spec authoring, initialization, planning, or building. State which existing files will be updated and which missing files may be created.
3. Preserve unrelated and user-authored changes. Never stash, clean, reset, replace an existing spec, or rerun initialization over partial artifacts to make the workspace look clean.
4. Require a clean working tree before a build unless every existing change is confirmed as an intended build input. Stop for direction when unrelated changes share the workspace or branch policy would be violated.

## Operating Model

- Work in the current project directory unless the user names another path.
- Use the managed Codex backend and the developer's Codex model selection. Do not pass a backend unless checking or explaining a rejection; the guarded runner sources `global-skill.env`, enforces Codex, and removes pinned Ralph's upstream model argument when no model override was requested so Codex can use its own configuration.
- Treat Ralph's displayed upstream model as informational only during model deferral. The guarded runner prints a notice because Ralph builds its banner before the scoped Codex shim removes that unpassed default.
- Never run raw `ralph init`, `ralph plan`, or `ralph build`. Pinned init scaffolds an opinionated commit skill, and the upstream plan/build paths trust mutable prompts and PATH resolution. Use this skill's reviewed init, plan, and build helpers. Use global `$commit` and `$git-workflow` separately when the user authorizes those outcomes.
- Use one build iteration by default: `-n 1`.
- For plan/build, let the guarded runner resolve and checksum the managed Ralph binary. By default it uses `${CODEX_GLOBAL_SKILLS_HOME:-$HOME/.local/share/codex-global-skills}/ralph-runtimes/<runtime-id>/bin/ralph` on the host and the verified `/usr/local/bin/ralph` mount when `DEVCONTAINER=true`, deliberately ignoring an unrelated `ralph` earlier on `PATH`.
- The guarded runner enforces the reviewed Codex CLI version and managed Codex backend default on both host and devcontainer. Stop on a missing or mismatched CLI, a missing/modified `global-skill.env`, or a request for another backend.
- The `ralph` pack intentionally requires Docker's devcontainer CLI so the supported container flow is available. A guarded host run remains possible when Docker is unavailable, but it has no container workspace boundary.
- Enter, rebuild, or clean Ralph's container only through `scripts/run-sandbox-guarded.sh`; never run raw `ralph sandbox` through ambient `PATH`. The launcher verifies the managed CLI and reviewed container-configuration contract, removes the upstream Docker-socket/host-network/host-home mounts, uses a dedicated sandbox home, nests the Ralph skill there through a read-only mount, and controls the `ralph` selected for `/usr/local/bin/ralph`. Container rebuilds still resolve the base image, OS packages, and npm transitive inputs; do not describe the image as byte-reproducible.
- On a dedicated sandbox's first use, tell the user to run `codex login` inside it. The credential persists under `${CODEX_GLOBAL_SKILLS_HOME:-$HOME/.local/share/codex-global-skills}/ralph-sandbox-home/.codex` and is available to the backend. The workspace remains writable and outbound networking remains enabled, so describe the container as containment and credential separation, never an absolute security boundary.
- Do not manually implement plan items when the user asked Ralph to build. Let Ralph run the loop, then summarize results.

## Git Authorization

- Treat Ralph's backend prompt as executable behavior. The pinned prompt invokes Ralph's bundled commit skill, which forces its own message and attribution policy, and also runs `git push` before Ralph evaluates `--skip-push`.
- The guarded runner verifies and executes the managed pinned Ralph binary directly, substitutes a byte-for-byte reviewed prompt, blocks ordinary `git push`/`git send-pack` calls (including literal URLs), overrides configured remote push URLs, and passes `--skip-push`. These are defense-in-depth controls, not a network sandbox: an unrestricted backend could bypass PATH or use another network client. Never claim remote writes are technically impossible; stop if any guard fails and report the residual boundary.
- Do not infer commit authorization from a request to create specs, initialize, plan, or build. The build leaves changes uncommitted. After reviewing the diff and validation, invoke the installed global `$commit` only when the user has separately authorized local commits; that workflow discovers and follows repository conventions and attribution policy.
- The guarded runner records the `HEAD` commit and symbolic/detached identity, the index tree, all Git refs, and security-relevant repository metadata (local/worktree config, hooks, excludes/info, and alternates). It requires them to remain unchanged and returns failure if the backend persists a history, branch, staging, remote, hook, or exclusion change. Preserve the evidence; do not rewrite, delete, or unstage it automatically.
- Do not amend, rebase, squash, push, open a pull request, merge, tag, or publish without the corresponding separate authorization. Follow project branch policy before any later commit.

## Requirements From Chat

When the user says "use ralph and implement requirements below", "generate requirements with ralph", or asks to turn chat into Ralph-ready requirements:

1. Create `specs/` if needed.
2. Inspect existing specs and follow their naming. Update a named spec only when requested; otherwise create the next numbered descriptive file, for example `specs/001-nunjucks-ui-test.md`.
3. Never overwrite an existing generic or numbered spec to avoid choosing a new name.
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
2. When required artifacts are absent, run the bundled safe initializer. It creates only missing `specs/`, `IMPLEMENTATION_PLAN.md`, and `PROGRESS.md`; it preserves `.gitignore`, `.claude/`, and existing artifacts:

```bash
<ralph-skill>/scripts/init-safe.sh
```

3. Run the guarded planner:

```bash
<ralph-skill>/scripts/run-plan-guarded.sh -n 3 -g "Implement the active specs in specs/"
```

If the user names one spec, use:

```bash
<ralph-skill>/scripts/run-plan-guarded.sh -n 3 -g "Implement <spec path>"
```

After planning:

- Read `IMPLEMENTATION_PLAN.md`.
- Inspect the complete Git-visible diff and untracked-path list. The guarded planner fails if anything outside `IMPLEMENTATION_PLAN.md` or `specs/` changes relative to the pre-existing baseline.
- Summarize the plan, highest-priority item, open questions, and any generated/updated specs.
- Do not build in the same step unless the user asked for both.

## Ralph Build

When the user asks Ralph to implement requirements, build from the plan, or run development:

1. Read `IMPLEMENTATION_PLAN.md` and identify the highest-priority incomplete item.
2. Complete the repository preflight. Commit authorization is not required to run the no-commit build.
3. Record the current `HEAD` commit and identity, index tree, refs, and guarded Git metadata, then run one cautious iteration through the bundled guarded wrapper:

```bash
<ralph-skill>/scripts/run-build-no-push.sh -n 1
```

4. If the user asks for multiple iterations, repeat one wrapper iteration at a time. Review each diff and result before starting the next; do not pass a larger iteration count through as one unreviewed batch.
5. After each run, verify the guarded HEAD/index/ref/repository-metadata invariants; inspect `git status`, the diff, `IMPLEMENTATION_PLAN.md`, `PROGRESS.md`, and relevant test output.
6. If the user authorized local commits, invoke global `$commit` only after that review and exclude Ralph-local artifacts (`IMPLEMENTATION_PLAN.md`, `PROGRESS.md`, `PROMPT_*.md`, and `.ralph/`) unless the repository explicitly tracks them. If publication was also requested, hand it to `$git-workflow` after the commit result is inspected.
7. Summarize:
   - completed plan item
   - files changed
   - tests run and result
   - whether `HEAD`, index, and refs remained unchanged during Ralph and whether a separately authorized commit was later created
   - next recommended iteration

If Ralph fails, report the failing command, the key error lines, and the safest next step. Preserve unrelated baseline failures as evidence and follow-up work; do not broaden the iteration to fix them.

## EE Rules Convention

If the project contains Equal Experts LLM toolkit rules or an EE rules skill is available:

- Reference relevant rules from the spec's `Applicable Rules` section.
- Load only the rules needed for the task.
- Keep Ralph specs as the source of product intent and EE rules as development constraints.
- Prefer local project rules over global defaults when both exist.
- Inside the guarded container, use a project-local `prompts/library` toolkit. Host-absolute links from global EE wrappers are intentionally not mounted into the dedicated sandbox profile.

Do not copy entire external rule sets into specs. Link or name the applicable rule files instead.

## Report

List created and updated Ralph artifacts, the requested phase, commands run, tests and results, the Ralph HEAD/index/ref/repository-metadata invariants, any separately authorized commits, final branch and working-tree status, unrelated pre-existing changes, and the next safe step. State that publication was not technically prevented, whether the guarded container or host path was used, and whether any publication command or evidence was observed.
