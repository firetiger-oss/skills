# Change control: overview

## Contents
- What "change control" means here
- Why monitor changes (and not just everything)
- The four golden signals
- SLIs, SLOs, and error budgets
- Blast radius and the intended/unintended-effect frame
- The post-deploy validation window
- MTTR and the rollback hint
- Where to go next

## What "change control" means here

In the [Google SRE book](https://sre.google/sre-book/) sense — the set of practices that lets a team ship code changes to production without lighting their error budget on fire. The bit of change control these skills automate is **post-deploy validation**: after a change hits production, watch the right signals on the right cadence with the right evidence-discipline so a regression is caught early, attributed to the change, and surfaced with enough evidence to act on.

The skills do not cover pre-merge change review, change advisory boards, or release engineering tooling. Those are upstream of the skill's scope.

## Why monitor changes (and not just everything)

Generic alerting (page when error rate > X) catches problems but cannot attribute them to a specific change. Change-scoped monitoring asks a tighter question: *did this specific change move these specific signals in the way this specific change was supposed to move them, and not in any other way?*

Two signals matter:

- **Intended effect** — what the change was supposed to do. If the change adds caching, the intended effect is "cache hit ratio rises." Confirming this is as important as watching for regressions; a change that ships cleanly but doesn't move the metric it was supposed to move is a different kind of failure.
- **Unintended effect (blast radius)** — what the change could plausibly break that no one wanted to touch. The diff scopes this — a database-migration PR has a different blast radius than a frontend tweak.

The plan-side skill enumerates both. The monitor-side skill confirms or refutes both at each checkpoint.

## The four golden signals

From SRE book ch. 6. The minimum baseline for any service-touching change:

| Signal | What it asks |
|--------|--------------|
| Latency | How long requests take (especially the slow tail — p95/p99). |
| Traffic | How much demand the service is seeing. |
| Errors | The rate of failed requests. |
| Saturation | How full the system is (CPU, memory, queue depth, connection pool). |

Every change-monitoring plan picks at least one indicator per applicable golden signal for the affected services. This is the floor, not the ceiling.

## SLIs, SLOs, and error budgets

- **SLI (Service Level Indicator)** — a measurement of one aspect of service behaviour, usually expressed as a ratio: `good_events / total_events`. The skills strongly prefer ratio-form SLIs because they normalise out volume — a request-error count drops overnight because traffic drops, not because the service got better; an error *ratio* doesn't.
- **SLO (Service Level Objective)** — a target for an SLI over a window. Most teams already have SLOs; the skills don't define new ones, they reference what the team already has.
- **Error budget** (SRE book ch. 3) — the inverse of an SLO. If your availability SLO is 99.9%, you have a 0.1% error budget per window. Risky changes burn more of it than safe changes; the risk-tier rubric in `plan-rollout/references/risk-rubric.md` maps that to checkpoint cadence.

## Blast radius and the intended/unintended-effect frame

"Blast radius" (SRE book ch. 12, cascading failures) is the set of services, request paths, data, or user populations that a change *could* affect — directly or by knock-on. Plan-side enumerates this from the diff: services touched, dependencies invoked, data writes performed, infrastructure altered.

Indicators are picked across the blast radius, not just on the service that owns the change. A change to a shared queue can break consumers downstream; the plan covers them.

## The post-deploy validation window

SRE book ch. 8 (release engineering) treats every release as having a validation window: a span of time after the deploy during which the team is paying attention. The skills size this window by risk tier:

| Tier | Checkpoints |
|------|-------------|
| Low (pure-function, doc, flag-gated) | +10m, +30m |
| Medium (API behaviour, dependency bump, partial flag rollout) | +10m, +30m, +1h, +2h |
| High (DB migration, schema change, auth/middleware, infra, hot-path code, anything that can't be hotfixed in <30m) | +10m, +30m, +1h, +2h, +24h, +72h |

Dense early checkpoints catch acute regressions; sparse late ones catch slow drift (cache churn, cron-driven failures, consumer backlogs that take hours to surface). The schedule is a verbatim port of the production system Firetiger runs on its own deploys.

## MTTR and the rollback hint

Mean Time To Recovery (SRE book ch. 13) is the dominant lever in incident impact: a fast, known rollback path beats a slow, unknown one every time. The plan therefore *requires* a one-line rollback hint — the exact thing to do (revert PR, redeploy previous tag, flip flag off) — and the executor reproduces that hint verbatim in any `ISSUE_DETECTED` report.

The hint is not a checklist of options; it's the call-the-shot the planner makes at write-time so the executor doesn't have to invent it under pressure.

## Where to go next

- For the plan/monitor decision tree, read [decision-tree.md](decision-tree.md).
- For known limits of the local skill, read [limitations.md](limitations.md).
- For the methodology applied to a specific change, invoke `plan-rollout` against a diff or PR url.
