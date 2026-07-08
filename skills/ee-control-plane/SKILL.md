---
name: ee-control-plane
description: Use the Equal Experts control-plane workflow to bootstrap architecture, conventions, ADRs, and project context for a new or existing project. Use when the user says ee-control-plane, control plane, bootstrap architecture docs, set up project context, or wants a reusable LLM-assisted development foundation before implementation.
---

# EE Control Plane

Use this for project setup and architecture alignment, not for normal feature implementation. For day-to-day implementation loops, use `$ralph`.

## When To Use

- Greenfield project setup.
- Multi-repo or multi-package system setup.
- Existing project needs architecture and convention docs.
- Team wants a shared project context before using Ralph or other coding agents.

## Workflow

1. Ask about the project: purpose, users, current state, scale, tech preferences, and constraints.
2. Work through architecture decisions: boundaries, deployment model, tech stack, project structure, testing, logging, and error handling.
3. Produce control-plane documents:
   - `AGENTS.md`
   - `docs/conventions.md`
   - `docs/architecture/L1-system-context.md`
   - `docs/architecture/L2-containers.md`
   - `docs/adr/ADR-001-<decision>.md`
   - `Makefile` or equivalent orchestration file when helpful
4. Keep documents concise enough to remain useful context.
5. Recommend the first implementation spec or Ralph workflow after the control plane is ready.

If the Equal Experts toolkit is installed in the project at `prompts/library`, reference relevant rule files by path instead of copying their contents.
