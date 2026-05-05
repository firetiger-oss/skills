# Datadog (telemetry source)

## Detection

Datadog is the **priority-1** telemetry source. Detect via:
- MCP tools matching `Datadog:*` (typical names: `Datadog:query_metrics`, `Datadog:search_logs`, `Datadog:get_monitor`).
- The `dog` or `datadog-ci` CLI on `$PATH`.
- `DD_API_KEY` + `DD_APP_KEY` env vars set, with optional `DD_SITE` (`datadoghq.com`, `datadoghq.eu`, `us3.datadoghq.com`, etc.).

## Indicator query patterns

### Error ratio (golden signal: errors)

```
kind: ratio
source: Datadog:query_metrics
query: "sum:trace.servlet.request.errors{service:checkout}.as_count() / sum:trace.servlet.request.hits{service:checkout}.as_count() by {env}"
```

For non-trace services, sub in your error-counter metric and your request-counter metric. The `by {env}` is what enables multi-env multiplexing.

### Latency p99 (golden signal: latency)

```
kind: gauge
source: Datadog:query_metrics
query: "p99:trace.servlet.request{service:checkout} by {env}"
```

### Traffic / RPS (golden signal: traffic)

```
kind: gauge
source: Datadog:query_metrics
query: "sum:trace.servlet.request.hits{service:checkout}.as_rate() by {env}"
```

### Saturation (golden signal: saturation)

```
kind: gauge
source: Datadog:query_metrics
query: "avg:system.cpu.user{service:checkout} by {env}"
```

For queue saturation, sub `kafka.consumer_lag` or your queue's depth metric.

### Cache hit ratio (intended-effect, intended-up)

```
kind: ratio
source: Datadog:query_metrics
query: "sum:cache.hit{service:checkout}.as_count() / (sum:cache.hit{service:checkout}.as_count() + sum:cache.miss{service:checkout}.as_count()) by {env}"
```

### Log-derived indicator

When a metric doesn't exist but the signal is in logs:

```
kind: ratio
source: Datadog:search_logs
query: "service:checkout status:error"
denominator-query: "service:checkout"
```

The executor runs both queries and divides. Note: log-based indicators are slower and rate-limited; prefer metrics where both exist.

## Querying the 24-hour baseline

In the plan, capture the actual value at write time:

```
indicator: error-rate-checkout
baseline:
  staging: 0.21%  (queried 2026-05-04T15:00Z, last 24h, Datadog)
  prod:    0.08%  (queried 2026-05-04T15:00Z, last 24h, Datadog)
```

The `Datadog:query_metrics` payload to get this:
```json
{
  "query": "sum:checkout.errors{...}.as_count() / sum:checkout.requests{...}.as_count() by {env}",
  "from": "now-24h",
  "to": "now"
}
```

## MCP tool reference

Always use the fully-qualified `Server:tool_name` form (e.g. `Datadog:query_metrics`), never the legacy `mcp__datadog__query_metrics`. The qualified form disambiguates when multiple MCP servers expose similarly named tools.

## Common pitfalls

- **Forgetting `by {env}`**. Without it, every multi-env plan needs N queries per checkpoint instead of one.
- **Using `.as_count()` on already-counted metrics**. Doubles the value.
- **Tags vs scopes**. Make sure the env tag is on the metric (`environment:prod`, `env:prod`, `deployment_environment:prod` — varies by team). The plan must use the actual tag the team uses.
- **`p99` vs `avg`**. For latency, default to `p99`; `avg` hides slow-tail regressions.
