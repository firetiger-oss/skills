---
name: firetiger-query
description: >
  Use when querying Firetiger telemetry with SQL — finding traces, searching logs,
  inspecting metrics, locating errors or slow requests, computing latency
  percentiles, or aggregating observability data via the Firetiger MCP `query` tool.
  Always use this skill before writing a Firetiger query — it carries the critical
  gotchas (every SELECT needs LIMIT<200, slashed table names must be quoted,
  duration is computed not stored, status codes are integers) that make queries
  succeed on the first try.
license: Apache-2.0
user_invocable: true
user_invocable_description: "Query traces, logs, and metrics with SQL"
metadata:
  author: firetiger
  version: "1.0.0"
  homepage: https://firetiger.com
  source: https://github.com/firetiger-oss/skills
references:
  - references/schema.md
  - references/query-examples.md
  - references/metrics.md
---

# Firetiger Query

Firetiger stores telemetry in Apache Iceberg tables with dynamic schema inference. Run **DuckDB SQL** against
it with the Firetiger MCP server's **`query`** tool.

## Quick Start

```sql
-- 1. Discover which service tables exist
SHOW TABLES;

-- 2. Inspect a table's columns before querying it
DESCRIBE "opentelemetry/traces/checkout-service";

-- 3. Query it — always time-filter first, always LIMIT < 200
SELECT trace_id, name, end_time - start_time AS duration, start_time
FROM "opentelemetry/traces/checkout-service"
WHERE start_time >= NOW() - INTERVAL '1 hour'
ORDER BY start_time DESC
LIMIT 100;
```

**Key gotcha:** every `SELECT` MUST include `LIMIT < 200`, or the query is rejected.

## Table naming

Tables are namespaced by signal type and service name. Names with slashes **must be double-quoted**.

| Signal | Table |
|--------|-------|
| Traces | `"opentelemetry/traces/{service_name}"` |
| Logs | `"opentelemetry/logs/{service_name}"` |
| Metric series (metadata) | `opentelemetry_metrics_series` |
| Metric data | `opentelemetry_metrics_gauges`, `opentelemetry_metrics_counters_cumulative`, `opentelemetry_metrics_counters_delta`, `opentelemetry_metrics_histograms_cumulative`, … |

Run `SHOW TABLES;` to see the services actually sending data.

## Essential facts

| Fact | Detail |
|------|--------|
| **Time columns** | `start_time` (traces), `time` (logs/metrics). Filter on these first for partition pruning. |
| **Duration** | Not stored — compute `end_time - start_time`. For a numeric value, `EXTRACT(EPOCH FROM (end_time - start_time))` gives seconds. |
| **Status codes** | Integers: `0`=UNSET, `1`=OK, `2`=ERROR. Filter errors with `status.code = 2`. |
| **Severity** | `severity_number` integer: TRACE=1-4, DEBUG=5-8, INFO=9-12, WARN=13-16, ERROR=17-20, FATAL=21-24. |
| **Attributes** | Nested structs, dot-accessed: `attributes.http.route`, `resource.attributes.service.name`. Inferred to depth 2; level 3+ is hex-encoded JSON — `decode()` + `json_extract_string()`. |
| **Trace IDs** | Binary — match with `x'...'` literals: `WHERE trace_id = x'0123...'`. |

## What do you need?

| Task | Reference |
|------|-----------|
| **Full column reference** for traces, logs, and deeply-nested attributes | [references/schema.md](references/schema.md) |
| **Ready-to-run queries** — recent/slow/error spans, latency percentiles, error logs, cross-service traces | [references/query-examples.md](references/query-examples.md) |
| **Metrics** — series join pattern, discovering available metrics, gauge/counter/histogram tables | [references/metrics.md](references/metrics.md) |

## Common Mistakes

| # | Mistake | Fix |
|---|---------|-----|
| 1 | **Omitting `LIMIT`** (or `LIMIT >= 200`) | Every `SELECT` needs `LIMIT < 200`, or it's rejected. |
| 2 | **Unquoted table name with slashes** | `"opentelemetry/traces/my-service"` — bare `opentelemetry/traces/...` is a parse error. |
| 3 | **Selecting a `duration` column** | There is none. Use `end_time - start_time`. |
| 4 | **Filtering `status.code = 'ERROR'`** | Status codes are integers — use `status.code = 2`. |
| 5 | **No time filter** | Always constrain `start_time`/`time` first — full scans are slow and may time out. |
| 6 | **Averaging an INTERVAL** | Wrap in `EXTRACT(EPOCH FROM (end_time - start_time))` to aggregate durations as numbers. |
| 7 | **Guessing service/table names** | Run `SHOW TABLES;` and `DESCRIBE "table"` first — schemas are inferred and vary per service. |
| 8 | **Reading a level-3+ attribute directly** | It's hex-encoded JSON — `json_extract_string(decode(attributes.request.context), '$.key')`. |

## Related

- No data to query? Verify instrumentation with `firetiger-instrument`.
- Diagnosing an incident? `firetiger-investigate` wraps these queries in a tracked workflow.
