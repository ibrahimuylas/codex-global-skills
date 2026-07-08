# Equal Experts Workflow Skill

The `equal-experts-workflow` global Codex skill installs and applies the Equal Experts LLM toolkit to individual repositories.

## Common Prompts

```text
Apply EE toolkit to this repo.
```

```text
Use EE rules for this TypeScript testing task.
```

```text
Use EE clarify to turn this idea into a scoped work item.
```

```text
Use EE breakdown for this large feature.
```

For dedicated clarify and breakdown workflows, prefer:

```text
Use ee-clarify to refine this idea.
```

```text
Use ee-breakdown to split this feature.
```

## Behavior

When asked to apply the toolkit to a project, the skill adds the Equal Experts toolkit as a project submodule:

```text
prompts/library
```

Then it uses selected files from:

```text
prompts/library/rules/
prompts/library/prompts/
prompts/library/commands/
```

For one-off advice, it can use the globally installed toolkit copy without modifying the target project.

## Rule Selection

The skill should load only the rules needed for the task. Examples:

- Clean implementation: `rules/clean-code.md`, `rules/code-quality.md`
- Testing: `rules/testing-principles.md`
- TypeScript/frontend: `rules/platform/typescript.rules.md`
- API work: `rules/api-design.md`
- Architecture: `rules/hexagonal-architecture.md`, `rules/domain-driven-design.md`

## Ralph Integration

When used with Ralph, EE rule paths should be referenced in each Ralph spec under `Applicable Rules`.
