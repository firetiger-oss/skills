# Example: high-risk DB migration monitoring plan

> Source change: PR #6128 adds a `NOT NULL` column `tier` to the `users` table (50M rows), with a backfill migration that runs in batches of 10k. Deploys to staging then prod via GitHub Actions. Telemetry: Honeycomb (traces) + Prometheus (DB infra).

## Monitoring plan

**Risk tier:** high — schema change + backfill on a large table; the backfill is the riskiest part and can't be hot-fixed if it leaves the column partially populated.
**Intended effect:** `users.tier` is non-null on all rows by the end of the backfill window; new rows are inserted with `tier` populated; queries that filter on `tier` return non-empty results.
**Blast radius (unintended):** `users-svc` (write path), Postgres primary (lock contention during ALTER + backfill), read replicas (replication lag if backfill is large), every consumer of the `users.tier` field (downstream services that may have stale schema).
**Rollback:** if backfill is in flight, kill the backfill job (`kubectl delete job users-tier-backfill -n production`); the migration script is idempotent so a re-run after fix is safe. If migration is fully applied and a regression appears, revert PR + redeploy + run a follow-up migration to drop the column.

### Environments

#### staging
Deploy detection:
```
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
| users-error-rate | ratio | `Honeycomb:query` dataset=users-svc; calculations = `[COUNT_WHERE error=true, COUNT]`; breakdowns=[env]; time_range=86400 | staging 0.31% / prod 0.12% | > 5× baseline sustained 5m | unintended-watch | shared |
| users-latency-p99 | gauge | `Honeycomb:query` dataset=users-svc; calculations=`[P99(duration_ms)]`; breakdowns=[env]; time_range=86400 | staging 180ms / prod 95ms | > baseline + 200ms sustained 5m | unintended-watch | shared |
| db-cpu | gauge | `Prometheus:query_range` `avg(rate(node_cpu_seconds_total{mode!="idle",job="postgres"}[5m])) by (env)` | staging 0.22 / prod 0.41 | > 0.85 sustained 2m | unintended-watch | shared |
| db-replica-lag | gauge | `Prometheus:query_range` `pg_replication_lag_seconds by (env)` | staging 0.4s / prod 0.9s | > 30s sustained 2m | unintended-watch | shared |
| db-conn-pool-saturation | gauge | `Prometheus:query_range` `avg(rate(pg_stat_activity_count[5m])) by (env) / avg(pg_settings_max_connections) by (env)` | staging 0.15 / prod 0.38 | > 0.90 sustained 2m | unintended-watch | shared |
| backfill-rows-remaining | gauge | `Prometheus:query_range` `migration_rows_remaining{migration="users_tier_backfill"} by (env)` | initial: 50e6 | declining; should reach 0 within 60m on prod | intended-down | shared |
| users-tier-null-fraction | ratio | `Prometheus:query_range` `sum(users_tier_null_count) by (env) / sum(users_total_count) by (env)` (assumes a metric emitted by the service) | initial: ~1.0 | < 0.001 by +24h checkpoint | intended-down | shared |

### Checkpoints

`+10m, +30m, +1h, +2h, +24h, +72h`

(Full schedule because: backfill takes ~60m and replica catch-up may extend beyond that; +24h covers the daily-cycle peak and any nightly batch jobs that read `users.tier`; +72h confirms stability across a weekly cycle.)

### Activation

After the change merges and the deploy is triggered, run:

```
/execute-change-control examples/high-risk-db-migration.md
```

in this same session to monitor it.
