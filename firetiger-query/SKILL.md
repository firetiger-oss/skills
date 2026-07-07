---
name: firetiger-query
description: "Query Firetiger telemetry (traces, logs, metrics) with SQL via the Firetiger MCP server's query tool. Use when the user wants to find traces, search logs, inspect metrics, find errors or slow requests, aggregate telemetry, or analyze latency. Covers the Iceberg table naming scheme, trace/log/metric schemas, attribute access, and ready-to-run DuckDB SQL examples."
user_invocable: true
user_invocable_description: "Query traces, logs, and metrics with SQL"
---

# Firetiger Query

You are an expert at querying observability data in Firetiger using SQL via the MCP server.

## Overview

Firetiger stores telemetry in Apache Iceberg tables with dynamic schema inference. Use the Firetiger MCP
server's **`query`** tool to run DuckDB SQL against the data warehouse.

**Important:** every `SELECT` MUST include `LIMIT < 200`.

## Discovering schema

Discover tables and columns before writing queries:

```sql
-- List all tables
SHOW TABLES;

-- Show columns for a specific table
DESCRIBE "opentelemetry/traces/api-gateway";

-- Alternative syntax
SHOW COLUMNS FROM "opentelemetry/logs/checkout-service";
```

## Table names

Tables are namespaced by signal type and service name:

- **Traces**: `"opentelemetry/traces/{service_name}"`
- **Logs**: `"opentelemetry/logs/{service_name}"`
- **Metrics series**: `opentelemetry_metrics_series`
- **Metrics data**: `opentelemetry_metrics_gauges`, `opentelemetry_metrics_counters_cumulative`,
  `opentelemetry_metrics_counters_delta`, `opentelemetry_metrics_histograms_cumulative`, etc.

**Note:** table names with slashes must be quoted: `"opentelemetry/traces/my-service"`.

## Traces schema

| Column | Type | Description |
|--------|------|-------------|
| `trace_id` | BINARY(16) | W3C Trace Context trace ID |
| `span_id` | BINARY(8) | Span ID within trace |
| `parent_span_id` | BINARY(8) | Parent span ID (optional) |
| `name` | STRING | Logical operation name (span name) |
| `kind` | INT | Span kind: 0=UNSPECIFIED, 1=INTERNAL, 2=SERVER, 3=CLIENT, 4=PRODUCER, 5=CONSUMER |
| `start_time` | TIMESTAMPTZ | Span start timestamp (partition key) |
| `end_time` | TIMESTAMPTZ | Span end timestamp |
| `status.code` | INT | Status: 0=UNSET, 1=OK, 2=ERROR |
| `status.message` | STRING | Status message |
| `attributes` | STRUCT | Span attributes (dynamically inferred) |
| `resource.attributes.service.name` | STRING | Service name |
| `resource.attributes.service.namespace` | STRING | Service namespace |
| `resource.attributes.service.version` | STRING | Service version |

**Duration is calculated, not stored:**
```sql
end_time - start_time AS duration
```

## Logs schema

| Column | Type | Description |
|--------|------|-------------|
| `time` | TIMESTAMPTZ | Log timestamp (partition key) |
| `observed_time` | TIMESTAMPTZ | When log was observed |
| `severity_number` | INT | TRACE=1-4, DEBUG=5-8, INFO=9-12, WARN=13-16, ERROR=17-20, FATAL=21-24 |
| `severity_text` | STRING | TRACE, DEBUG, INFO, WARN, ERROR, FATAL |
| `body` | ANY | Log message body |
| `trace_id` | BINARY(16) | Trace ID for correlation (optional) |
| `span_id` | BINARY(8) | Span ID for correlation (optional) |
| `attributes` | STRUCT | Log attributes (dynamically inferred) |
| `resource.attributes.service.name` | STRING | Service name |

## Accessing attributes

Attributes are stored as nested structs. Access them with dot notation:

```sql
-- Span attributes (up to 2 levels deep)
attributes.http.method
attributes.http.route
attributes.http.status_code
attributes.db.system
attributes.db.statement

-- Resource attributes
resource.attributes.service.name
resource.attributes.service.namespace
resource.attributes.telemetry.sdk.language
```

### Type inference and deeply nested attributes

Firetiger infers attribute types with a **depth limit of 2 levels**:
- **Levels 1-2**: expanded into queryable struct columns.
- **Level 3+**: stored as hex-encoded binary JSON.

For deeply nested attributes (3+ levels), decode and extract:

```sql
SELECT
  json_extract_string(decode(attributes.request.context), '$.tenant_id') AS tenant_id
FROM "opentelemetry/traces/api"
WHERE start_time >= NOW() - INTERVAL '1 hour'
LIMIT 100;
```

## Query examples

### Recent spans
```sql
SELECT trace_id, name, resource.attributes.service.name AS service,
       end_time - start_time AS duration, start_time
FROM "opentelemetry/traces/checkout-service"
WHERE start_time >= NOW() - INTERVAL '1 hour'
ORDER BY start_time DESC
LIMIT 100;
```

### Slow spans
```sql
SELECT trace_id, name, resource.attributes.service.name AS service,
       end_time - start_time AS duration
FROM "opentelemetry/traces/api-gateway"
WHERE end_time - start_time > INTERVAL '1 second'
  AND start_time >= NOW() - INTERVAL '1 hour'
ORDER BY (end_time - start_time) DESC
LIMIT 50;
```

### Error spans
```sql
SELECT trace_id, name, status.code, status.message, start_time
FROM "opentelemetry/traces/payment-service"
WHERE status.code = 2  -- ERROR
  AND start_time >= NOW() - INTERVAL '1 hour'
ORDER BY start_time DESC
LIMIT 100;
```

### Aggregate by span name
```sql
SELECT name, COUNT(*) AS span_count,
       AVG(EXTRACT(EPOCH FROM (end_time - start_time))) AS avg_duration_sec,
       MAX(EXTRACT(EPOCH FROM (end_time - start_time))) AS max_duration_sec
FROM "opentelemetry/traces/checkout-service"
WHERE start_time >= NOW() - INTERVAL '1 hour'
GROUP BY name
ORDER BY span_count DESC
LIMIT 50;
```

### Latency percentiles by HTTP route
```sql
SELECT attributes.http.route AS route, COUNT(*) AS requests,
       PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (end_time - start_time))) AS p50_sec,
       PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (end_time - start_time))) AS p95_sec,
       PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (end_time - start_time))) AS p99_sec
FROM "opentelemetry/traces/api-gateway"
WHERE start_time >= NOW() - INTERVAL '1 hour'
  AND attributes.http.route IS NOT NULL
GROUP BY attributes.http.route
ORDER BY requests DESC
LIMIT 50;
```

### Error logs
```sql
SELECT time, severity_text, body, trace_id, resource.attributes.service.name AS service
FROM "opentelemetry/logs/checkout-service"
WHERE time >= NOW() - INTERVAL '1 hour'
  AND severity_number >= 17  -- ERROR and above
ORDER BY time DESC
LIMIT 100;
```

### Trace a request across services
```sql
SELECT name, resource.attributes.service.name AS service, start_time,
       end_time - start_time AS duration, status.code
FROM "opentelemetry/traces/api-gateway"
WHERE trace_id = x'0123456789abcdef0123456789abcdef'
ORDER BY start_time
LIMIT 100;
```

### Metrics with series join
```sql
SELECT s.name AS metric_name, s.resource.attributes.service.name AS service,
       s.attributes.http.route AS route, g.time, g.value
FROM opentelemetry_metrics_gauges g
JOIN opentelemetry_metrics_series s ON g.series = s.series
WHERE g.time >= NOW() - INTERVAL '1 hour'
  AND s.name = 'http.server.active_requests'
ORDER BY g.time DESC
LIMIT 100;
```

### Discover available metrics
```sql
SELECT DISTINCT name, type, unit, description
FROM opentelemetry_metrics_series
WHERE time >= NOW() - INTERVAL '1 day'
ORDER BY name
LIMIT 100;
```

## Tips

1. **Always include `LIMIT < 200`** — required for all `SELECT` queries.
2. **Quote table names with slashes** — `"opentelemetry/traces/my-service"`.
3. **Filter by time first** — use `start_time` (traces) or `time` (logs/metrics) for partition pruning.
4. **Calculate duration** — `end_time - start_time`, there is no duration column.
5. **Use `EXTRACT` for aggregations** — `EXTRACT(EPOCH FROM (end_time - start_time))` gives seconds as a number.
6. **Status codes are integers** — 0=UNSET, 1=OK, 2=ERROR.
7. **Discover schema first** — run `DESCRIBE "table_name"` to see available columns.
8. **Handle hex-encoded fields** — use `decode()` + `json_extract_string()` for deeply nested attributes.
