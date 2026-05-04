# Example: low-risk bugfix monitoring plan

> Source change: a typo fix in the request-validation error message returned by `POST /api/v1/widgets` when the body is malformed. One file, two lines. Deploys to prod only via GitHub Actions.

## Monitoring plan

**Risk tier:** low — text-only change to error-message body, no behaviour change beyond cosmetic.
**Intended effect:** error message now reads correctly (verified by hitting the endpoint with a malformed payload post-deploy; no metric will move).
**Blast radius (unintended):** `widgets-svc` request-validation path; nothing else touches this code.
**Rollback:** revert PR via `gh pr revert <pr-number>` and redeploy via `deploy.yml`.

### Environments

#### prod
Deploy detection:
```
gh run list --workflow=deploy.yml --branch=main --limit=1 --json status,conclusion,headSha
```
Match: `status==completed && conclusion==success && headSha==<merge-sha>`

### Indicators

| Name | Kind | Source | Baseline (24h) | Threshold | Direction | Scope |
|------|------|--------|----------------|-----------|-----------|-------|
| error-rate-widgets | ratio | `Datadog:query_metrics` `sum:trace.servlet.request.errors{service:widgets}.as_count() / sum:trace.servlet.request.hits{service:widgets}.as_count() by {env}` | 0.42% | > 5× baseline sustained 5m | unintended-watch | shared |
| traffic-widgets | gauge | `Datadog:query_metrics` `sum:trace.servlet.request.hits{service:widgets}.as_rate() by {env}` | 320 req/s | < 50% of baseline for 10m | unintended-watch | shared |

(Latency and saturation omitted — change is text-only and cannot plausibly affect them; including them would add noise without insight.)

### Checkpoints

`+10m, +30m`

### Activation

After the change merges and the deploy is triggered, run:

```
/execute-change-control examples/low-risk-bugfix.md
```

in this same session to monitor it.
