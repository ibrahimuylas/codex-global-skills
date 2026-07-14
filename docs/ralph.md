# Ralph Skill

The `ralph` global Codex skill lets a developer use Ralph from chat without manually typing Ralph commands.

## Common Prompts

```text
Use ralph and create requirements from this chat.
```

```text
Use ralph and implement the requirements below. Leave Ralph's result uncommitted.
```

```text
Use ralph to plan specs/001-feature.md, but do not build yet.
```

```text
Use ralph to run one build iteration and leave the result uncommitted.
```

```text
Use ralph with EE rules to create a spec and plan it.
```

## Behavior

- Reads repository instructions, branch and working-tree state, diffs, specs, plans, progress, and Ralph configuration before mutations.
- Creates the next numbered spec under `specs/`, or updates a named spec only when requested.
- Uses `scripts/init-safe.sh` only when required artifacts are absent. It creates missing `specs/`, `IMPLEMENTATION_PLAN.md`, and `PROGRESS.md` without touching `.gitignore`, `.claude/`, or existing artifacts.
- Uses the managed Codex backend from `global-skill.env` while leaving the model to the developer's Codex configuration unless explicitly overridden; the guarded process removes pinned Ralph's upstream model argument, while raw Ralph remains unchanged.
- Uses a guarded planner and the bundled uncommitted-build wrapper; raw `ralph init`, `ralph plan`, and `ralph build` are not used.
- The planner permits changes only to `IMPLEMENTATION_PLAN.md` and `specs/`; any new Git-visible mutation elsewhere fails while preserving evidence.
- Requires a clean build workspace unless all existing changes are confirmed build inputs.
- Verifies Ralph did not change the commit or symbolic identity of `HEAD`, the index tree, any refs, or security-relevant repository metadata such as local config, hooks, excludes, and alternates; then reads and summarizes diffs, `IMPLEMENTATION_PLAN.md`, and `PROGRESS.md` after a run.

The skill resolves its installed directory and uses these helpers rather than raw Ralph commands:

```bash
<ralph-skill>/scripts/init-safe.sh
<ralph-skill>/scripts/run-sandbox-guarded.sh
<ralph-skill>/scripts/run-plan-guarded.sh -n 3 -g "Plan the active specs"
<ralph-skill>/scripts/run-build-no-push.sh -n 1
```

## Git Authorization

The pinned Ralph backend prompt invokes Ralph's bundled commit skill, which imposes Conventional Commits and an attribution footer even when a repository has different rules. It also contains `git push`, which runs before Ralph's wrapper evaluates `--skip-push`.

Therefore the skill uses guarded plan/build helpers that verify and execute the managed pinned Ralph binary directly (ignoring PATH shadows), source the managed `global-skill.env` defaults, normalize every Ralph option, append the managed Codex backend defensively, substitute byte-for-byte reviewed prompts, and keep initialization independent of Ralph's opinionated scaffold. When no model override was requested, a narrowly scoped Codex shim removes only the pinned Ralph CLI's reviewed `--model gpt-5.2-codex` pair before delegating to the verified Codex CLI. Codex then applies its own configuration. On the host the default Ralph binary lives under `${CODEX_GLOBAL_SKILLS_HOME:-$HOME/.local/share/codex-global-skills}/ralph-runtimes/<runtime-id>/bin/ralph`; inside Ralph's devcontainer it verifies the contract-scoped `/usr/local/bin/ralph` mount.

Ralph constructs its banner and dry-run text before invoking Codex, so those displays still show its internal `gpt-5.2-codex` default. During a real guarded run without an override, the wrapper prints a model-deferral notice and the shim removes that model pair before execution. An explicit `--model` or `RALPH_GLOBAL_SKILL_MODEL` value is preserved instead.

The runner also enforces the reviewed Codex CLI version, checksum-reviewed `global-skill.env`, and Codex backend. A stale host CLI, modified managed defaults file, or sandbox rebuilt with a different Codex version fails before the agent loop starts.

The inner `codex exec` process uses `${CODEX_GLOBAL_SKILLS_HOME:-$HOME/.local/share/codex-global-skills}/ralph-backend-home` as a managed `CODEX_HOME`. That home links to the supervising Codex authentication and configuration so account and model choices remain available, but it contains no global skills or global `AGENTS.md`. Plugins are disabled and the child session is ephemeral. This prevents the inner agent from discovering the Ralph skill and recursively waiting on its own parent loop; repository-local instructions continue to load from the target worktree.

For defense in depth, the guarded runner blocks ordinary `git push` and `git send-pack` commands, including literal-URL pushes, overrides configured remote push URLs, and supplies `--skip-push` before caller options. This is not a network sandbox: an unrestricted backend could invoke an absolute binary, alter its environment, or use another network client. The skill reports this residual boundary and never describes publication as technically impossible.

The pinned CLI expects GNU-style `getopt`. The wrapper places a narrowly scoped compatibility helper first on Ralph's subprocess `PATH`, handling only Ralph's exact option schema and delegating every other `getopt` invocation to the original executable. This keeps backend selection and safety flags working on macOS without changing the developer's shell configuration.

The guarded runner requires the `HEAD` commit and symbolic/detached identity, Git index tree, every local ref, local/worktree Git config, hooks, info/excludes, and object alternates to remain unchanged. If the backend violates an invariant, it returns failure and preserves the unexpected state as evidence for review. The skill then reviews the working-tree result. A request to create a spec, initialize, plan, or build does not authorize a commit: when local commits are separately authorized, the installed global `commit` skill runs afterward and follows the target repository's convention and attribution policy. Ralph-local plan/progress/prompt artifacts stay out of that commit unless the repository explicitly tracks them. Explicitly requested publication happens later through `git-workflow`, never inside Ralph.

## Guarded Devcontainer Boundary

Run `scripts/run-sandbox-guarded.sh` on the host to enter or rebuild the supported container. The launcher verifies the pinned Ralph/Codex/devcontainer versions and reviewed configuration assets; creates a versioned configuration keyed by the complete contract fingerprint; and mounts a contract-scoped Ralph copy. Its reviewed reduced container assets omit Ralph upstream's Docker socket, `--network=host`, host `.ssh`, host GitHub configuration, and host Codex home. Instead, Ralph receives the project workspace and a dedicated home at `${CODEX_GLOBAL_SKILLS_HOME:-$HOME/.local/share/codex-global-skills}/ralph-sandbox-home`. The launcher scrubs supported host credential environment variables before starting it. A rebuild still resolves the mutable base-image tag, OS packages, and npm transitive inputs, so the resulting image is not byte-reproducible even though the launcher configuration and top-level CLI version are pinned.

On first use, run `codex login` after the container opens. The resulting credential persists in the dedicated sandbox `.codex` directory so later runs can use Codex without exposing the host profile. That credential is still readable by the backend, the project is writable, Docker containers are not an absolute host-security boundary, and default bridge networking permits outbound traffic required by Codex. Treat this as workspace containment and credential separation, not proof that exfiltration or publication is impossible.

Only a contract-scoped, read-only Ralph skill is nested into the dedicated sandbox Codex home; the writable auth/profile mount cannot replace its scripts, assets, or pin file. If the plan uses Equal Experts rules, install the toolkit project-locally at `prompts/library`; host-absolute links from global EE wrappers are intentionally not forwarded. `run-sandbox-guarded.sh clean` verifies the managed Ralph executable but bypasses a missing or damaged generated configuration, then removes every same-workspace container whose config label belongs to this tool's contract directory. It leaves unrelated devcontainers for the same project alone. A guarded host run is available when Docker is unavailable, but it has no container workspace boundary.

If a project already owns `PROMPT_plan.md` or `PROMPT_build.md`, the matching wrapper preserves it and refuses to run unless it exactly matches the reviewed bundled prompt. Move or reconcile custom prompt content deliberately. Use Ralph's `--goal` option for per-run focus without weakening the safety contract.

## Dependencies

The `ralph` and `developer` packs require:

- Ralph CLI from pinned commit `3c53c0ed8ed549c6aa15d9f364ae474b2b19ac10`
- OpenAI Codex CLI `0.144.4`, synchronized from `@openai/codex@0.144.4` when explicitly requested
- Devcontainer CLI `0.87.0`, synchronized from `@devcontainers/cli@0.87.0` when explicitly requested

`./install.sh` checks these commands and exact versions without changing the machine. Use `./install.sh --pack ralph --install-dependencies` to install missing or mismatched pinned dependencies and synchronize the managed Ralph checkout. Instead of running Ralph's upstream installer against personal configuration, it publishes only checksum-reviewed files under `${CODEX_GLOBAL_SKILLS_HOME:-$HOME/.local/share/codex-global-skills}/ralph-runtimes/<runtime-id>/`, including `global-skill.env` with `RALPH_GLOBAL_SKILL_BACKEND=codex` while leaving model selection to Codex configuration by default. A future pin receives a new directory, so the prior runtime remains intact and a partial publish can be rolled back safely. Ralph need not be on `PATH`, and the installer never edits a shell profile or changes raw Ralph's default for other tools.

Set `RALPH_GLOBAL_SKILL_MODEL` before invoking the guarded wrapper when a specific account or Codex installation needs a different supported model. An explicit `--model` argument takes precedence for that one run.

Project-specific setup uses the bundled safe initializer, not raw `ralph init`, so Ralph's `.claude/skills/commit` scaffold is never introduced by this global workflow.

## Recommended Flow

1. Optionally install `--pack equal-experts` and use `ee-clarify` if the request is vague.
2. Optionally use `ee-breakdown` if the work is too large.
3. Apply the EE toolkit project-locally if its rules must be visible in Ralph's guarded container.
4. Use `ralph` to create specs, plan, and produce an uncommitted build iteration.
5. Use `quality-gate` and `local-review`, then `commit` only when local commits were separately authorized.
6. When installed through `developer-core`, `developer`, or `all`, use `release-readiness` before tagging or publishing; it is not part of the focused `ralph` pack.
