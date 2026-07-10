# Debug

Use `debug` when a defect, crash, failing test, performance regression, or intermittent failure needs a confirmed cause.

## Good Prompts

```text
Use $debug to reproduce this failure and identify the root cause. Do not fix it yet.
```

```text
Use $debug to investigate why this test only fails in CI.
```

## Workflow

1. Capture the expected behavior, observed behavior, environment, and smallest known trigger.
2. Reproduce the failure without broadening its impact.
3. Reduce the case and test competing hypotheses with focused evidence.
4. Trace the failing path through relevant code, configuration, data, and history.
5. Confirm the root cause and identify a regression test that would fail before the fix.
6. Report the smallest credible next step.

Diagnosis is the default: the skill does not implement a fix unless the request includes one. When reproduction is impossible, it reports what was verified, what remains uncertain, and the next observation needed rather than presenting a guess as fact.

After a fix, use `$quality-gate` and `$local-review`.
