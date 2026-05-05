# Worked example monitoring plans

These are the kind of monitoring sections `plan-rollout` aims to produce. They serve two purposes:

1. As reference templates for the agent — concrete examples of how the schema fills in for different change shapes.
2. As documentation for users — what a "good" monitoring plan looks like before they get the agent to write one.

The five examples cover the typical shape range:

| File | Shape |
|------|-------|
| [low-risk-bugfix.md](low-risk-bugfix.md) | Single-env, two early checkpoints, minimal indicator set |
| [medium-risk-api-change.md](medium-risk-api-change.md) | Staging + prod, golden signals + intended-effect indicator |
| [high-risk-db-migration.md](high-risk-db-migration.md) | Staging + prod, full +24h/+72h schedule, DB-side indicators |
| [high-risk-infra-change.md](high-risk-infra-change.md) | Staging + prod, full schedule, infra/saturation focus |
| [multi-region-rollout.md](multi-region-rollout.md) | Four regions fanned out via ArgoCD ApplicationSet |

Each example follows the template at `plan-rollout/assets/monitoring-plan-template.md`. They're purely illustrative — the indicator names, baselines, and thresholds are made-up plausible numbers; for a real change the planner would query the user's actual telemetry.
