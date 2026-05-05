# Tempo (telemetry source — Grafana stack: traces)

## Detection

Tempo is part of the Grafana stack and handles distributed tracing. Detect via:
- MCP tools matching `Grafana:*` or `Tempo:*` (e.g. `Grafana:query_traces`).
- The `TEMPO_URL` env var set to a queryable endpoint.
- A reachable Grafana datasource of type `tempo`.

`probe_telemetry_tools.sh` checks `TEMPO_URL` reachability via `${TEMPO_URL%/}/api/echo`. A successful response (200/401/403 — auth-required is still queryable) marks Tempo as available.

## Indicator query patterns

Tempo's query language is TraceQL — search by attributes, durations, status codes, span structure.

### Error rate (golden signal: errors)

```
kind: ratio
source: Tempo:query
query:
  numerator: '{ resource.service.name = "my-svc" && status = error } | count_over_time()'
  denominator: '{ resource.service.name = "my-svc" } | count_over_time()'
breakdowns: [resource.deployment.environment]
```

The `resource.deployment.environment` attribute (OTel semantic conventions) gives the per-env grouping.

### Latency p99 (golden signal: latency)

```
kind: gauge
source: Tempo:query
query:
  '{ resource.service.name = "my-svc" } | quantile_over_time(span:duration, 0.99)'
breakdowns: [resource.deployment.environment]
```

### Traffic (RPS by service)

```
kind: gauge
source: Tempo:query
query:
  '{ resource.service.name = "my-svc" } | rate()'
breakdowns: [resource.deployment.environment]
```

### Span-attribute indicator (intended effect)

When the change adds a new attribute or operation, the intended effect can be measured directly off span attributes:

```
kind: ratio
source: Tempo:query
query:
  numerator: '{ resource.service.name = "my-svc" && cache.hit = true } | count_over_time()'
  denominator: '{ resource.service.name = "my-svc" && span.has(cache.hit) } | count_over_time()'
breakdowns: [resource.deployment.environment]
```

## Querying the 24-hour baseline

TraceQL supports time-range parameters; the planner sets the window to the last 24 hours when capturing baselines. Tempo's `count_over_time` and `quantile_over_time` functions return time-series; aggregate per-env at query time.

```
indicator: error-rate-my-svc
baseline:
  staging: 0.34%  (queried 2026-05-04T15:00Z, last 24h, Tempo)
  prod:    0.11%  (queried 2026-05-04T15:00Z, last 24h, Tempo)
```

## MCP tool reference

Use `Tempo:` or `Grafana:` prefix for MCP-served queries. If the team accesses Tempo via Grafana's datasource API, the prefix is `Grafana:` (the MCP tool routes through Grafana to the underlying Tempo instance).

## Common pitfalls

- **Sample rate matters.** Tempo often samples traces (head-sampling at the SDK or tail-sampling in the collector). Indicators based on trace counts must factor in the sample rate; a change in sampling looks like a regression. The planner should ask the user about sampling if the indicator depends on absolute counts.
- **`status = error`** captures gRPC/HTTP errors set explicitly via OTel API. If your service uses non-standard error markers (custom span events), the query needs to match those.
- **Cardinality of breakdowns.** Don't break down by `trace_id`. Stick to `resource.service.name`, `resource.deployment.environment`, `service.version` — known low-cardinality attributes.
- **Trace retention.** Tempo defaults are often 1–7 days for full traces. Confirm the team's retention covers the 24h baseline window before relying on Tempo for historical comparisons.
