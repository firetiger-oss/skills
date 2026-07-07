---
name: firetiger-query
description: >
  Use when querying Firetiger telemetry with SQL — finding traces, searching logs,
  inspecting metrics, locating errors or slow requests, computing latency
  percentiles, or aggregating observability data via the Firetiger MCP `query` tool.
  Always use this skill before writing a Firetiger query — it carries the critical
  gotchas (slashed table names must be quoted, duration is computed not stored,
  status codes are integers, attributes are structs not maps) that make queries
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
it with the Firetiger MCP server's **`query`** tool (parameter: `sql`).

## Quick Start

```sql
-- 1. Discover which tables exist
SHOW TABLES;

-- 2. Inspect a table's columns before querying it
DESCRIBE "opentelemetry/traces/checkout-service";

-- 3. Query it — time-filter first; add a LIMIT to bound the result
SELECT trace_id, name, end_time - start_time AS duration, start_time
FROM "opentelemetry/traces/checkout-service"
WHERE start_time >= NOW() - INTERVAL '1 hour'
ORDER BY start_time DESC
LIMIT 100;
```

**Key gotcha:** the `query` tool auto-injects `USE "connections/iceberg-gateway"`, so you reference tables by
their quoted name (`"opentelemetry/traces/checkout-service"`) — you don't prefix a catalog path. There is **no
enforced row cap**, but the tool returns every row as JSON, so always add a `LIMIT` (and explicit columns, not
`SELECT *`) to avoid dumping huge nested rows.

## Table naming

Tables are namespaced by signal type and service name. Names with slashes **must be double-quoted**. The
`{service_name}` layout is the default shard key; a deployment can configure a different one, so always
`SHOW TABLES;` to see the real names.

| Signal | Table |
|--------|-------|
| Traces | `"opentelemetry/traces/{service_name}"` (one row per span) |
| Logs | `"opentelemetry/logs/{service_name}"` |
| Metrics catalog | `"opentelemetry/metrics"` (one row per metric — discover names here) |
| Metric data | `"opentelemetry/metrics/{metric_name}"` (one table per metric; values inline) |

Metrics use a per-metric table with values inline — there is **no** `series` join and no
`opentelemetry_metrics_gauges`/`_series` tables. There is no separate "spans" or "events" table — a span's
`events` and `links` are nested `LIST<STRUCT>` columns inside the traces table.

## Essential facts

| Fact | Detail |
|------|--------|
| **Time columns** | `start_time` (traces), `time` (logs/metrics), all UTC. Filter on these first — tables are day-partitioned on them. Use a `Z`/`+00:00` suffix on literal timestamps. |
| **Duration** | Not stored — compute `end_time - start_time`. For a number, `EXTRACT(EPOCH FROM (end_time - start_time))` gives seconds. |
| **Status codes** | Integers: `0`=UNSET, `1`=OK, `2`=ERROR. Filter errors with `status.code = 2`. |
| **Severity** | `severity_number` integer: TRACE=1-4, DEBUG=5-8, INFO=9-12, WARN=13-16, ERROR=17-20, FATAL=21-24. |
| **Attributes** | STRUCTs, dot-accessed (`attributes.http.route`, `resource.attributes.service.name`) — **not** maps, so no `attributes['key']`. Keys are snake_case-normalized. Inferred to depth 2; level 3+ is a JSON-typed column — extract with DuckDB JSON funcs (e.g. `json_extract_string(attributes.request.context, '$.tenant_id')`). |
| **IDs** | `trace_id` is 16 bytes, `span_id`/`parent_span_id` 8 bytes (BLOB in DuckDB). Match with `x'...'` hex literals: `WHERE trace_id = x'0123...'`. |
| **Sampling** | Traces may carry a nullable `sample_rate` (double). When present, multiply counts by `1 / sample_rate` to estimate true volume. |

## What do you need?

| Task | Reference |
|------|-----------|
| **Full column reference** for traces, logs, and deeply-nested attributes | [references/schema.md](references/schema.md) |
| **Ready-to-run queries** — recent/slow/error spans, latency percentiles, error logs, cross-service traces | [references/query-examples.md](references/query-examples.md) |
| **Metrics** — the metadata catalog, per-metric data tables, gauge/sum/histogram value columns | [references/metrics.md](references/metrics.md) |

## Common Mistakes

| # | Mistake | Fix |
|---|---------|-----|
| 1 | **`SELECT *` / no `LIMIT`** | Telemetry rows are wide (nested structs/lists) and every row is returned as JSON. Select explicit columns and add a `LIMIT`. |
| 2 | **Unquoted table name with slashes** | `"opentelemetry/traces/my-service"` — bare `opentelemetry/traces/...` is a parse error. |
| 3 | **Selecting a `duration` column** | There is none. Use `end_time - start_time`. |
| 4 | **Filtering `status.code = 'ERROR'`** | Status codes are integers — use `status.code = 2`. |
| 5 | **No time filter** | Always constrain `start_time`/`time` first — tables are day-partitioned, so this is what prunes the scan. |
| 6 | **Averaging an INTERVAL** | Wrap in `EXTRACT(EPOCH FROM (end_time - start_time))` to aggregate durations as numbers. |
| 7 | **Guessing service/table names** | Run `SHOW TABLES;` and `DESCRIBE "table"` first — schemas are inferred and vary per service. |
| 8 | **Map syntax on attributes** | Attributes are structs — `attributes.http.route`, not `attributes['http.route']`. |
| 9 | **Reading a level-3+ attribute directly** | Beyond nesting depth 2 it's a JSON-typed column — `json_extract_string(attributes.request.context, '$.key')`. |

## Related

- No data to query? Verify instrumentation with `firetiger-instrument`.
- Diagnosing an incident? `firetiger-investigate` wraps these queries in a tracked workflow.
