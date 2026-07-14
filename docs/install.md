# Install, Update, And Doctor

## Install From Codex

Open this repository in Codex and say:

```text
install global skills
```

Codex follows [AGENTS.md](../AGENTS.md) and runs:

```bash
./install.sh --install-dependencies
```

The explicit dependency flag installs missing or mismatched pinned CLIs and synchronizes the managed Ralph checkout. If selected dependencies already match, `./install.sh` alone performs no network installation.

The repository currently ships developer workflows. The installer defaults to the complete `developer` pack on its first run; `all` is a separate future-proof superset so later writer, business-analysis, or athlete packs do not silently enter the developer profile. It reuses the previous managed selection later, or accepts one or more explicit packs:

```bash
./install.sh --list-packs
./install.sh --pack all
./install.sh --pack developer-core
./install.sh --pack developer-core --pack equal-experts
```

Start a new Codex task or restart Codex if newly installed skills are not immediately visible.

## What The Installer Manages

The installer:

- resolves the union of selected pack manifests under `packs/`
- checks dependencies without changing them unless `--install-dependencies` is supplied
- verifies OpenAI Codex CLI `0.144.4` and devcontainer CLI `0.87.0`, and installs missing or mismatched selected versions from exact npm packages only when explicitly requested
- initializes the pinned EE toolkit only when selected and explicitly requested
- synchronizes Ralph source at pinned commit `3c53c0ed8ed549c6aa15d9f364ae474b2b19ac10`, then publishes only its reviewed CLI, Codex global-skill defaults, plan/build prompts, and source container files into managed state; it never runs Ralph's upstream installer against personal `~/.config/ralph` content
- verifies existing skill ownership, content hashes, symlink targets, and executable modes before staging a replacement
- adopts only previously published pre-manifest copies whose content and executable modes both match a recorded historical source; local modifications still fail safely
- applies the selected skill set with rollback, removing an omitted skill only when the previous managed copy is unchanged
- links the EE toolkit into the EE wrapper skills
- installs `installer/guidance/git-safety.md` as a clearly marked managed block in `${CODEX_HOME:-$HOME/.codex}/AGENTS.md`
- records selected packs and their source hashes, dependencies, guidance, skill hashes, the EE target fingerprint when applicable, and a canonical state checksum in `${CODEX_HOME:-$HOME/.codex}/.codex-global-skills/manifest`

State is fail-closed: a missing pack or skill selection, unsupported dependency, duplicate entry, checksum mismatch, pack-union mismatch, or claim for an unknown skill stops before profile mutation. Recorded pack hashes let a valid old manifest remain an ownership baseline when pack definitions evolve, while unchanged pack contracts must exactly match their recorded skill/dependency/guidance union.

A per-profile lock serializes installers, destinations are revalidated immediately before replacement, and the new manifest is staged before skill changes. Failure or interruption before atomic manifest publication restores both skill changes and managed `AGENTS.md` guidance while preserving concurrent edits for review; interruption after publication retains the complete committed selection rather than creating mixed state.

The installer never edits `.zshrc`, `.bashrc`, or another shell profile. Ralph does not need to be on `PATH`: the skill resolves its checksum-verified executable directly from managed state.

Each Ralph source/CLI/config contract has its own `${CODEX_GLOBAL_SKILLS_HOME:-$HOME/.local/share/codex-global-skills}/ralph-runtimes/<runtime-id>/` directory, separate from personal Ralph configuration and older managed pins. The managed runtime includes a checksum-reviewed `global-skill.env` that makes Codex the backend default for this global skill only; raw Ralph can still keep its own default elsewhere. This makes a pin upgrade additive and non-destructive; an interrupted new contract is rolled back without touching the previous runtime. See [Ralph](ralph.md).

## Update

From this repository, ask Codex to `update global skills` or run:

```bash
./update.sh
```

The update script requires a clean branch with a configured upstream, fast-forwards the repository, synchronizes submodule URLs and pinned gitlinks, validates the updated source, reinstalls the previously selected packs with explicit dependency synchronization, and runs the doctor. It stops before pulling when the repository has local changes, is detached, lacks an upstream, or cannot fast-forward.

## Doctor

To verify the installation, ask Codex to `check global skills` or run:

```bash
./doctor.sh
```

The doctor verifies the state checksum and pack contracts, reconstructs the selected union, compares source and installed directory hashes with the recorded state, verifies every EE toolkit link resolves to the exact pinned toolkit, verifies Ralph's source, isolated managed runtime, plan/build prompts, source container contract, and exact CLI versions, detects stale or locally changed copies, and checks only the dependencies relevant to the selected packs. Legacy or repository skills installed outside the managed selection are reported as warnings rather than deleted.
