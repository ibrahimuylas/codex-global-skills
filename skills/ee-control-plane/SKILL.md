---
name: ee-control-plane
description: Bootstrap or repair shared architecture, convention, ADR, and project-context documents for a new or existing repository with the Equal Experts control-plane workflow. Use when the user says ee-control-plane, control plane, bootstrap architecture docs, set up project context, or needs a reusable development foundation before implementation. Do not use for an individual ADR or normal feature work.
---

# EE Control Plane

Bootstrap shared project context. Use `$decision-record` for an individual architecture decision. Hand implementation loops to `$ralph` only when that separately installable pack is available or the user asks to add it.

## Preflight

1. Read repository instructions and inspect the current branch, `git status`, relevant diffs, project structure, build files, and existing architecture, convention, ADR, and orchestration documents.
2. Discover local filenames, ADR numbering and status conventions, documentation structure, and task-runner conventions before proposing paths.
3. Classify each proposed artifact as create, update, or leave unchanged. Preserve user-authored content and make the smallest coherent update. Never replace an existing `AGENTS.md` wholesale.
4. Stop for direction when an existing path has a different owner or purpose, or when repository evidence conflicts with the requested architecture.

## Workflow

1. Establish the project purpose, users, current state, scale, constraints, and unresolved questions from the repository and user context.
2. Work through material decisions: boundaries, deployment model, tech stack, project structure, testing, logging, and error handling. Record unsupported choices as open questions instead of presenting assumptions as accepted decisions.
3. Create or update only the relevant control-plane documents, following local conventions:
   - `AGENTS.md`
   - `docs/conventions.md`
   - `docs/architecture/L1-system-context.md`
   - `docs/architecture/L2-containers.md`
   - `docs/adr/ADR-NNN-<decision>.md`
   - `Makefile` or equivalent orchestration file when helpful
4. Follow the repository's ADR sequence and status model. If none exists, start at `ADR-001`; do not reuse, renumber, or supersede an existing decision unless requested.
5. Extend the existing task runner instead of introducing a competing one. Keep documents concise enough to remain useful context.
6. Validate internal links and any repository-defined documentation checks, then inspect `git status` and the diff again.

If the Equal Experts toolkit is installed in the project at `prompts/library`, reference relevant rule files by path instead of copying their contents.

## Report

List created, updated, and unchanged artifacts; decisions recorded; open questions; validation performed; and final working-tree status. Call out unrelated pre-existing changes. Do not stage, commit, or push unless the user separately authorizes it.
