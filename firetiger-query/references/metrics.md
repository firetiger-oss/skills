# Querying metrics

Metrics are split across a **series** table (metadata: name, type, unit, resource/attributes) and per-kind
**data** tables (timestamped values). Join a data table to the series table on the `series` key.

## Data tables by metric kind

| Table | Metric kind |
|-------|-------------|
| `opentelemetry_metrics_gauges` | Gauges (point-in-time values) |
| `opentelemetry_metrics_counters_cumulative` | Cumulative counters |
| `opentelemetry_metrics_counters_delta` | Delta counters |
| `opentelemetry_metrics_histograms_cumulative` | Cumulative histograms |

`opentelemetry_metrics_series` holds one row per unique metric+attribute combination.

## Series join pattern

```sql
SELECT s.name AS metric_name,
       s.resource.attributes.service.name AS service,
       s.attributes.http.route AS route,
       g.time, g.value
FROM opentelemetry_metrics_gauges g
JOIN opentelemetry_metrics_series s ON g.series = s.series
WHERE g.time >= NOW() - INTERVAL '1 hour'
  AND s.name = 'http.server.active_requests'
ORDER BY g.time DESC
LIMIT 100;
```

## Discover available metrics

```sql
SELECT DISTINCT name, type, unit, description
FROM opentelemetry_metrics_series
WHERE time >= NOW() - INTERVAL '1 day'
ORDER BY name
LIMIT 100;
```

## Notes

- Metric tables use `time` (not `start_time`) as the partition key — filter on it first.
- Attributes on the series (`s.attributes.*`, `s.resource.attributes.*`) follow the same depth-2 inference rule
  as traces/logs — see [schema.md](schema.md).
- Every `SELECT` still needs `LIMIT < 200`.
