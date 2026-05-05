# Example: medium-risk API change monitoring plan

> Source change: adds a new `POST /api/v1/orders/preview` endpoint that previews order pricing without committing. Backed by Postgres reads only. Deploys to staging then prod via GitHub Actions. Telemetry: Datadog.

## Monitoring plan

**Risk tier:** medium — new endpoint, read-only, no infra/data writes; can be hot-fixed in <30m by removing the route registration.
**Intended effect:** `orders.preview.requests` becomes non-zero in both envs as the endpoint is exercised; latency is sub-second.
**Blast radius (unintended):** `orders-svc` (the new endpoint may share the request handler / DB connection pool); Postgres read replica (added query workload).
**Rollback:** revert PR via `gh pr revert <pr-number>` and redeploy via `deploy.yml`.

### Environments

#### staging
Deploy detection:
```
gh run list --workflow=deploy.yml --branch=main --limit=1 --json databaseId,headSha
# match the headSha == <merge-sha>; then:
gh run view <databaseId> --json jobs --jq '.jobs[] | select(.name | contains("staging")) | {status, conclusion}'
```
Match: `status==completed && conclusion==success`

#### prod
Deploy detection:
```
gh run view <databaseId> --json jobs --jq '.jobs[] | select(.name | contains("prod")) | {status, conclusion}'
```
Match: `status==completed && conclusion==success`

### Indicators

| Name | Kind | Source | Baseline (24h) | Threshold | Direction | Scope |
|------|------|--------|----------------|-----------|-----------|-------|
| error-rate-orders | ratio | `Datadog:query_metrics` `sum:trace.servlet.request.errors{service:orders}.as_count() / sum:trace.servlet.request.hits{service:orders}.as_count() by {env}` | staging 0.21% / prod 0.08% | > 3× baseline sustained 5m | unintended-watch | shared |
| latency-p99-orders | gauge | `Datadog:query_metrics` `p99:trace.servlet.request{service:orders} by {env}` | staging 215ms / prod 165ms | > baseline + 200ms sustained 5m | unintended-watch | shared |
| traffic-orders | gauge | `Datadog:query_metrics` `sum:trace.servlet.request.hits{service:orders}.as_rate() by {env}` | staging 80 req/s / prod 1450 req/s | < 50% of baseline for 10m (degenerate fail) | unintended-watch | shared |
| db-pool-saturation | gauge | `Datadog:query_metrics` `avg:postgres.pool.connections.active{service:orders}.as_count() / avg:postgres.pool.connections.size{service:orders} by {env}` | staging 0.18 / prod 0.42 | > 0.85 sustained 2m | unintended-watch | shared |
| orders-preview-rps | gauge | `Datadog:query_metrics` `sum:trace.servlet.request.hits{service:orders, resource_name:POST_orders_preview}.as_rate() by {env}` | 0 (endpoint doesn't exist yet) | > 0 in prod by +1h after deploy | intended-up | shared |

### Checkpoints

`+10m, +30m, +1h, +2h`

### Activation

After the change merges and the deploy is triggered, run:

```
/monitor-rollout examples/medium-risk-api-change.md
```

in this same session to monitor it.
