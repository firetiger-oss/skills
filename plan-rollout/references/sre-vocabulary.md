# SRE vocabulary used in rollout

## Contents
- Golden signals
- SLI / SLO
- Error budget
- Blast radius
- Canary analysis
- Post-deploy validation window
- MTTR
- Where each term is used

Vocabulary anchored on the Google SRE book. Use these terms verbatim in plan content; the user is more likely to recognise them than ad-hoc framing.

## Golden signals (SRE book ch. 6)

The four signals every monitored service should expose:

| Signal | Indicator shape |
|--------|-----------------|
| Latency | p95 / p99 of `request_duration_seconds`; slow-tail focus, not `avg`. |
| Traffic | Requests/second; consumer lag for queues. |
| Errors | Ratio of failed events to total events. |
| Saturation | CPU%, memory%, queue depth, connection-pool utilisation. |

**Rule:** every plan picks at least one indicator per *applicable* golden signal on each affected service. *Applicable* = the signal makes sense for the service shape (a cron job has errors and saturation but no continuous latency or traffic).

## SLI / SLO (ch. 4)

- **SLI** = a measurement, prefer ratio form (`good / total`).
- **SLO** = a target value for an SLI over a window. If the team has one, reference it; do not redefine.

**Rule:** if forced to choose between `kind: ratio` and `kind: gauge`, pick ratio whenever an honest denominator exists. Ratios factor out volume; raw counts do not.

## Error budget (ch. 3)

Inverse of an SLO. 99.9% SLO = 0.1% error budget per window. The risk-tier rubric is the budget-allocation rule: low-risk changes spend none, medium spend a little, high can spend a lot.

## Blast radius (ch. 12, cascading failures)

Set of services / paths / data / users a change *could* affect, directly or transitively.

**Rule:** indicator selection covers blast radius, not just the service that owns the change. A queue producer change watches the consumers; an auth change watches every service that calls auth.

## Canary analysis (ch. 27)

Comparing post-deploy behaviour against a baseline (the same metric on the same time-of-day in the recent past).

**Rule:** the four-check evidence-discipline gate in [`monitor-rollout/references/evidence-discipline.md`](../../monitor-rollout/references/evidence-discipline.md) *is* a canary analysis. Don't reinvent it.

## Post-deploy validation window (ch. 8, release engineering)

The span during which the team is paying attention. Sized by tier:

| Tier | Window | Checkpoints |
|------|--------|-------------|
| Low | 30 min | +10m, +30m |
| Medium | 2 h | +10m, +30m, +1h, +2h |
| High | 72 h | +10m, +30m, +1h, +2h, +24h, +72h |

Dense early, sparse late. Acute regressions surface in minutes; slow-burn ones take hours.

## MTTR (ch. 13)

Mean Time To Recovery. Dominant lever in incident impact.

**Rule:** the plan's `Rollback:` line is required and must be specific (one line, exact command/action). The executor reproduces it verbatim in any `ISSUE_DETECTED` report.

## Where each term is used

| Term | Step / location |
|------|-----------------|
| Golden signals | `plan-rollout` step 6 (indicator picker) |
| SLI | step 6 (`kind: ratio` preference) |
| SLO | step 7 (threshold language references team SLO if present) |
| Error budget | risk rubric (implicit) |
| Blast radius | step 1 (diff analysis), step 6 (cross-blast-radius indicators) |
| Canary analysis | `monitor-rollout` evidence-discipline gate |
| Post-deploy validation | full workflow |
| MTTR | step 9 (rollback hint); `ISSUE_DETECTED` report (verbatim quote) |
