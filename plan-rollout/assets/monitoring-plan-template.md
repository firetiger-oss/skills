# Monitoring plan template

Append the rendered version of this template to the user's plan file. The fields in `${PLAN_*}` are filled by `render_plan_section.sh` from JSON input; the agent may also fill them in directly without invoking the script.

---

## Monitoring plan

**Risk tier:** ${PLAN_TIER} — ${PLAN_TIER_REASON}
**Intended effect:** ${PLAN_INTENDED_EFFECT}
**Blast radius (unintended):** ${PLAN_BLAST_RADIUS}
**Rollback:** ${PLAN_ROLLBACK_HINT}

### Environments

${PLAN_ENVIRONMENTS_BLOCK}

> Per-environment block format (one per env):
> ```
> #### <env-name>
> Deploy detection:
>   <exact poll command>
> Match: <condition that returns true once the deploy is in for this env>
> ```

### Indicators

${PLAN_INDICATORS_TABLE}

> Indicators table format:
> | Name | Kind | Source | Baseline (24h) | Threshold | Direction | Scope |
> |------|------|--------|----------------|-----------|-----------|-------|
> | err-rate-checkout | ratio | `Datadog:query_metrics` `sum:errors{service:checkout}.as_count() / sum:requests{service:checkout}.as_count() by {env}` | staging 0.21% / prod 0.08% | > 5× baseline sustained 5m | unintended-watch | shared |
> | cache-hit-ratio   | ratio | `Datadog:query_metrics` `sum:cache.hit{...} / (sum:cache.hit{...} + sum:cache.miss{...}) by {env}` | staging 78% / prod 84% | < 90% of baseline | intended-up | shared |
> | replication-lag-us-east | gauge | `CloudWatch` `AWS/RDS ReplicaLag dimensions=[{DBInstance: db-prod-us-east}]` | 0.4s p95 | > 5s sustained 2m | unintended-watch | per-env: prod-us-east-1 |

### Checkpoints

${PLAN_CHECKPOINTS}

### Activation

After the change merges and the deploy is triggered, run:

```
/monitor-rollout <path-to-this-plan-file>
```

in this same session to monitor it.
