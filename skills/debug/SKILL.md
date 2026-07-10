---
name: debug
description: Diagnose reproducible or intermittent software failures by preserving the original signal, isolating variables, confirming the root cause, and identifying a regression test. Use when asked to debug or investigate a crash, failing test, incorrect behavior, performance regression, environment-only failure, or unexplained production-like symptom.
---

# Debug

Confirm the cause before proposing or implementing a fix.

## Workflow

1. Read repository instructions and inspect the current working-tree state before running or changing anything.
2. Define the expected behavior, observed behavior, environment, frequency, first known occurrence, and smallest known trigger.
3. Reproduce the failure with the narrowest safe command or input. Do not experiment against production, shared data, or external systems without explicit authorization.
4. Preserve the original error, stack trace, logs, exit status, timing, and relevant versions. Avoid broad logging or configuration changes that can mask the signal.
5. Reduce the case and test one plausible hypothesis at a time. Compare working and failing inputs, environments, commits, configurations, or execution paths.
6. Trace the failing path through callers, state, configuration, data boundaries, concurrency, and recent history. Distinguish evidence from inference.
7. Confirm the root cause with a focused observation or test that explains both the failure and relevant non-failing cases.
8. Identify a regression test that fails before the fix. Add it and implement the smallest fix only when the user asked for a fix.
9. Re-run the reproduction, targeted tests, and appropriate repository checks after any authorized change.

## Boundaries

- Treat diagnosis as the default when the user asks only to investigate.
- Do not change dependencies, weaken checks, suppress errors, or combine cleanup with a fix.
- Do not claim a root cause when evidence supports only a hypothesis.
- When reproduction is blocked, report what was verified, the remaining uncertainty, and the next observation needed.

## Report

Lead with the confirmed cause or current best-supported finding. Include the reproduction, decisive evidence, affected scope, regression-test recommendation, any implemented change, verification results, and residual risk.
