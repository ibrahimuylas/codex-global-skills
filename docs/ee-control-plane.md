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

- `AGENTS.md`
- `docs/conventions.md`
- `docs/architecture/L1-system-context.md`
- `docs/architecture/L2-containers.md`
- `docs/adr/ADR-001-<decision>.md`
- `Makefile` or equivalent orchestration when useful

## When To Use

Use this at the beginning of a project, for multi-repo systems, or when a codebase lacks shared architecture documentation.

For day-to-day development, use `ralph`.

After the control plane exists, use `decision-record` for individual architecture decisions instead of rerunning the bootstrap workflow.
