# AGENTS.md

This repository contains portable global Codex skills and their installer.

## Chat Commands

When the user asks to "install global skills", "install these skills", or similar from this repo chat:

1. Run `./install.sh` from the repository root.
2. Report installed skills, installed/updated dependencies, and any manual follow-up.

When the user asks to "update global skills", "update these skills", or similar:

1. Run `./update.sh` from the repository root.
2. Report the update result and any conflicts or pull failures.

When the user asks to "check global skills", "doctor global skills", "verify global skills", or similar:

1. Run `./doctor.sh` from the repository root.
2. Report failures first, then warnings, then the confirmed installed skills.

## Repository Rules

- Keep install/update behavior in shell scripts so new developers can run the same flow outside Codex.
- Global Codex skills live under `skills/<skill-name>/`.
- Every skill must include a concise `SKILL.md` and matching `agents/openai.yaml` metadata.
- Human documentation lives in `README.md` and `docs/`; keep `SKILL.md` concise.
- External reusable toolkits should be git submodules under `vendor/`.
- Do not copy large third-party rule sets into skill bodies.
- Add or update developer-facing examples whenever a skill is added or its invocation changes.
- Keep always-on global Git guidance small, safety-focused, and repository-agnostic. Put repeatable Git procedures in `commit` or `git-workflow`, and leave branch, ticket, merge, signing, and release conventions to project-local guidance.
- Preserve user-authored content outside `<!-- codex-global-skills:git-safety:start -->` and `<!-- codex-global-skills:git-safety:end -->` in `${CODEX_HOME:-$HOME/.codex}/AGENTS.md`. Changes to the managed block or its markers must remain idempotent and backward compatible with an existing global file.
- A request to commit does not imply push, and a request to push does not imply creating a pull request. Document and preserve these authorization boundaries in Git-related skills.
- Run `./validate.sh` for source validation, use the skill-creator validator for new or substantially changed skills, and run `./doctor.sh` after installation.
