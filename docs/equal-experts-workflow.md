# Equal Experts Workflow

The `equal-experts-workflow` skill makes the Equal Experts LLM toolkit discoverable and usable from Codex chat. It applies the toolkit to projects and selects only the rules or templates relevant to the current work.

## Why Keep Global EE Wrappers?

The toolkit submodule and the global skills are complementary:

- `vendor/equalexperts/llm-toolkit` is the pinned upstream source for rules, prompts, commands, and templates.
- `equal-experts-workflow`, `ee-clarify`, `ee-breakdown`, and `ee-control-plane` provide skill metadata, trigger phrases, and focused workflows that Codex can discover.

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
