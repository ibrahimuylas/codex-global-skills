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
- Human documentation lives in `README.md` and `docs/`; keep `SKILL.md` concise.
- External reusable toolkits should be git submodules under `vendor/`.
- Do not copy large third-party rule sets into skill bodies.
