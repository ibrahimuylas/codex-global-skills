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

## How It Fits With Ralph

Ralph works best when tasks are fine-grained. After breakdown, use:

```text
Use ralph to create specs for these work items.
```

or:

```text
Use ralph to plan the first item from this breakdown.
```
