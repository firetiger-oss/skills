# Multi-environment execution

## Contents
- The multiplex shape
- GROUP BY environment per source
- Per-env-only indicators
- Aggregation rules across envs
- First-issue-wins handoff
- Worked example: staging + prod, regression in staging only

## The multiplex shape

Rather than running each indicator query N times (once per env), the executor runs **one** query per indicator and groups by environment in the source query language. This:
- Makes telemetry costs roughly O(checkpoints × indicators), not O(checkpoints × indicators × envs).
- Returns all envs' values atomically (no skew between per-env queries running at slightly different times).
- Is how the closed-source product's `agent/src/firetiger/agent/plan_executor_agent.py` operates against Firetiger's own metrics tables.

## GROUP BY environment per source

| Source | Syntax |
|--------|--------|
| Datadog | `query: "...{...} by {env}"` |
| Honeycomb | `breakdowns: [env]` in the query body |
| Axiom | `summarize ... by env` (APL) |
| Prometheus | `... by (env)` |
| CloudWatch | `Dimensions: [{Environment: ...}]` per env, OR Metric Insights `GROUP BY Environment` |

If the source doesn't support grouping (e.g. a per-env CloudWatch dimension that's structurally distinct), fall back to N per-env queries — but that's the exception, not the default.

## Per-env-only indicators

Some indicators only make sense for a specific env: a region's replica lag, a specific tenant's quota usage, a feature flag's exposure-fraction. The plan marks these `scope: per-env: <env-name>`. The executor runs them only against that env, regardless of how many envs are in the plan.

## Aggregation rules across envs

At each checkpoint, after per-env per-indicator verdicts are computed:

```
for each env:
    env.checkpoint_verdict = aggregate(env.indicator_verdicts)
        - any indicator regressed (post evidence gate) ⇒ env regressed
        - any intended-effect indicator newly confirmed ⇒ flag intended_effect_confirmed = true
        - all clean ⇒ env unchanged

plan.checkpoint_verdict =
    any env regressed ⇒ ISSUE_DETECTED (first-such env wins)
    all envs reached final checkpoint clean ⇒ COMPLETED
    otherwise ⇒ CHECK_COMPLETE
```

The "first-such env wins" tie-breaker doesn't matter much in practice — the executor surfaces all per-env regressions in the report, and the plan-mode handoff seed names whichever fired first along with the others. But it does mean the user fixes one regression at a time.

## First-issue-wins handoff

When the aggregate verdict is `ISSUE_DETECTED`:

1. Emit the `ISSUE_DETECTED` status block (see [`status-report-formats.md`](status-report-formats.md)) — includes per-env regression details, the rollback hint, and a list of any other envs that also showed regression but are deferred.
2. Render the seed plan from [`plan-mode-handoff.md`](plan-mode-handoff.md). The seed includes:
   - The regressed env name.
   - The failing indicators with their pre/post values and evidence summary.
   - The rollback hint copied verbatim from the plan.
   - One or two candidate fix directions if the diff suggests them.
3. Call `EnterPlanMode` with the seed.
4. Stop monitoring across all envs. Other envs that also showed `regressed` are listed as "deferred — re-run /execute-change-control after the current fix lands to resume monitoring on those envs."

The session is now in plan mode focused on the fix. The executor does not get to run again until the user explicitly re-invokes it.

## Worked example: staging + prod, regression in staging only

Plan:
```
Environments: staging, prod
Tier: medium
Schedule: +10m, +30m, +1h, +2h
Indicators (shared):
  - error-rate-svc-X (ratio, threshold > 5× baseline 5m)
  - latency-p99-svc-X (gauge, threshold > +200ms 5m)
  - cache-hit-ratio (ratio, intended-up, threshold < 90% of baseline)
Rollback: revert PR #1234 via deploy.yml; keep flag off.
```

Timeline:
```
T = 0      staging deploys
T = +2m    prod deploys (matrix-style fan-out)
T = +10m   first checkpoint
           - staging:  error-rate 1.2% (baseline 0.18%, threshold 0.9% — regressed?)
                       Same-time-of-day prior: 0.16%, 0.20% (not in range).
                       Variance: baseline 0.10–0.32% (insufficient to explain 1.2%).
                       Analytical reason: "Post-deploy error spike not seen on
                         prior days; cache-hit-ratio also dropped to 22% from 78%."
                       ⇒ regressed.
           - prod:     error-rate 0.10% (baseline 0.08%, well under threshold).
                       latency-p99 245ms (baseline 220ms, well under +200ms).
                       cache-hit-ratio 80% (baseline 84%, within variance).
                       ⇒ unchanged.
           Aggregate: ISSUE_DETECTED (staging).
T = +12m   ISSUE_DETECTED block emitted; EnterPlanMode called with seed:
             "Staging regressed: error rate 1.2% vs baseline 0.18%; cache hit ratio
              dropped from 78% to 22%. Likely cause: the new caching layer is
              writing to but not reading from the cache. Suggested fix directions:
              (a) inspect the cache-key-derivation function, (b) check the bypass-
              flag wiring. Rollback hint: revert PR #1234 via deploy.yml; keep
              flag off. Prod is unchanged but monitoring is paused; re-run
              /execute-change-control after the fix lands."
T = +12m   Session pivots to plan mode, building the fix.
```

After the fix lands and the user re-invokes `/execute-change-control` against the same plan, the executor starts polling for the new deploy_time and runs the schedule from there.
