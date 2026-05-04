# SRE vocabulary used in change-control

## Contents
- Golden signals (SRE book ch. 6)
- SLI / SLO (ch. 4)
- Error budget (ch. 3)
- Blast radius (ch. 12, cascading failures)
- Canary analysis (ch. 27)
- Post-deploy validation (ch. 8, release engineering)
- MTTR (ch. 13)
- Where each term is used in the skills

## Golden signals (SRE book ch. 6)

The four signals every monitored service should expose:

| Signal | Question it answers | Typical indicator |
|--------|---------------------|-------------------|
| Latency | How long do requests take? | p50/p95/p99 of `request_duration_seconds`, slow-tail focus |
| Traffic | How much demand are we under? | requests/second; consumer lag for queues |
| Errors | What fraction of requests fail? | ratio of 5xx (or domain-specific failure) to total |
| Saturation | How full is the system? | CPU, memory, queue depth, connection-pool utilisation |

The skills require at least one indicator per applicable golden signal on each affected service. *Applicable* means: a stateless HTTP service has all four; a cron job has only "errors" and "saturation"; a queue consumer has all four where "latency" is end-to-end-processing-time.

## SLI / SLO (ch. 4)

- **SLI (Service Level Indicator)** — a measurement of one aspect of service behaviour. Strongly preferred form: a ratio (`good_events / total_events`).
- **SLO (Service Level Objective)** — a target value for an SLI over a window.

The skills use "indicator" as a generic term for both SLI-shaped measurements and ad-hoc one-offs (e.g. an intended-effect indicator that's only meaningful for the duration of this rollout). Where the user already has an SLO defined, reference it; don't redefine it.

## Error budget (ch. 3)

The inverse of an SLO. If your availability SLO is 99.9% over a month, your error budget is 0.1% × month — the amount of badness you can tolerate before the SLO is breached.

The risk-tier rubric uses error budget as the implicit unit:
- Low-risk changes are not expected to spend budget.
- Medium-risk changes may spend budget; we watch closely for the first few hours.
- High-risk changes can spend a lot of budget if they go wrong; we extend the watch window to +72h to catch slow burns.

## Blast radius (ch. 12, cascading failures)

The set of services / paths / data / user populations a change *could* affect, directly or by knock-on. The plan-side skill enumerates blast radius from the diff — services touched, dependencies invoked, data writes performed, infrastructure altered. Indicators are picked across the blast radius, not just on the service that owns the change.

## Canary analysis (ch. 27)

The practice of comparing production behaviour after a deploy against a baseline (the same metrics on the same time-of-day in the recent past, or on a still-running un-deployed peer). The execute-side skill applies a verbatim canary discipline at every checkpoint: the four-check evidence-discipline gate is the canary-vs-baseline test.

## Post-deploy validation (ch. 8, release engineering)

The window during which the team is paying attention after a release. Sized by risk tier:

| Tier | Window | Checkpoints |
|------|--------|-------------|
| Low | 30 min | +10m, +30m |
| Medium | 2 h | +10m, +30m, +1h, +2h |
| High | 72 h | +10m, +30m, +1h, +2h, +24h, +72h |

Dense early, sparse late. Acute regressions show up in minutes; slow drift (cache churn, cron-driven failures, consumer backlogs) takes hours.

## MTTR (ch. 13)

Mean Time To Recovery. The plan requires a one-line **Rollback** hint precisely because MTTR is the dominant lever in incident impact: a fast known rollback beats a slow unknown one every time. The executor reproduces the hint verbatim in any `ISSUE_DETECTED` report so on-call doesn't have to invent it under pressure.

## Where each term is used in the skills

| Term | Skill | Section |
|------|-------|---------|
| Golden signals | `plan-change-control` | step 6 (indicator picker) |
| SLI | `plan-change-control` | step 6 (`kind: ratio` preference) |
| SLO | `plan-change-control` | step 7 (threshold language references the team's SLO if one exists) |
| Error budget | `plan-change-control` | tier rubric (implicit) |
| Blast radius | `plan-change-control` | step 1 (diff analysis), step 6 (cross-blast-radius indicators) |
| Canary analysis | `execute-change-control` | evidence-discipline gate |
| Post-deploy validation | both skills | the entire workflow |
| MTTR | `plan-change-control` step 9; `execute-change-control` `ISSUE_DETECTED` block | rollback hint |
