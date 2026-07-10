---
name: repo-map
description: Build a read-only, evidence-backed map of an unfamiliar repository, including workspaces, boundaries, entry points, commands, tests, integrations, and important data flows. Use for repository onboarding, architecture orientation, locating where a change belongs, understanding how an application starts, or surveying a codebase before planning work.
---

# Repository Map

Map the repository from source evidence without changing it.

## Workflow

1. Read repository instructions, top-level documentation, manifests, workspace configuration, and ownership files.
2. Inventory tracked and relevant untracked files with fast file-listing and search tools. Exclude generated output, dependency caches, vendored code, and large artifacts unless they define behavior under investigation.
3. Identify languages, package managers, workspaces, applications, libraries, infrastructure, documentation, and generated-code boundaries from their configuration files.
4. Locate runtime, CLI, worker, scheduled-job, migration, and test entry points. Confirm each entry point from scripts, imports, registrations, or deployment configuration.
5. Trace dependencies and requested data flows through actual calls, imports, events, routes, schemas, queues, and external integrations. Label any unverified conclusion as an inference.
6. Derive supported setup, development, test, build, lint, type-check, and release commands from repository scripts, documentation, and CI. Do not execute mutating commands merely to discover them.
7. Inspect representative tests to identify test layers, fixtures, conventions, and gaps relevant to the user's goal.
8. Stop exploring when the map answers the requested scope. Avoid exhaustively listing files or restating the directory tree.

## Report

Present only useful, evidence-backed sections:

1. Summarize the repository's purpose and major boundaries.
2. Map key directories or workspaces to their responsibilities.
3. Identify entry points and trace the important runtime or data flow.
4. List authoritative developer commands and their sources.
5. Explain where common or requested changes belong and which tests cover them.
6. Distinguish confirmed facts, inferences, and unresolved questions.

Link to the most useful local files and line locations when supported. Keep the map concise, and do not create a map artifact unless the user asks for one.
