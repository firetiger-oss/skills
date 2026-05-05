# Multi-environment monitoring

A change usually deploys to more than one environment: staging then prod, multi-region (us-east-1 + eu-west-1 + ap-northeast-1), per-tenant fan-out (BYOC customers), preview + production (Vercel), or a fleet of canary cells. The plan must enumerate them and the executor must monitor each independently.

## Default environment list by tier

| Tier | Default envs (when the user can't tell you) |
|------|---------------------------------------------|
| Low | prod-only |
| Medium | staging + prod |
| High | all available envs (staging + prod + every region/tenant the deploy system fans out to) |

Override these only when the user is explicit. Hotfixes are typically prod-only regardless of tier.

## How to enumerate

The `enumerate_envs.sh` script in `scripts/` parses common deploy-config shapes:

| Source | What it parses |
|--------|----------------|
| `.github/workflows/*.y*ml` | `strategy.matrix` jobs; per-environment workflows |
| `argocd/`, `gitops/`, `*-applicationset.yaml` | `ApplicationSet` `generators.list` and `generators.cluster` |
| `vercel.json`, `.vercel/` | `target` field; preview vs production |
| `terraform/stacks/`, `deployments/` | per-stack tfvars |
| `helm/values-*.yaml`, `helmfile.yaml` | per-environment overrides |

After running the script, surface its output and ask the user: *"This change will deploy to {env list}. Confirm or amend."* Don't proceed with an unconfirmed list.

## Naming conventions

Use the deploy system's own environment names verbatim. Don't invent friendly aliases — the executor needs to match these names against telemetry tags and deploy-detection commands.

Examples:
- GitHub Actions matrix → use the matrix value (`{env: staging}`, `{env: prod-us}`, `{env: prod-eu}`).
- ArgoCD `ApplicationSet` → use the `name` of each generated `Application` (`my-svc-prod-us-east-1`, `my-svc-prod-eu-west-1`).
- Vercel → use Vercel's terms: `production`, `preview`, plus any environment alias the team has configured.

## Per-env vs shared indicators

The executor's default mode is **multiplexed**: one query per indicator, grouped by environment. This is much cheaper than N queries per checkpoint and matches how Datadog, Honeycomb, and Prometheus all express it.

| Telemetry source | Multi-env grouping syntax |
|------------------|---------------------------|
| Datadog | `by {env}` in metric query |
| Prometheus / PromQL | `by (env)` |
| Honeycomb | `BREAKDOWN: env` |
| Axiom | `summarize ... by env` |
| CloudWatch | `Dimension: env` |

When an indicator is genuinely environment-specific (a region-only feature flag, a tenant-specific SLO), promote it to a per-env entry instead of forcing a `GROUP BY` query that doesn't make sense.

## Per-env deploy-detection

Each environment gets its own `Deploy detection` line because:
- Different envs may use different deploy systems (staging via GH Actions, prod via ArgoCD).
- Even within one system, the env-name has to be in the poll command (matrix entry, ArgoCD app name, Vercel target).
- Each env's deploy_time is independent; the executor records them separately.

In the plan template:

```
### Environments

#### staging
Deploy detection:
  gh run list --workflow=deploy-staging.yml --branch=main --limit=1 --json status,conclusion,headSha
Match: status==completed && conclusion==success && headSha==<merge_sha>

#### prod-us-east-1
Deploy detection:
  argocd app get my-svc-prod-us-east-1 -o json | jq '.status.sync.revision'
Match: revision==<merge_sha> || ancestor-of(<merge_sha>)
```

## Per-env outcomes and aggregation

The executor:
1. Tracks each env's `MonitoredDeployment` state independently (`POLLING_FOR_DEPLOY → CHECKING → terminal`).
2. Computes the aggregate plan outcome as the worst per-env outcome.
3. On the **first** env to reach `ISSUE_DETECTED` (after evidence discipline), pauses all envs and hands off to plan mode.

The single-issue-mode handoff is in [`monitor-rollout/references/multi-env-execution.md`](../../monitor-rollout/references/multi-env-execution.md). The plan-side just needs to enumerate the envs and the indicators correctly; the executor handles the orchestration.
