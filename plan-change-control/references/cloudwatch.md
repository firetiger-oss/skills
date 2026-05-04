# CloudWatch (telemetry source)

## Detection

CloudWatch is **priority-5**. Detect via:
- AWS credentials configured for the account that owns the metrics (`aws sts get-caller-identity` returns success).
- The `aws` CLI on `$PATH`.
- MCP tools matching `CloudWatch:*` or `AWS:*`.

## Indicator query patterns

CloudWatch supports basic statistics + Metric Math expressions. Multi-dim grouping is via Dimensions.

### Error ratio (Lambda)

```
kind: ratio
source: CloudWatch:get_metric_data
query:
  expression: |
    "errors / requests"
  metrics:
    - id: errors
      metric: AWS/Lambda Errors
      dimensions: [{ FunctionName: my-svc-prod-us-east-1 }]
      stat: Sum, period: 300
    - id: requests
      metric: AWS/Lambda Invocations
      dimensions: [{ FunctionName: my-svc-prod-us-east-1 }]
      stat: Sum, period: 300
```

### Latency p99 (ALB)

```
kind: gauge
source: CloudWatch:get_metric_data
metric: AWS/ApplicationELB TargetResponseTime
dimensions: [{ LoadBalancer: app/my-alb/abcd1234 }]
stat: p99
period: 300
```

### Traffic (request count, ALB)

```
kind: gauge
source: CloudWatch:get_metric_data
metric: AWS/ApplicationELB RequestCount
dimensions: [{ LoadBalancer: app/my-alb/abcd1234 }]
stat: Sum
period: 60
```

### Saturation (RDS CPU)

```
kind: gauge
source: CloudWatch:get_metric_data
metric: AWS/RDS CPUUtilization
dimensions: [{ DBInstanceIdentifier: my-db-prod }]
stat: Average
period: 300
```

## Multi-environment grouping

CloudWatch dimensions are environment-specific (`FunctionName: my-svc-prod-us-east-1` vs `my-svc-prod-eu-west-1`). The plan typically lists the indicator as `per-env`, with one entry per env's dimensions.

For accounts that use the `Environment` dimension consistently, you can use Metric Insights:

```
SELECT AVG(CPUUtilization) FROM "AWS/RDS"
GROUP BY Environment
```

## Querying the 24-hour baseline

Use `start-time` 24h ago and `end-time` now. The 5-minute period is the typical default for application metrics; 1-minute for high-resolution Lambda metrics.

## Common pitfalls

- **Period mismatch.** Mixing `Period: 60` and `Period: 300` in a Metric Math expression silently doesn't work. Match periods.
- **Account boundaries.** If staging is in a different AWS account from prod, you need credentials for both, or cross-account observability set up.
- **Metric publication delay.** CloudWatch metrics typically lag 60–90 seconds. The executor's first checkpoint at +10m is fine; do not write checkpoints earlier than +5m.
