---
name: firetiger-investigate
description: "Run a Firetiger investigation to diagnose an issue or incident and track findings. Use when the user wants to investigate, diagnose, or troubleshoot a problem using telemetry, or track findings during an incident. Covers the investigations collection (schema/list/create/get/update), a broad-to-narrow analysis workflow, and SQL patterns for latency, errors, and missing data."
user_invocable: true
user_invocable_description: "Start an investigation to diagnose issues in Firetiger"
---

# Firetiger Investigate

You are an expert at running investigations in Firetiger to diagnose issues and analyze telemetry.

## Overview

Firetiger investigations are time-bounded analysis sessions that systematically diagnose issues using
observability data. An investigation tracks your findings, queries, and conclusions in one place. Investigations
are a Firetiger MCP collection, managed with the generic CRUD tools (`schema`, `list`, `create`, `get`,
`update`, `delete`).

## Managing investigations with MCP tools

### Discover the schema
Always inspect the current fields before creating or updating — field names below are illustrative.
```
schema with collection: "investigations"
```

### List existing investigations
```
list with resource: "investigations"
```
Filter by status or time range to find relevant ones.

### Create an investigation
```
create with resource: "investigations"
```
Typical fields:
- **title** — brief description of what you're investigating
- **description** — detailed context about the issue
- **time_range** — the time window to focus on
- **services** — relevant services

### Get details
```
get with name: "investigations/{id}"
```

### Update with findings / status
```
update with name: "investigations/{id}"
```
Update fields like **findings**, **status** (`in_progress`, `resolved`, `closed`), and **root_cause**.

## Workflow

### 1. Start the investigation
1. Run `schema` to learn the fields.
2. `create` an investigation with a clear title and context.
3. Note the investigation ID / resource name.

### 2. Analyze telemetry
Use the `query` tool to run SQL against the warehouse. Firetiger telemetry lives in per-service Iceberg
tables (`"opentelemetry/traces/{service}"`, `"opentelemetry/logs/{service}"`) — see the `firetiger-query`
skill for the full schema. Every `SELECT` needs `LIMIT < 200`. Discover services with `SHOW TABLES;`.

**Errors in the time window:**
```sql
SELECT trace_id, name, status.code, status.message, start_time
FROM "opentelemetry/traces/checkout-service"
WHERE status.code = 2  -- ERROR
  AND start_time BETWEEN TIMESTAMPTZ '{start_time}' AND TIMESTAMPTZ '{end_time}'
ORDER BY start_time DESC
LIMIT 100;
```

**Latency patterns by operation:**
```sql
SELECT name,
       COUNT(*) AS count,
       AVG(EXTRACT(EPOCH FROM (end_time - start_time))) * 1e3 AS avg_ms,
       MAX(EXTRACT(EPOCH FROM (end_time - start_time))) * 1e3 AS max_ms
FROM "opentelemetry/traces/checkout-service"
WHERE start_time BETWEEN TIMESTAMPTZ '{start_time}' AND TIMESTAMPTZ '{end_time}'
GROUP BY name
ORDER BY avg_ms DESC
LIMIT 100;
```

**Correlate error logs with traces:**
```sql
SELECT time, severity_text, body, trace_id
FROM "opentelemetry/logs/checkout-service"
WHERE time BETWEEN TIMESTAMPTZ '{start_time}' AND TIMESTAMPTZ '{end_time}'
  AND severity_number >= 13  -- WARN and above
ORDER BY time DESC
LIMIT 100;
```
Then pull the full trace for a `trace_id` of interest:
```sql
SELECT name, resource.attributes.service.name AS service, start_time,
       end_time - start_time AS duration, status.code
FROM "opentelemetry/traces/checkout-service"
WHERE trace_id = x'{trace_id_hex}'
ORDER BY start_time
LIMIT 100;
```

### 3. Document findings
`update` the investigation as you go — patterns identified, root-cause analysis, affected services or
endpoints, and recommendations. Note specific `trace_id`s that demonstrate the issue.

### 4. Close it
```
update with name: "investigations/{id}"
  status: "resolved"
  root_cause: "Description of the root cause"
  resolution: "How it was fixed or mitigated"
```

## Best practices

1. **Define a clear time window** and filter on it first (partition pruning).
2. **Start broad, then narrow** — high-level aggregates before drilling into individual traces.
3. **Document incrementally** — update the investigation as findings emerge.
4. **Link specific traces** — record the `trace_id`s that prove the issue.
5. **Check dependencies** — look upstream and downstream of the suspect service.

## Common scenarios

### High latency
1. Find slow traces in the window (order by `end_time - start_time`).
2. Identify the service/span contributing most.
3. Check DB queries, external calls, or resource contention on that span.

### Error spike
1. Group errors by service and error type/message.
2. Find the first occurrence of the pattern.
3. Correlate with a deployment or config change — the `firetiger-monitor-deploy` skill ties deploys to windows.

### Missing data
1. Count spans by service over time.
2. Look for gaps.
3. Verify instrumentation with `firetiger-instrument`.

## Related

- To have an autonomous agent run investigations on a schedule or on demand, see `firetiger-create-agent`.
- To tie an investigation to a specific deploy, see `firetiger-monitor-deploy`.
