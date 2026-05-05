# Example: multi-region rollout monitoring plan

> Source change: rolls out a new caching layer on the `search-svc`. Fanned out across four regions via an ArgoCD `ApplicationSet`: us-east-1, us-west-2, eu-west-1, ap-northeast-1. Telemetry: Honeycomb (traces) + Prometheus (cache backend).

## Monitoring plan

**Risk tier:** high — caching layer is on the request hot path; misconfigured TTLs / key-derivation can produce stale results across all regions, and per-region replica setups can mask the issue if monitoring isn't per-region.
**Intended effect:** `search-svc` cache hit ratio rises to >70% within 1h post-deploy in each region; p99 latency drops by ≥50ms vs pre-deploy.
**Blast radius (unintended):** `search-svc` request path (every region); Redis cluster (added load); cache key correctness (stale or wrong results returned to users); cross-region cache replication lag.
**Rollback:** the cache is enabled by feature flag `search-cache-v2`. Roll back by flipping the flag off in LaunchDarkly (per-region rollout supported). If catastrophic, also revert PR and redeploy; the flag-flip is sufficient for the read path.

### Environments

Four ArgoCD-managed environments, one Application per region. ApplicationSet generates `search-svc-prod-<region>`.

#### prod-us-east-1
Deploy detection:
```
argocd app get search-svc-prod-us-east-1 -o json | jq '{ syncStatus: .status.sync.status, revision: .status.sync.revision, healthStatus: .status.health.status }'
```
Match: `syncStatus==Synced && healthStatus==Healthy && (revision==<merge-sha> || git merge-base --is-ancestor <merge-sha> <revision>)`

#### prod-us-west-2
Deploy detection:
```
argocd app get search-svc-prod-us-west-2 -o json | jq '{ syncStatus: .status.sync.status, revision: .status.sync.revision, healthStatus: .status.health.status }'
```
Match: same shape as us-east-1 above.

#### prod-eu-west-1
Deploy detection:
```
argocd app get search-svc-prod-eu-west-1 -o json | jq '{ syncStatus: .status.sync.status, revision: .status.sync.revision, healthStatus: .status.health.status }'
```
Match: same shape.

#### prod-ap-northeast-1
Deploy detection:
```
argocd app get search-svc-prod-ap-northeast-1 -o json | jq '{ syncStatus: .status.sync.status, revision: .status.sync.revision, healthStatus: .status.health.status }'
```
Match: same shape.

### Indicators

Most indicators are `shared` (same query, breakdowns by region). Replica-lag is per-region.

| Name | Kind | Source | Baseline (24h) | Threshold | Direction | Scope |
|------|------|--------|----------------|-----------|-----------|-------|
| search-error-rate | ratio | `Honeycomb:query` dataset=search-svc; calculations=`[COUNT_WHERE error=true, COUNT]`; breakdowns=[region] | us-east 0.16% / us-west 0.18% / eu-west 0.21% / ap-northeast 0.20% | > 3× baseline sustained 5m | unintended-watch | shared |
| search-latency-p99 | gauge | `Honeycomb:query` calculations=`[P99(duration_ms)]`; breakdowns=[region] | us-east 240ms / us-west 245ms / eu-west 280ms / ap-northeast 310ms | > baseline + 100ms sustained 5m | unintended-watch | shared |
| search-cache-hit-ratio | ratio | `Honeycomb:query` calculations=`[COUNT_WHERE cache.hit=true, COUNT]`; breakdowns=[region] | 0% (cache doesn't exist yet) | > 70% by +1h checkpoint | intended-up | shared |
| redis-cpu-us-east-1 | gauge | `Prometheus:query_range` `avg(rate(redis_cpu_seconds_total[5m]))` (us-east-1 prom datasource) | 0.34 | > 0.85 sustained 2m | unintended-watch | per-env: prod-us-east-1 |
| redis-cpu-us-west-2 | gauge | `Prometheus:query_range` `avg(rate(redis_cpu_seconds_total[5m]))` (us-west-2 prom datasource) | 0.31 | > 0.85 sustained 2m | unintended-watch | per-env: prod-us-west-2 |
| redis-cpu-eu-west-1 | gauge | `Prometheus:query_range` `avg(rate(redis_cpu_seconds_total[5m]))` (eu-west-1 prom datasource) | 0.29 | > 0.85 sustained 2m | unintended-watch | per-env: prod-eu-west-1 |
| redis-cpu-ap-northeast-1 | gauge | `Prometheus:query_range` `avg(rate(redis_cpu_seconds_total[5m]))` (ap-northeast-1 prom datasource) | 0.36 | > 0.85 sustained 2m | unintended-watch | per-env: prod-ap-northeast-1 |
| search-result-equality | ratio | `Honeycomb:query` calculations=`[COUNT_WHERE result_diff=true, COUNT]`; breakdowns=[region] | n/a (new metric); expected ≈0% | > 0.5% sustained 5m | unintended-watch | shared |

### Checkpoints

`+10m, +30m, +1h, +2h, +24h, +72h`

(Full schedule because: regional rollout may take time to converge across all four ArgoCD applications; +24h covers weekly daily-cycle for ap-northeast-1 which has very different peak hours from us-east-1; +72h confirms stability under weekly business-pattern cycles.)

### Activation

After the change merges and the ArgoCD applications begin syncing, run:

```
/monitor-rollout examples/multi-region-rollout.md
```

in this same session to monitor it. The executor will poll all four regions independently and emit per-region rows in each `CHECK_COMPLETE` block.
