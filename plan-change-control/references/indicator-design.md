# Indicator design

## Contents
- Ratio vs gauge (and why ratio wins by default)
- Required minimum per plan
- Querying the 24-hour baseline
- Expressing thresholds relative to baselines
- Direction (intended-up / intended-down / unintended-watch)
- Per-environment vs shared
- Common pitfalls

## Ratio vs gauge

| Kind | When to use | Example |
|------|-------------|---------|
| `ratio` | Anything that has an honest denominator. Strongly preferred — normalises out volume, traffic seasonality, and weekend dips. | `5xx_count / total_request_count` |
| `gauge` | Single-value measurements with no honest denominator. | p99 latency value, queue depth, replication lag, cache hit ratio (already a ratio) |

If you find yourself reaching for `gauge` because the math is easier, stop. A raw count of failed requests will drop overnight because traffic drops, not because the service got better. The executor's evidence-discipline checks will flag that as a false positive (volume correlation), but it's better to express the indicator correctly in the first place.

The closed-source product Firetiger runs on its own deploys uses `RATIO` for ~90% of indicators. Match that bias.

## Required minimum per plan

For each affected service:

1. **At least one indicator per applicable golden signal**:
   - Latency (`gauge` — p95 or p99 value, or `ratio` of "fast enough" requests).
   - Traffic (`gauge` — requests/sec, or `ratio` if compared to a steady baseline).
   - Errors (`ratio` — failures / total).
   - Saturation (`gauge` — CPU%, memory%, queue depth).
   "Applicable" means the signal makes sense for the service. A cron job has errors and saturation but no continuous latency or traffic.

2. **At least one intended-effect indicator** — what the change is *supposed* to move. Mark `direction: intended-up` or `intended-down`. Examples:
   - Change adds caching → `cache_hit_ratio` should rise.
   - Change reduces a query timeout → `query_timeout_count_ratio` should fall.
   - Change adds a new validation step → `validation_failure_count` may rise (intended-up).

3. **At least one business-outcome indicator** if one exists for the affected surface. Examples:
   - Checkout flow change → `checkout_success_ratio`.
   - Search-ranking change → `clickthrough_ratio`.
   - Pricing-API change → `price_quote_success_ratio`.
   If you can't infer a business indicator from the diff, ask the user (the ambiguity-question template covers this).

## Querying the 24-hour baseline

Run each indicator's query *now* against the last 24 hours and capture the actual value. Examples:

```
indicator: error-rate-checkout
kind: ratio
source: Datadog:query_metrics{
  query: "sum:checkout.errors{service:checkout}.as_count() / sum:checkout.requests{service:checkout}.as_count()",
  from: "now-24h", to: "now"
}
baseline: 0.18%  (queried 2026-05-04T15:21:00Z)
```

Why 24 hours, not "5 minutes pre-deploy": the executor's evidence-discipline gate requires a ≥24h baseline to rule out periodic patterns (peak hours, daily batch jobs, cron schedules). Anything shorter and the four-check gate will reject the indicator at execution time.

If the telemetry tool is unreachable for an indicator at plan-write time, mark `baseline: pending` and note why. The executor will treat it as `INCONCLUSIVE` until a baseline lands.

## Expressing thresholds relative to baselines

| Bad | Good |
|-----|------|
| `> 1% error rate` | `> 5× baseline (baseline 0.18%) sustained 5m` |
| `< 100 req/s` | `< 50% of baseline traffic for ≥10m` |
| `p99 > 500ms` | `p99 > baseline + 200ms sustained 5m` |

Why: the threshold needs to be meaningful relative to *this* service's normal behaviour. A "1% error rate" alarm is fine for a checkout service but constant noise for an email-bounce ingester.

The executor compares post-deploy values against the baseline, not against the absolute threshold value. The threshold expression is what tells it how big a deviation matters.

## Direction

| Direction | Meaning |
|-----------|---------|
| `intended-up` | The change is supposed to make this indicator rise (e.g. cache hit ratio after adding a cache). Falling = unmet intent (don't celebrate). |
| `intended-down` | The change is supposed to make this indicator fall (e.g. error rate after a bugfix). Rising = unmet intent. |
| `unintended-watch` | The change isn't supposed to move this indicator. Any movement (in either direction) is a regression. |

Most golden-signal indicators are `unintended-watch`. The intended-effect indicators are `intended-up` or `intended-down`. Get this right — it changes how the executor interprets a movement.

## Per-environment vs shared

A `shared` indicator has the same query and the same expected behaviour across all environments. A `per-env` indicator differs. Examples:

```
shared:
  - error-rate-checkout (query has `service:checkout` filter; runs in all envs)

per-env:
  - region-us-east-1:
      - replication-lag-us-east  (only meaningful in this region)
  - region-eu-west-1:
      - replication-lag-eu-west
```

The executor multiplexes shared indicators with `GROUP BY environment` (one query, N results). Per-env indicators are run separately against each environment's tag/scope.

Default to `shared` when the indicator is the same metric on the same service — let the telemetry tool's grouping do the work. Promote to `per-env` only when the metric or the threshold genuinely differs.

## Common pitfalls

- **Treating a count as an SLI.** A count is volume-sensitive; convert to a ratio.
- **Picking a baseline window that's too short.** <24h fails the evidence gate.
- **Writing thresholds that are tighter than the existing SLO.** The change-monitoring threshold is breach-of-SLO-imminent, not breach-of-SLO-now. Loose enough to avoid false positives, tight enough to fire before the SLO does.
- **Listing every metric the team has.** Pick the few that *would actually move* if this change went wrong. Generic "monitor everything" defeats the purpose.
- **Skipping the intended-effect indicator.** A change that ships and doesn't move what it was supposed to is a different kind of failure — silent if you don't watch.
