# Repository Map

Use `repo-map` to understand an unfamiliar repository before planning or editing it. The exploration is read-only and evidence-backed.

## Good Prompts

```text
Use $repo-map to explain the workspaces, entry points, and developer commands.
```

```text
Use $repo-map to trace an HTTP request from the router to persistence and show where authentication changes belong.
```

## What It Maps

- applications, packages, ownership, and generated or vendored boundaries
- runtime, CLI, worker, migration, and test entry points
- important call, event, route, schema, queue, and integration flows
- setup, development, test, build, lint, and release commands derived from authoritative files
- likely change locations and their relevant tests

The report distinguishes confirmed facts from inferences and unresolved questions. It links to a small set of useful files instead of dumping the entire directory tree.

Use the resulting map to guide `$ee-clarify`, `$ee-breakdown`, `$decision-record`, or `$ralph`.
