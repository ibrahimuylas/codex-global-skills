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
5. Use the project's documented priority semantics. If none exist, use `P0` for an active critical incident or operational blocker, `P1` for high-impact or time-critical work to do next, `P2` for normal planned work by default, `P3` for lower-impact work, and `P4` for the parking lot.
6. Map every original requirement, acceptance criterion, risk, and dependency to at least one output item. Identify intentional exclusions and remove accidental gaps or duplicate ownership.
7. Show the suggested work order and parallel opportunities.
8. If Ralph will be used, make items small enough for one Ralph build iteration.

## Output

```md
# Breakdown: <Original Work Item>

## Strategy

## Work Items

### Item 1: <Title>

**Type:** <type>
**Priority:** <project value or P0-P4 fallback>
**Depends on:** <None|items>

**Description:**

**Acceptance Criteria:**
- [ ] ...

## Dependency Structure

## Coverage Check

## Suggested Ralph Specs
```

Do not over-decompose simple work. Each item should be independently understandable, testable, and valuable. Do not silently drop or change source scope.
