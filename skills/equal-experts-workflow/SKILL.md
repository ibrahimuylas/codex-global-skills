---
name: equal-experts-workflow
description: Safely install or update the Equal Experts LLM toolkit in a target repository, or locate, select, and apply its rules and templates. Use when the user explicitly asks to install, apply, or update the EE toolkit, use EE rules, select development rules, or reference toolkit resources. Use the focused ee-clarify, ee-breakdown, ee-control-plane, or ralph skill for those workflows.
---

# Equal Experts Workflow

Use the Equal Experts LLM toolkit as a per-repository rule library. First install/apply the toolkit into the target repo when requested; then load only the rules or templates needed for the current task.

## Global Skill And Toolkit Roles

Keep this skill and the focused `ee-*` workflow skills as thin global wrappers. The toolkit submodule contains rules, prompts, commands, and templates, but it is not itself a discoverable Codex skill.

- Use global skills for invocation, workflow, rule selection, and safety boundaries across repositories.
- Use the shared toolkit link for one-off advice without changing a target repository.
- Use a project-local `prompts/library` submodule when rules must be versioned and shared with that project.
- Do not copy toolkit rule bodies into skills or create one global skill per rule.

## Repository Preflight

Before changing a target repository:

1. Read repository instructions and inspect the current branch, `git status`, staged and unstaged diffs, `.gitmodules`, `prompts/`, and any existing `prompts/library` entry. Stop before `git submodule add` if `.gitmodules` already has staged or unstaged changes because Git would stage unrelated same-file edits.
2. Confirm the target is a Git repository and classify the request as read-only rule selection, initial installation, pinned initialization, or upstream update. Never mutate the repository for read-only selection.
3. Identify existing path ownership, submodule registration, origin URL, current commit, local changes, and project pinning policy. Capture remote URLs without printing them, compare the complete value privately, and redact embedded credentials from every report. Preserve unrelated and user-authored changes; never stash, clean, reset, or overwrite them.
4. Stop for direction if the path, `.gitmodules`, or index contains a conflicting entry, or if the existing checkout is not the expected Equal Experts toolkit.

## Apply Toolkit To A Repo

When the user says "apply ee toolkit", "implement ee toolkit", or asks to add EE rules/templates to the current project:

1. Work in the current project directory unless the user names another path.
2. If a valid registered EE submodule already exists, leave it unchanged unless the user explicitly asks to initialize or update it.
3. If the path and `.gitmodules` entry are both absent, explain that `git submodule add` stages `.gitmodules` and the gitlink, then add the toolkit:

```bash
mkdir -p prompts
git submodule add https://github.com/EqualExperts/llm-toolkit.git prompts/library
git submodule update --init --recursive -- prompts/library
```

4. Inspect `git diff --cached -- .gitmodules prompts/library` and `git status` immediately. Do not stage any other path, commit, or push without separate authorization.
5. Summarize the installed locations and suggest project guidance updates, such as referencing `prompts/library/rules/` from `AGENTS.md`.

If `prompts/library` exists but is not an EE toolkit checkout, stop and ask how to proceed rather than overwriting it.

## Initialize Or Update Toolkit

- Run `git submodule update --init --recursive -- prompts/library` only to materialize the clean commit already pinned by the parent repository. Never initialize or update other submodules as a side effect.
- Update beyond the pinned commit only when the user explicitly asks. Require a clean submodule, verify the expected origin, resolve the intended branch or commit from project policy or user direction, fetch it, and move only by fast-forward. Never reset, force, or silently change the tracked branch.
- Record the before and after submodule commits. Leave an updated gitlink unstaged unless the user asked to stage it.
- Stop when local submodule changes, an unexpected origin, an ambiguous target ref, or conflicting parent-repository changes make the update unsafe.

## Toolkit Locations

Look for the toolkit in this order:

1. Project-local: `prompts/library/`
2. Installed skill symlink: `toolkit/`
3. Shared skills repo: `../../vendor/equalexperts/llm-toolkit/`
4. User-provided path or URL

If the toolkit is missing from the shared skills repository, do not run a relative submodule command from the target project. Resolve the global skills repository root and use its installer:

```bash
cd <codex-global-skills-repo>
./install.sh --pack equal-experts --install-dependencies
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

## Focused Workflow Routing

- Use `$ee-clarify` for a vague idea, `$ee-breakdown` for decomposition, and `$ee-control-plane` for project bootstrap.
- When the separate Ralph pack is installed, use `$ralph` to create or manage specs, plans, and builds. This skill may select rule paths for an `Applicable Rules` section, but it does not manage Ralph artifacts; suggest composing `equal-experts` with `ralph` when that handoff is wanted.
- For new rule creation, read `prompts/00-rules-template.md` and keep generated rules under 200 lines.

## Applying Rules

When implementing or reviewing work with selected EE rules:

1. State which rules were selected and why.
2. Apply the rules as constraints during planning, coding, testing, and review.
3. If a rule conflicts with project-local instructions, prefer project-local instructions and call out the conflict.
4. Keep summaries short: mention the rule impact, not a full restatement of the rule.

## Report

State whether the work was read-only, installed, initialized, or updated; list selected rule paths; report only a credential-redacted toolkit origin and the before/after commit when changed; identify staged and unstaged paths; and call out conflicts or follow-up. Never expose raw remote credentials or imply that an update was published.
