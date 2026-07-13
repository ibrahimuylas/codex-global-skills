# Equal Experts Workflow

The `equal-experts-workflow` skill makes the Equal Experts LLM toolkit discoverable and usable from Codex chat. It safely installs or updates the toolkit when explicitly requested and selects only the rules or templates relevant to the current work.

## Why Keep Global EE Wrappers?

The toolkit submodule and the global skills are complementary:

- `vendor/equalexperts/llm-toolkit` is the pinned upstream source for rules, prompts, commands, and templates.
- `equal-experts-workflow`, `ee-clarify`, `ee-breakdown`, and `ee-control-plane` provide skill metadata, trigger phrases, and focused workflows that Codex can discover.

Installed EE wrapper skills use an absolute link back to this repository's pinned toolkit checkout. The v2 managed manifest fingerprints the target; if the source clone moves, rerunning its installer can relocate an otherwise unchanged managed link to the new pinned checkout. The installer and doctor reject an unrecorded redirect or locally changed wrapper rather than trusting it. Ralph's guarded container uses a dedicated Codex home and does not mount these host-absolute global links, so use a project-local `prompts/library` submodule when rules must be visible there.

A vendor directory is not automatically a named Codex skill. Without wrappers, developers must know the toolkit paths and manually explain which workflow to follow. The wrappers remain concise and link to the upstream files; they do not duplicate rule content.

Keep wrappers only when they add a distinct, frequently used workflow. The current set covers applying/selecting rules, clarification, breakdown, and project control-plane setup. Do not create a wrapper for every EE file.

## Global Or Project-Local?

Use the globally linked toolkit when you need one-off advice or a workflow without changing the target repository:

```text
Use $equal-experts-workflow to select EE rules for this TypeScript testing task.
```

Apply a project-local submodule when the repository should pin and share the rules, reference them from `AGENTS.md`, or include stable rule paths in Ralph specs:

```text
Use $equal-experts-workflow to apply the EE toolkit to this repo.
```

The project-local location is:

```text
prompts/library
```

Project-local instructions take precedence over global guidance. If `prompts/library` already contains unrelated content, the skill stops instead of overwriting it.

## Safe Installation And Updates

Before changing a repository, the skill checks repository instructions, branch and working-tree status, `.gitmodules`, the index, path ownership, submodule registration, origin, current commit, and local submodule changes. Existing staged or unstaged `.gitmodules` edits block `git submodule add`, because that command would stage unrelated same-file work.

An initial `git submodule add` stages `.gitmodules` and the `prompts/library` gitlink. The skill calls out that side effect, initializes only `prompts/library`, inspects the staged diff immediately, and does not stage other paths, commit, or push. An existing valid toolkit stays pinned unless the user explicitly asks to initialize or update it.

For an upstream update, the skill requires a clean submodule, verifies the expected origin and intended ref, and permits only a fast-forward. It stops on local changes, an unexpected origin, an ambiguous target, or conflicting parent-repository changes. Remote URLs are captured without printing and reported only after credential redaction. The report includes the before and after commits plus staged and unstaged paths.

## Focused EE Skills

Prefer the focused wrapper for common workflows:

```text
Use $ee-clarify to turn this idea into a scoped work item.
```

```text
Use $ee-breakdown to split this migration into Ralph-sized work.
```

```text
Use $ee-control-plane to bootstrap architecture and convention docs.
```

Use `equal-experts-workflow` for installation, rule selection, or tasks that span multiple toolkit resources.

The umbrella skill does not perform clarification, decomposition, control-plane bootstrapping, or Ralph planning/building. It may select rule paths for those workflows, then hands off to an installed focused skill. Ralph is a separate pack; compose `--pack equal-experts --pack ralph` when that handoff is required.

## Selecting Rules

Load only the rules needed for the task. Typical examples include clean code and code quality for implementation, testing principles for tests, platform-specific rules for framework work, API design for interfaces, and architecture rules for structural decisions.

Reference selected paths instead of copying the contents. A Ralph spec can contain:

```md
## Applicable Rules

- prompts/library/rules/clean-code.md
- prompts/library/rules/testing-principles.md
- prompts/library/rules/platform/typescript.rules.md
```

This keeps product intent in the spec, engineering guidance in the toolkit, and upstream updates manageable.
