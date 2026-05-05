# Loki (telemetry source — Grafana stack: logs)

## Detection

Loki is the Grafana stack's log store. Detect via:
- MCP tools matching `Grafana:*` or `Loki:*` (e.g. `Grafana:query_logs`).
- The `LOKI_URL` env var set to a queryable endpoint.
- A reachable Grafana datasource of type `loki`.

`probe_telemetry_tools.sh` checks `LOKI_URL` reachability via `${LOKI_URL%/}/ready`. A successful response (200/401/403) marks Loki as available.

## Indicator query patterns

Loki's query language is LogQL — `{label-selectors} |= filter | parse | aggregate`.

### Error rate (golden signal: errors)

```
kind: ratio
source: Loki:query
numerator-query: |
  sum(rate({service="my-svc", level="error"}[5m])) by (env)
denominator-query: |
  sum(rate({service="my-svc"}[5m])) by (env)
```

LogQL gives ratio queries directly; the executor runs both numerator + denominator and divides.

### Log-volume traffic (proxy when no metrics exist)

```
kind: gauge
source: Loki:query
query: |
  sum(rate({service="my-svc"}[5m])) by (env)
```

### Specific error-pattern frequency (intended effect)

When the change is supposed to *eliminate* a specific log error:

```
kind: gauge
source: Loki:query
query: |
  sum(rate({service="my-svc"} |= "TimeoutException"[5m])) by (env)
direction: intended-down
```

### JSON-payload extraction (custom indicators)

LogQL can parse JSON payloads inline:

```
kind: ratio
source: Loki:query
numerator-query: |
  sum(rate({service="my-svc"} | json | request_success="false"[5m])) by (env)
denominator-query: |
  sum(rate({service="my-svc"} | json | request_success!=""[5m])) by (env)
```

## Querying the 24-hour baseline

LogQL `query_range` accepts `start`/`end`/`step`. Use `start=24h ago`, `end=now`, `step=5m`. Average the resulting series for the baseline value, per env.

```
indicator: error-log-rate-my-svc
baseline:
  staging: 12 events/min  (avg over last 24h, queried 2026-05-04T15:00Z, Loki)
  prod:    0.6 events/min (avg over last 24h, queried 2026-05-04T15:00Z, Loki)
```

## MCP tool reference

Use `Loki:` or `Grafana:` prefix for MCP-served queries. The MCP tool routes through whatever upstream the team uses (self-hosted Loki, Grafana Cloud Logs, etc.).

## Common pitfalls

- **Cardinality on labels matters.** Don't add high-cardinality labels (`request_id`, `user_id`) to the selector. Stick to `service`, `level`, `env` — known low-cardinality.
- **`|= "text"` is case-sensitive.** Use `|~ "(?i)pattern"` for case-insensitive regex match.
- **JSON parsing is per-line.** If logs aren't structured JSON, use `pattern` or `regexp` parsers — but those are slower. Prefer structured logging upstream.
- **Loki retention.** Hot tier often 7–30 days, cold tier longer but slower. The 24h baseline window is usually well within hot tier.
- **Rate window match.** `[5m]` matches the typical SLI rate window the executor uses for thresholds. Mixing windows produces inconsistent baselines.
