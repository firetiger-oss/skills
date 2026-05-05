# Prometheus / Mimir (telemetry source — Grafana stack: metrics)

This file covers both Prometheus and Grafana Mimir. They are wire-compatible at the query API; everything below applies to both. The planner's probe checks `PROMETHEUS_URL` and `MIMIR_URL` env vars equivalently.

## Detection

Prometheus / Mimir / PromQL is part of the Grafana stack tier. Detect via:
- MCP tools matching `Prometheus:*`, `Mimir:*`, or `Grafana:*` with a Prometheus-flavoured datasource.
- The `promtool` CLI on `$PATH`.
- A reachable HTTP endpoint via `PROMETHEUS_URL` or `MIMIR_URL` env var.

## Indicator query patterns

PromQL natively expresses ratios and grouping; this is what makes it natural for SLI work.

### Error ratio

```
kind: ratio
source: Prometheus:query_range
query: |
  sum(rate(http_requests_total{service="my-svc",status=~"5.."}[5m])) by (env)
  /
  sum(rate(http_requests_total{service="my-svc"}[5m])) by (env)
```

### Latency p99

```
kind: gauge
source: Prometheus:query_range
query: |
  histogram_quantile(0.99,
    sum(rate(http_request_duration_seconds_bucket{service="my-svc"}[5m])) by (env, le)
  )
```

### Traffic (RPS)

```
kind: gauge
source: Prometheus:query_range
query: |
  sum(rate(http_requests_total{service="my-svc"}[5m])) by (env)
```

### Saturation (CPU)

```
kind: gauge
source: Prometheus:query_range
query: |
  avg(rate(process_cpu_seconds_total{service="my-svc"}[5m])) by (env)
```

### Queue depth (saturation, intended-down for a worker change)

```
kind: gauge
source: Prometheus:query_range
query: |
  sum(kafka_consumergroup_lag{topic="my-topic"}) by (env, consumergroup)
```

## Querying the 24-hour baseline

Use `query_range` with `start=24h ago` and `end=now`, `step=5m`. Average or take the right percentile of the resulting series for the baseline value, per-env.

```
indicator: error-rate-my-svc
baseline:
  staging: 0.32%  (avg over last 24h, queried 2026-05-04T15:00Z)
  prod:    0.11%  (avg over last 24h, queried 2026-05-04T15:00Z)
```

## MCP tool reference

Use `Prometheus:` prefix. If access is via `Grafana:query_datasource`, prefix with `Grafana:` instead.

## Common pitfalls

- **`rate()` window too short.** `[5m]` is the standard SLI rate window for SLO calculations; matches the executor's threshold-window default.
- **Forgetting `histogram_quantile`'s `by (le)` requirement.** P-quantile queries must group by `le` *before* taking the quantile.
- **Cardinality explosion.** Don't `by (request_id)`. Stick to env, service, status — known low-cardinality labels.
- **Recording rules.** If the team uses recording rules (e.g. `service:http_request_errors:rate5m`), reference those — they're cheaper and pre-aggregated.
