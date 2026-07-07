# Firetiger telemetry schema

Firetiger infers schema dynamically from incoming OpenTelemetry data, so exact columns vary per service. Run
`DESCRIBE "table_name"` to see the live shape. The columns below are always present.

## Traces — `"opentelemetry/traces/{service_name}"`

| Column | Type | Description |
|--------|------|-------------|
| `trace_id` | BINARY(16) | W3C Trace Context trace ID. Match with `x'...'` literals. |
| `span_id` | BINARY(8) | Span ID within the trace |
| `parent_span_id` | BINARY(8) | Parent span ID (optional) |
| `name` | STRING | Logical operation name (span name) |
| `kind` | INT | 0=UNSPECIFIED, 1=INTERNAL, 2=SERVER, 3=CLIENT, 4=PRODUCER, 5=CONSUMER |
| `start_time` | TIMESTAMPTZ | Span start (partition key — filter on this first) |
| `end_time` | TIMESTAMPTZ | Span end |
| `status.code` | INT | 0=UNSET, 1=OK, 2=ERROR |
| `status.message` | STRING | Status message |
| `attributes` | STRUCT | Span attributes (dynamically inferred) |
| `resource.attributes.service.name` | STRING | Service name |
| `resource.attributes.service.namespace` | STRING | Service namespace |
| `resource.attributes.service.version` | STRING | Service version |

**Duration is calculated, not stored:** `end_time - start_time AS duration`.

## Logs — `"opentelemetry/logs/{service_name}"`

| Column | Type | Description |
|--------|------|-------------|
| `time` | TIMESTAMPTZ | Log timestamp (partition key — filter on this first) |
| `observed_time` | TIMESTAMPTZ | When the log was observed |
| `severity_number` | INT | TRACE=1-4, DEBUG=5-8, INFO=9-12, WARN=13-16, ERROR=17-20, FATAL=21-24 |
| `severity_text` | STRING | TRACE, DEBUG, INFO, WARN, ERROR, FATAL |
| `body` | ANY | Log message body |
| `trace_id` | BINARY(16) | Trace ID for correlation (optional) |
| `span_id` | BINARY(8) | Span ID for correlation (optional) |
| `attributes` | STRUCT | Log attributes (dynamically inferred) |
| `resource.attributes.service.name` | STRING | Service name |

## Accessing attributes

Attributes and resource attributes are nested structs — access with dot notation:

```sql
-- Span attributes (semantic conventions)
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

### Type inference depth limit

Firetiger expands inferred attribute types to a **depth of 2 levels**:

- **Levels 1–2** — expanded into queryable struct columns (`attributes.http.route`).
- **Level 3+** — stored as hex-encoded binary JSON. Decode and extract:

```sql
SELECT
  json_extract_string(decode(attributes.request.context), '$.tenant_id') AS tenant_id
FROM "opentelemetry/traces/api"
WHERE start_time >= NOW() - INTERVAL '1 hour'
LIMIT 100;
```
