# EE Control Plane

Use `ee-control-plane` when a project needs architecture and development context before implementation starts.

## Good Prompts

```text
Use ee-control-plane to bootstrap this new project.
```

```text
Use ee-control-plane to create architecture and convention docs for this existing repo.
```

## Typical Output

The skill follows existing repository paths and naming. In a repository without conventions, likely artifacts include:

- `AGENTS.md`
- `docs/conventions.md`
- `docs/architecture/L1-system-context.md`
- `docs/architecture/L2-containers.md`
- `docs/adr/ADR-NNN-<decision>.md`
- `Makefile` or equivalent orchestration when useful

Each artifact is classified as create, update, or leave unchanged. Existing `AGENTS.md`, architecture documents, and task runners are extended with focused edits rather than replaced. ADRs follow the local sequence and status model; `ADR-001` is used only when no ADR convention exists.

## Repository Safety

Before writing, the skill reads repository instructions, checks the branch and working tree, and inspects existing project, documentation, ADR, and orchestration conventions. Conflicting path ownership or architecture evidence is surfaced instead of overwritten, and undecided architecture choices remain open questions rather than invented consensus.

The final report lists created, updated, and unchanged artifacts, validation performed, open questions, and final working-tree status. The workflow does not stage, commit, or push without separate authorization.

## When To Use

Use this at the beginning of a project, for multi-repo systems, or when a codebase lacks shared architecture documentation.

For day-to-day development, use `ralph` when its separate pack is installed; compose `--pack equal-experts --pack ralph` when both workflows are wanted.

After the control plane exists, use `decision-record` for individual architecture decisions instead of rerunning the bootstrap workflow.
