---
name: ee-breakdown
description: Use the Equal Experts breakdown workflow to split large work items, epics, features, migrations, or risky tasks into small manageable pieces with dependencies and acceptance criteria. Use when the user says ee-breakdown, EE breakdown, break this down with EE, or asks to prepare work for Ralph iterations.
---

# EE Breakdown

Use this before Ralph when a work item is too broad for one implementation iteration.

## Decomposition Strategies

Choose the strategy that best fits the work:

- Vertical slicing: user-value slices across UI, API, data, and tests.
- Horizontal slicing: technical layers for infrastructure or refactoring.
- Risk-based: spike first, then implementation after unknowns are reduced.
- Dependency-based: independent vs sequential work.
- Scope-based: MVP, enhancement, polish.
- Acceptance-criteria based: one item per major criterion.

## Workflow

1. Understand the original work item and acceptance criteria.
2. Identify why it is too large or risky.
3. Pick a decomposition strategy and state why.
4. Produce small items with title, type, priority, dependencies, description, and acceptance criteria.
5. Show the suggested work order and parallel opportunities.
6. If Ralph will be used, make items small enough for one Ralph build iteration.

## Output

```md
# Breakdown: <Original Work Item>

## Strategy

## Work Items

### Item 1: <Title>

**Type:** <type>
**Priority:** <P0-P4>
**Depends on:** <None|items>

**Description:**

**Acceptance Criteria:**
- [ ] ...

## Dependency Structure

## Suggested Ralph Specs
```

Do not over-decompose simple work. Each item should be independently understandable, testable, and valuable.
