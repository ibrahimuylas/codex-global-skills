---
name: ee-clarify
description: Use the Equal Experts clarify workflow to turn vague ideas, feature requests, bugs, improvements, spikes, or tasks into clear scoped work items with acceptance criteria. Use when the user says ee-clarify, EE clarify, clarify this idea with EE, or asks to refine rough requirements before Ralph planning.
---

# EE Clarify

Use this before Ralph when the user's idea is not yet specific enough to become a stable spec.

## Workflow

1. Understand the idea: problem, beneficiaries, trigger, and success.
2. Classify the work: feature, bug, improvement, spike, task, or epic.
3. Define scope: in scope, out of scope, MVP, and nice-to-haves.
4. Define success: 3-7 concrete, testable acceptance criteria.
5. Assess risk: unknowns, dependencies, complexity, and suggested approach.
6. Set priority: P0-P4 with a short rationale.
7. Produce a work item.

Ask focused questions only when the answer is necessary. If enough information is present, produce the work item directly and put uncertainties in `Open Questions`.

## Output

Use this structure:

```md
# <Specific action-oriented title>

**Type:** <Feature|Bug|Improvement|Spike|Task|Epic>
**Priority:** <P0-P4>
**Risk:** <Low|Medium|High>

## Problem / Opportunity

## Proposed Solution

## Scope

## Acceptance Criteria

## Out of Scope

## Open Questions

## Suggested Next Step
```

If the user plans to use Ralph, suggest turning the clarified work item into a `specs/NNN-name.md` file with `$ralph`.
