# Skill Packs

Packs are small declarative selections of global skills, supporting resources, and guidance. They let developers install a focused workflow without turning each role or interest into one large persona skill.

## Available Packs

| Pack | Skills | Dependencies |
| --- | --- | --- |
| `all` | Every skill currently shipped; future role skills join it only when they are added | `git`, `codex`, `devcontainer`, `ralph`, `ee-toolkit` |
| `developer` | The complete current developer workflow (currently 14 skills) | `git`, `codex`, `devcontainer`, `ralph`, `ee-toolkit` |
| `developer-core` | The nine developer workflows that do not use Equal Experts or Ralph | `git` |
| `git` | `commit`, `git-workflow` | `git` |
| `equal-experts` | Four EE workflows plus `decision-record` | `git`, `ee-toolkit` |
| `ralph` | Ralph plus verification, review, commit, and publication handoffs | `git`, `codex`, `devcontainer`, `ralph` |

Every pack must request the managed `git-safety` guidance. The validator enforces this invariant, so switching to a future writer, analyst, or athlete pack never leaves guidance ownership ambiguous.

## Selection Semantics

On the first installation, no explicit pack selection uses the `developer` pack. Later no-argument runs reuse the packs recorded in the managed manifest, so an update does not silently expand a focused installation back to the complete developer setup. `all` is intentionally separate: future writer, business-analysis, or athlete skills can join it without polluting the developer profile.

Each repeated pack selection adds to a union. Skills, dependencies, and guidance with the same name are installed once, so these selections request the developer-core and Equal Experts workflows together:

```bash
./install.sh --pack developer-core --pack equal-experts
```

For Ralph with EE requirement shaping and rules, compose the two self-contained packs:

```bash
./install.sh --pack ralph --pack equal-experts
```

Pack selection and dependency installation are separate decisions. The installer checks selected dependencies and exact managed CLI versions by default. Add `--install-dependencies` to install missing or mismatched pinned CLIs, initialize the pinned EE toolkit, and synchronize the managed Ralph checkout:

```bash
./install.sh --pack ralph --install-dependencies
```

An explicit selection does not implicitly include `developer`. For example, selecting only `git` requests only `commit`, `git-workflow`, the Git dependency, and Git safety guidance.

The selected union is the desired state for content managed by this installer. When switching packs, a skill omitted from the new desired state may be removed only when both conditions hold:

1. a previous installation recorded that skill as managed by this toolkit
2. the installed skill is unchanged from the last managed copy

Unmanaged skills and locally modified installed skills are preserved. Managed hashes cover file content, symlink targets, and executable modes. The installer reports a conflict for manual resolution rather than deleting user-owned work. Dependency tools are checked when selected but are not automatically installed without the explicit flag or uninstalled when switching packs. The Ralph pack intentionally includes `devcontainer`: guarded host execution remains possible, while the container flow adds a reduced, workspace-scoped environment with a dedicated sandbox home. It removes upstream Docker-socket, host-network, and host-home mounts, but still has project write access, a backend credential, and outbound network access; it is not an absolute security boundary. Managed Git guidance is mandatory across packs and follows its own bounded-block preservation rules.

The v2 managed manifest is validated fail-closed before it is trusted: it must contain at least one known pack and source or approved legacy skill, every dependency and guidance entry must be allowlisted, and a canonical checksum covers its pack, dependency, guidance, skill, and EE-link records. Each selected pack also records its source hash. When those hashes still match, the recorded skill/dependency/guidance names must exactly equal the pack union. A changed pack hash is treated as a source update: the checksummed old list remains the ownership baseline and the current pack becomes the next desired state. Invalid, inconsistent, or truncated state never falls back to a broader default pack. A per-profile lock serializes installers, destination hashes are checked again immediately before replacement, and the replacement manifest is staged before mutation. Failure or signal before manifest publication restores the prior skills and guidance while preserving concurrent edits; a signal after atomic publication retains the complete new selection.

## Manifest Format

Pack manifests live under `packs/` and use a deliberately small line-oriented format. Blank lines and lines beginning with `#` are ignored. Every other line must be exactly one of:

```text
skill <name>
dependency <name>
guidance git-safety
```

`skill <name>` must reference an existing `skills/<name>/` directory. Dependency names are restricted to:

- `git`
- `codex`
- `devcontainer`
- `ralph`
- `ee-toolkit`

Manifests contain names only. Installation commands, URLs, versions, and platform-specific behavior belong in the installer so parsing stays safe and dependency behavior remains consistent.

## Designing Future Packs

Add a pack when a coherent group of focused skills is useful to install together. Keep the skills action-oriented and independently reusable; do not create one broad role prompt that is always active.

This repository currently ships developer workflows only. A future writer pack might compose separate outlining, drafting, editing, source-checking, and publication-readiness skills. A business-analysis pack might compose problem framing, stakeholder mapping, requirements clarification, process analysis, and acceptance-criteria skills. If “runner” means an endurance athlete, that pack might compose training-block planning, workout review, race preparation, and recovery checks while keeping medical diagnosis outside scope. If it means a task or automation runner, those belong to a distinctly named developer-automation pack.

Only reference these skills after their own `SKILL.md`, metadata, documentation, and validation exist. Shared actions should remain reusable across packs rather than being copied into role-specific variants.
