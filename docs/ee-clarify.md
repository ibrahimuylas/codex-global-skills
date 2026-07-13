# EE Clarify

Use `ee-clarify` before Ralph when an idea is too vague to become a reliable spec.

## Good Prompts

```text
Use ee-clarify to refine this idea: users should be able to preview invoices before sending them.
```

```text
Use ee-clarify before Ralph. I want to improve the checkout flow but I am not sure what the scope should be.
```

## What It Produces

- work type
- priority
- risk level
- problem/opportunity
- proposed solution
- scope
- acceptance criteria
- out of scope
- open questions
- next step

The skill uses the project's own priority labels and meanings when available. Otherwise it uses:

- `P0`: active critical incident or operational blocker; act immediately
- `P1`: high-impact or time-critical work; do next
- `P2`: normal planned work and the default when urgency is not evidenced
- `P3`: lower-impact improvement; schedule when capacity allows
- `P4`: parking-lot idea with no current commitment

## How It Fits With Ralph

After clarification, use Ralph to turn the clarified item into a spec:

```text
Use ralph to create a spec from the clarified work item.
```

Ralph is installed by a separate pack; compose the `equal-experts` and `ralph` packs when this handoff is required.
