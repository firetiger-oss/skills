# Worked example monitoring plans

These are the kind of monitoring sections `plan-rollout` aims to produce. They serve two purposes:

1. As reference templates for the agent — concrete examples of how the schema fills in for different change shapes.
2. As documentation for users — what a "good" monitoring plan looks like before they get the agent to write one.

The examples cover the typical shape range:

| File | Shape |
|------|-------|
| [low-risk-bugfix.md](low-risk-bugfix.md) | Single-env, two early checkpoints, minimal indicator set |
| [medium-risk-api-change.md](medium-risk-api-change.md) | Staging + prod, golden signals + intended-effect indicator |
| [high-risk-db-migration.md](high-risk-db-migration.md) | Staging + prod, full +24h/+72h schedule, DB-side indicators |
| [high-risk-infra-change.md](high-risk-infra-change.md) | Staging + prod, full schedule, infra/saturation focus |
| [multi-region-rollout.md](multi-region-rollout.md) | Four regions fanned out via ArgoCD ApplicationSet |
| [static-site-deploy.md](static-site-deploy.md) | Vercel/Netlify static rebuild, HTTP probe + content equality + edge-cache TTL |

Each example follows the template at `plan-rollout/assets/monitoring-plan-template.md`. They're purely illustrative — the indicator names, baselines, and thresholds are made-up plausible numbers; for a real change the planner would query the user's actual telemetry.

## Where plans live by convention

`plan-rollout` writes generated plans to `.rollout/<branch-slug>-monitoring-plan.md` (relative to the git root). The `monitor-rollout` skill auto-discovers plans there when invoked without an explicit path.

If your team wants to share plans across PR reviews (so reviewers can see what monitoring is set up for the change), commit `.rollout/` to the repo. Otherwise add it to `.gitignore`:

```
# .gitignore
.rollout/
```

The latter is the default expectation — plans are session-local artifacts, not source-tree commits.
