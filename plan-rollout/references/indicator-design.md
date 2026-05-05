# Indicator design

## Contents
- Ratio vs gauge
- Required minimum per plan
- Querying the 24-hour baseline
- Expressing thresholds relative to baselines
- Direction
- Per-environment vs shared
- Common pitfalls

## Ratio vs gauge

| Kind | When | Example |
|------|------|---------|
| `ratio` | Anything with an honest denominator. Default. | `5xx_count / total_request_count` |
| `gauge` | Single-value with no honest denominator. | p99 latency value, queue depth, replication lag |

**Rule:** prefer ratio. Raw counts drop overnight because traffic drops; ratios don't. The closed-source product uses `ratio` for ~90% of indicators.

## Required minimum per plan

For each affected service:

1. **One indicator per applicable golden signal** (latency, traffic, errors, saturation). *Applicable* = the signal makes sense for the service shape.
2. **One intended-effect indicator** — the metric the change is *supposed* to move. Mark `direction: intended-up` or `intended-down`.
3. **One business-outcome indicator** if one exists for the affected surface (checkout success, signup rate, search clickthrough). Ask the user if not obvious.

## Querying the 24-hour baseline

Run each indicator's query *now* against the last 24 hours; capture the value per env. Format:

```
indicator: error-rate-checkout
kind: ratio
source: Datadog:query_metrics
query: 'sum:errors{...}.as_count() / sum:requests{...}.as_count() by {env}'
baseline:
  staging: 0.21%  (queried 2026-05-04T15:00Z, last 24h)
  prod:    0.08%  (queried 2026-05-04T15:00Z, last 24h)
```

**Rule:** baseline window ≥24h. Anything shorter is rejected by the executor's evidence-discipline gate. If the source can't deliver 24h of history, mark `baseline: pending` with the retention limit and let the executor flag it `INCONCLUSIVE`.

## Expressing thresholds relative to baselines

| Bad | Good |
|-----|------|
| `> 1% error rate` | `> 5× baseline (0.18%) sustained 5m` |
| `< 100 req/s` | `< 50% of baseline traffic for ≥10m` |
| `p99 > 500ms` | `p99 > baseline + 200ms sustained 5m` |

**Rule:** the threshold expression names the baseline. The executor compares post-deploy values to the baseline at runtime; absolute thresholds without a baseline reference are rejected.

## Direction

| Direction | Meaning |
|-----------|---------|
| `intended-up` | Change is supposed to make this rise. Falling = unmet intent. |
| `intended-down` | Change is supposed to make this fall. Rising = unmet intent. |
| `unintended-watch` | Change isn't supposed to move this. Any movement = regression. |

Most golden-signal indicators are `unintended-watch`. The intended-effect indicator is `intended-up` or `intended-down`. Setting this wrong inverts the executor's verdict logic; double-check.

## Per-environment vs shared

- `shared` = same query across envs, factored via `GROUP BY environment` at runtime. Default.
- `per-env: <env-name>` = the indicator only applies to that env, or its query/threshold genuinely differ.

**Rule:** default to `shared`. Promote to `per-env` only when the metric or threshold genuinely differs (region-specific replica lag, tenant-specific SLO).

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Picking a count when a ratio exists | Use the ratio. |
| Baseline window <24h | The executor will flag `INCONCLUSIVE`. Use ≥24h. |
| Threshold tighter than the team's SLO | The change-monitor threshold is "breach-of-SLO imminent," not "breach now." Loosen it. |
| Listing every metric the team has | Pick the few that *would actually move* if this change went wrong. |
| Skipping the intended-effect indicator | A change that doesn't move what it's supposed to is silent failure. Required, not optional. |
