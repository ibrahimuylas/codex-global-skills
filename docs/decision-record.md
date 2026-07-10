# Decision Record

Use `decision-record` when a significant technical choice should remain understandable after the original discussion is gone.

## Good Prompts

```text
Use $decision-record to capture our choice of an event-driven integration.
```

```text
Use $decision-record to supersede the existing database ADR with the decision from this chat.
```

## What It Captures

- the decision and its status
- context, constraints, and decision drivers
- credible options considered
- rationale and important trade-offs
- positive and negative consequences
- follow-up work and links to related records

The skill first discovers the repository's existing ADR location, template, naming, numbering, and status conventions. It updates or supersedes an existing record when appropriate instead of creating a duplicate. If no convention exists, it proposes a compact Markdown ADR under `docs/adr/`.

Use an ADR for durable, consequential choices—not routine implementation details. Record current evidence and explicitly label unresolved assumptions; do not invent historical consensus.
