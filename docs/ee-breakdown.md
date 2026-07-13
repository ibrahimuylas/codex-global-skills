# EE Breakdown

Use `ee-breakdown` when a feature, migration, or bug fix is too large for one clean implementation pass.

## Good Prompts

```text
Use ee-breakdown to split this feature into Ralph-sized tasks.
```

```text
Use ee-breakdown on this migration and identify dependencies.
```

## Breakdown Strategies

- vertical slicing
- horizontal slicing
- risk-based spikes
- dependency-based order
- MVP / enhancement / polish
- acceptance-criteria based

The skill preserves project-defined priority semantics. If the project has none, it uses `P0` for an active critical incident or operational blocker, `P1` for high-impact or time-critical work to do next, `P2` for normal planned work by default, `P3` for lower-impact work, and `P4` for the parking lot.

## Coverage Check

After slicing, the skill maps every original requirement, acceptance criterion, risk, and dependency to at least one work item. It identifies intentional exclusions and resolves accidental gaps or duplicate ownership so decomposition does not silently lose or change scope.

## How It Fits With Ralph

Ralph works best when tasks are fine-grained. After breakdown, use:

```text
Use ralph to create specs for these work items.
```

or:

```text
Use ralph to plan the first item from this breakdown.
```

Ralph is installed by a separate pack; compose the `equal-experts` and `ralph` packs when this handoff is part of the workflow.
