# Checkpoint schedule

Tier → schedule, applied verbatim:

| Tier | Schedule (offsets from each environment's `deploy_time`) |
|------|----------------------------------------------------------|
| Low | `+10m, +30m` |
| Medium | `+10m, +30m, +1h, +2h` |
| High | `+10m, +30m, +1h, +2h, +24h, +72h` |

The shape (dense early, sparse late) is calibrated to the bimodal failure distribution of real production deploys: regressions either show up acutely in the first few minutes, or they're slow-burn issues that take hours to surface (cache churn, cron-driven failures, consumer backlog buildup, retry storm escalation).

## Why these offsets

| Offset | What it catches |
|--------|-----------------|
| +10m | Immediate error spikes, container crashloops, syntax errors that escaped CI. |
| +30m | Rapid-validation phase. Initial traffic ramp has settled. Latency regressions visible. |
| +1h | Late-early phase. First batch jobs / scheduled tasks have run. |
| +2h | Cache churn effects, downstream consumer lag accumulation. |
| +24h | Full daily-cycle covered. Catches issues that only surface at peak hours, in nightly batch jobs, or in cron-driven workloads. |
| +72h | Slow-drift confirmation. Memory leaks, slowly-failing background tasks, weekly-pattern issues. |

## Per-environment timing

Each environment's checkpoint clock starts when *that environment* sees the deploy. If staging deploys at T=0 and prod deploys at T=2h, staging checkpoints fire at T+10m, T+30m, T+1h, T+2h, etc., while prod checkpoints fire at T+2h+10m, T+2h+30m, etc. The executor handles this — the plan only needs to specify the tier.

## Customisation

The plan may override the default schedule when the user has a clear reason:
- *"This change is behind a feature flag we'll flip in stages over a week — extend the schedule with checkpoints at the flag-flip times."*
- *"This is a hotfix, skip +24h and +72h."*

Do not customise without a reason. The defaults are calibrated; ad-hoc tweaks are usually worse.

## Plan-mode override syntax

In the plan section, render the schedule as:

```
### Checkpoints
+10m, +30m, +1h, +2h, +24h, +72h
```

If overridden, add a one-line reason:

```
### Checkpoints
+10m, +30m, +1h, +2h
(Override: hotfix; skipping +24h and +72h because rollback is < 5 min via flag flip.)
```
