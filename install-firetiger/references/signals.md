# Telemetry Signal Guide

Choose the right signal for your observability needs.

## Signal Overview

| Signal | Best For | Cardinality | Retention Cost |
|--------|----------|-------------|----------------|
| **Traces** | Request flow, latency breakdown | High | High |
| **Metrics** | Aggregations, SLOs, dashboards | Low | Low |
| **Logs** | Discrete events, debugging | Medium | Medium |

## When to Use Traces

Traces capture the journey of a request through your system.

**Use for:**
- Understanding request latency breakdown
- Debugging distributed system failures
- Identifying bottlenecks across services
- Error propagation analysis

**Attributes to include:**
- Request/response metadata
- User/tenant identifiers
- Business operation context
- Error details

**Avoid:**
- High-frequency operations (use metrics instead)
- Sensitive data (PII, credentials)

## When to Use Metrics

Metrics are aggregated measurements over time.

**Use for:**
- SLO tracking (latency percentiles, error rates)
- Resource utilization (CPU, memory, connections)
- Business KPIs (orders/minute, revenue)
- Alerting thresholds

**Metric types:**
| Type | Use Case | Example |
|------|----------|---------|
| Counter | Cumulative totals | `requests_total` |
| Gauge | Current value | `active_connections` |
| Histogram | Distributions | `request_duration_seconds` |

**Best practices:**
- Keep cardinality low (limit label combinations)
- Use histograms for latency, not averages
- Align bucket boundaries with SLO thresholds

## When to Use Logs

Logs capture discrete events with context.

**Use for:**
- Error details and stack traces
- Audit trails
- State changes
- Debugging information

**Structured logging:**
```json
{
  "level": "error",
  "message": "Payment failed",
  "order_id": "ord_123",
  "error_code": "INSUFFICIENT_FUNDS",
  "trace_id": "abc123"
}
```

**Best practices:**
- Always include trace_id for correlation
- Use structured formats (JSON)
- Set appropriate log levels
- Avoid logging sensitive data

## Correlation

Link signals together for full observability:

1. **Trace ID in logs**: Include `trace_id` in every log line
2. **Exemplars in metrics**: Attach trace IDs to metric samples
3. **Span events**: Add logs as events within spans

```typescript
// Logs with trace context
const span = trace.getActiveSpan();
logger.info('Processing order', {
  orderId,
  traceId: span?.spanContext().traceId,
});
```

## Sampling Strategy

Not all data needs full fidelity:

| Signal | Recommendation |
|--------|----------------|
| Traces | Sample 1-10% in production, 100% for errors |
| Metrics | Always collect (pre-aggregated) |
| Logs | Filter by level, sample debug logs |

```typescript
// Head-based sampling
const sampler = new ParentBasedSampler({
  root: new TraceIdRatioBasedSampler(0.1), // 10%
});
```
