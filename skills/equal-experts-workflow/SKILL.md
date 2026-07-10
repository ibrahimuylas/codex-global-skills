---
name: equal-experts-workflow
description: Install, apply, select, and use the Equal Experts LLM toolkit rules, prompts, commands, and templates in a target repository from Codex chat. Use when the user asks to apply or implement the EE toolkit, use EE rules, Equal Experts rules, llm-toolkit, development rules, rule templates, clarify or breakdown templates, or add applicable rules to Ralph specs or project guidance.
---

# Equal Experts Workflow

Use the Equal Experts LLM toolkit as a per-repository rule library. First install/apply the toolkit into the target repo when requested; then load only the rules or templates needed for the current task.

## Global Skill And Toolkit Roles

Keep this skill and the focused `ee-*` workflow skills as thin global wrappers. The toolkit submodule contains rules, prompts, commands, and templates, but it is not itself a discoverable Codex skill.

- Use global skills for invocation, workflow, rule selection, and safety boundaries across repositories.
- Use the shared toolkit link for one-off advice without changing a target repository.
- Use a project-local `prompts/library` submodule when rules must be versioned and shared with that project.
- Do not copy toolkit rule bodies into skills or create one global skill per rule.

## Apply Toolkit To A Repo

When the user says "apply ee toolkit", "implement ee toolkit", or asks to add EE rules/templates to the current project:

1. Work in the current project directory unless the user names another path.
2. Ensure the project has a `prompts/` directory.
3. If `prompts/library` already exists, inspect whether it is the Equal Experts toolkit and update it if asked.
4. If it is missing, add the toolkit as a git submodule:

```bash
mkdir -p prompts
git submodule add https://github.com/EqualExperts/llm-toolkit.git prompts/library
git submodule update --init --recursive
```

5. Summarize the installed rule/template locations and suggest any project guidance updates, such as referencing `prompts/library/rules/` from `AGENTS.md`.

If `prompts/library` exists but is not an EE toolkit checkout, stop and ask how to proceed rather than overwriting it.

## Toolkit Locations

Look for the toolkit in this order:

1. Project-local: `prompts/library/`
2. Installed skill symlink: `toolkit/`
3. Shared skills repo: `../../vendor/equalexperts/llm-toolkit/`
4. User-provided path or URL

If the toolkit is missing from the shared skills repo, suggest:

```bash
git submodule update --init --recursive
```

## Rule Selection

Start by listing available rules with:

```bash
find <toolkit>/rules -maxdepth 2 -type f | sort
```

Select only rules relevant to the current work. Common choices:

- General implementation: `rules/clean-code.md`, `rules/code-quality.md`, `rules/task-execution.md`
- Testing: `rules/testing-principles.md`
- API work: `rules/api-design.md`
- TypeScript or frontend work: `rules/platform/typescript.rules.md`
- Angular work: `rules/platform/angular-ts.rules.md`
- .NET work: `rules/platform/dotnet.rules.md`
- Security-sensitive work: `rules/platform/security.md`
- Architecture: `rules/hexagonal-architecture.md`, `rules/domain-driven-design.md`, `rules/solid-principles.md`
- Git/commit behavior: `rules/git-rules.md`
- Long-running autonomous work: `rules/long-running-tasks.md`

Read the selected files before applying them. Do not load the entire rules directory by default.

## Ralph Integration

When creating or updating Ralph specs:

- Add an `Applicable Rules` section.
- Reference rule paths instead of copying full rule content.
- Prefer project-local paths if a project has its own `prompts/library`.
- Keep product intent in `specs/*.md`; keep engineering constraints in EE rule references.

Example:

```md
## Applicable Rules

- prompts/library/rules/clean-code.md
- prompts/library/rules/testing-principles.md
- prompts/library/rules/platform/typescript.rules.md
```

If the project does not vendor the toolkit, apply it to the repo before using project-local EE rules when the user asked to "apply" or "implement" EE toolkit. For one-off advice, the installed skill toolkit may be used without modifying the target repo.

## Clarify And Breakdown

Use EE commands as workflow templates, not literal slash commands unless the host tool supports them.

- For vague ideas, read `commands/clarify.md` and use its phases to turn the idea into a scoped work item.
- For large work, read `commands/breakdown.md` and use it to decompose into small, testable tasks.
- For new rule creation, read `prompts/00-rules-template.md` and keep generated rules under 200 lines.

## Applying Rules

When implementing or reviewing work with selected EE rules:

1. State which rules were selected and why.
2. Apply the rules as constraints during planning, coding, testing, and review.
3. If a rule conflicts with project-local instructions, prefer project-local instructions and call out the conflict.
4. Keep summaries short: mention the rule impact, not a full restatement of the rule.
