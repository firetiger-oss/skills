# Honeycomb (telemetry source)

## Detection

Honeycomb is **priority-2** after Datadog. Detect via:
- MCP tools matching `Honeycomb:*` (e.g. `Honeycomb:query`, `Honeycomb:list_datasets`).
- The `hccli` or `honeycomb` CLI on `$PATH`.
- `HONEYCOMB_API_KEY` + `HONEYCOMB_DATASET` env vars.

## Indicator query patterns

Honeycomb queries are JSON over an HTTP API; the MCP tool wraps the same shape.

### Error ratio (golden signal: errors)

```
kind: ratio
source: Honeycomb:query
dataset: my-svc
query:
  calculations:
    - { op: COUNT_WHERE, column: error, value: true }
    - { op: COUNT }
  breakdowns: [env]
  time_range: 86400  # 24h
```

The MCP returns the two columns; the plan/executor divides them per env.

### Latency p99

```
kind: gauge
source: Honeycomb:query
dataset: my-svc
query:
  calculations:
    - { op: P99, column: duration_ms }
  breakdowns: [env]
  time_range: 86400
```

### Traffic

```
kind: gauge
source: Honeycomb:query
dataset: my-svc
query:
  calculations:
    - { op: COUNT }
  breakdowns: [env]
  time_range: 86400
```

### Custom-attribute indicator (intended effect)

```
kind: ratio
source: Honeycomb:query
dataset: my-svc
query:
  filters:
    - { column: cache.hit, op: exists }
  calculations:
    - { op: COUNT_WHERE, column: cache.hit, value: true }
    - { op: COUNT }
  breakdowns: [env]
  time_range: 86400
```

## Querying the 24-hour baseline

Set `time_range: 86400` (seconds) on each query; the MCP returns the aggregate value for that window. Capture per-env in the plan baseline block.

## MCP tool reference

Use the `Honeycomb:` prefix consistently. If the team uses Honeycomb Pro / Classic / EU instances, the MCP tool name is the same; the dataset and API endpoint differ in config.

## Common pitfalls

- **`BREAKDOWN: env` requires the column to be on the events.** If trace events don't carry env, add a derived column or use a Honeycomb Trigger condition that matches on the upstream attribute.
- **High-cardinality breakdowns are slow.** Don't break down by `request_id`; break down by `env` or `service` only.
- **Honeycomb's `time_range` is in seconds, not minutes.** 86400 = 24h.
