---
name: firetiger-investigate
description: >
  Use when diagnosing an issue or incident with Firetiger and tracking the findings
  — investigating, troubleshooting, or root-causing a problem using telemetry, or
  recording what you found in a durable investigation. Always use this skill for
  incident diagnosis — it carries the critical gotchas (run schema before create,
  query the real Iceberg tables not a generic "traces" table, document findings
  incrementally) that turn scattered queries into a tracked investigation.
license: Apache-2.0
user_invocable: true
user_invocable_description: "Start an investigation to diagnose issues in Firetiger"
metadata:
  author: firetiger
  version: "1.0.0"
  homepage: https://firetiger.com
  source: https://github.com/firetiger-oss/skills
---

# Firetiger Investigate

A Firetiger investigation is a time-bounded analysis session that tracks your findings, queries, and
conclusions in one place. Investigations are a Firetiger MCP collection managed with the generic CRUD tools
(`schema`, `list`, `create`, `get`, `update`, `delete`).

## Workflow

### 1. Start the investigation
```
schema with collection: "investigations"    # learn the fields first — they're inferred and may drift
create with resource: "investigations"       # title, description, time_range, services
```
Note the returned investigation ID.

### 2. Analyze telemetry
Use the `query` tool against the per-service Iceberg tables (`"opentelemetry/traces/{service}"`,
`"opentelemetry/logs/{service}"`). Discover services with `SHOW TABLES;`. Every `SELECT` needs `LIMIT < 200`.
See the `firetiger-query` skill for the full schema; the essentials: duration = `end_time - start_time`, error
status = `status.code = 2`, filter on `start_time` / `time` first.

**Errors in the window:**
```sql
SELECT trace_id, name, status.code, status.message, start_time
FROM "opentelemetry/traces/checkout-service"
WHERE status.code = 2
  AND start_time BETWEEN TIMESTAMPTZ '{start}' AND TIMESTAMPTZ '{end}'
ORDER BY start_time DESC
LIMIT 100;
```

**Latency by operation:**
```sql
SELECT name, COUNT(*) AS count,
       AVG(EXTRACT(EPOCH FROM (end_time - start_time))) * 1e3 AS avg_ms,
       MAX(EXTRACT(EPOCH FROM (end_time - start_time))) * 1e3 AS max_ms
FROM "opentelemetry/traces/checkout-service"
WHERE start_time BETWEEN TIMESTAMPTZ '{start}' AND TIMESTAMPTZ '{end}'
GROUP BY name
ORDER BY avg_ms DESC
LIMIT 100;
```

**Error logs → then pull the trace:**
```sql
SELECT time, severity_text, body, trace_id
FROM "opentelemetry/logs/checkout-service"
WHERE time BETWEEN TIMESTAMPTZ '{start}' AND TIMESTAMPTZ '{end}'
  AND severity_number >= 13   -- WARN and above
ORDER BY time DESC
LIMIT 100;
```
```sql
SELECT name, resource.attributes.service.name AS service, start_time,
       end_time - start_time AS duration, status.code
FROM "opentelemetry/traces/checkout-service"
WHERE trace_id = x'{trace_id_hex}'
ORDER BY start_time
LIMIT 100;
```

### 3. Document findings (incrementally)
```
update with name: "investigations/{id}"     # findings, patterns, affected services, recommendations
```
Record the specific `trace_id`s that prove the issue.

### 4. Close it
```
update with name: "investigations/{id}"
  status: "resolved"
  root_cause: "..."
  resolution: "..."
```

## Common scenarios

| Scenario | Approach |
|----------|----------|
| **High latency** | Find slow traces (order by `end_time - start_time`) → identify the span contributing most → check DB queries, external calls, contention on that span. |
| **Error spike** | Group errors by service + message → find the first occurrence → correlate with a deploy or config change (see `firetiger-monitor-deploy`). |
| **Missing data** | Count spans by service over time → look for gaps → verify instrumentation with `firetiger-instrument`. |

## Common Mistakes

| # | Mistake | Fix |
|---|---------|-----|
| 1 | **`create` before `schema`** | Investigation fields are inferred and may drift — call `schema` first. |
| 2 | **Querying a generic `traces` table** | Data lives in `"opentelemetry/traces/{service}"` — run `SHOW TABLES;` to find services. |
| 3 | **`status_code = 'ERROR'` / `duration_ns`** | Use `status.code = 2` and `end_time - start_time` — see the query gotchas. |
| 4 | **Not tracking findings** | Update the investigation as you go; don't leave analysis only in chat. |
| 5 | **No time window** | Define and filter a specific window first — it's the whole point of an investigation and enables partition pruning. |
| 6 | **Ignoring dependencies** | Check upstream and downstream services, not just the suspect one. |

## Related

- Query mechanics and full schema: `firetiger-query`.
- Automate recurring investigations: `firetiger-create-agent`.
- Tie an investigation to a specific deploy: `firetiger-monitor-deploy`.
