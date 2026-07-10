---
name: decision-record
description: Create, update, or supersede an Architecture Decision Record that preserves context, options, rationale, consequences, and follow-up work using the repository's own conventions. Use when asked to write an ADR, record a durable technical decision, document an architecture trade-off, or replace an obsolete decision.
---

# Decision Record

Capture the decision that was made without inventing consensus or rewriting history.

## Workflow

1. Read repository instructions and locate existing ADR directories, indexes, templates, numbering, filenames, statuses, dates, and cross-link conventions.
2. Search existing records and architecture documentation for the same decision. Update a draft or supersede an accepted record when appropriate instead of creating a duplicate.
3. Confirm the decision, current status, scope, constraints, decision drivers, credible alternatives, and evidence. Label unresolved points rather than filling them with assumptions.
4. Follow the local template. When none exists, use a compact Markdown structure containing:
   - title, date, and status
   - context and decision drivers
   - options considered
   - decision and rationale
   - positive and negative consequences
   - follow-up work and related records
5. Keep implementation detail only when it explains the choice or its consequences. Link to stable repository evidence instead of copying large source passages.
6. Preserve accepted history. Create a new record that explicitly supersedes the old one when the decision changes materially.
7. Update an ADR index or reciprocal links when the repository convention requires it.

## Boundaries

- Use ADRs for consequential choices that future maintainers may otherwise reopen without context.
- Do not create an ADR for routine implementation detail, temporary investigation notes, or a decision that has not been made.
- Do not implement the decision unless the user separately requests implementation.

## Report

State the created or updated record, its status, the decision captured, any superseded record, unresolved assumptions, and required follow-up work.
