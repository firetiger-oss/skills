---
name: plan-change-control
description: "Adds a multi-environment change-monitoring section to the agent's plan: enumerates target environments (staging, prod, regions, BYOC tenants), picks SLIs (golden signals + intended-effect + business-outcome) per env or shared, queries 24h baselines, sets baseline-referenced thresholds, and chooses a checkpoint schedule based on risk tier. Use when the user is planning a code change that will be deployed, preparing a rollout, asking how to monitor a release, doing post-deploy validation prep, planning a canary, or wants production watched after merging — even when they don't say 'monitoring plan'. Anchored on Google SRE book vocabulary (golden signals, SLI, error budget, blast radius). Companion to execute-change-control."
argument-hint: "[optional: paste of the change diff or PR url]"
---

# plan-change-control

Authors a change-monitoring section for the user's plan. The section becomes the input to `execute-change-control` after the change ships.

## When to use

The user is preparing a code change that will be deployed to production. Specifically:
- They're in plan mode and the change has a production-facing surface.
- They're drafting or reviewing a PR that will deploy.
- They're asking *"how should I monitor this?", "what should we watch for?", "what are the SLIs?", "do we need a canary?"*
- They're planning a release, a rollout, or a feature flag flip.

Skip this skill when the change is read-only or local-only, dev-stack only, or pure-documentation. Tell the user no monitoring plan is warranted in those cases.

## Methodology

Anchored on the Google SRE book. Full term map in [references/sre-vocabulary.md](references/sre-vocabulary.md). Risk-tiering rubric in [references/risk-rubric.md](references/risk-rubric.md). Tier-to-checkpoint mapping in [references/checkpoint-schedule.md](references/checkpoint-schedule.md). Indicator design (RATIO vs GAUGE, baselines, thresholds) in [references/indicator-design.md](references/indicator-design.md). Multi-environment handling in [references/multi-env.md](references/multi-env.md).

The plan you author has five pillars:
1. **Risk tier** + one-sentence reason — drives checkpoint cadence.
2. **Environments** — staging, prod, regions, tenants. Each gets its own deploy-detection command and may carry its own indicator overrides.
3. **Indicators** — golden signals + intended-effect + business outcome. Each indicator has a 24h baseline value queried *now* and a threshold expressed relative to that baseline.
4. **Deploy-detection** — exact command per environment that returns "deploy started for this commit" once the rollout begins.
5. **Rollback hint** — one line. The exact thing to do if a regression is detected. Required.

Per-source telemetry recipes:
- [references/datadog.md](references/datadog.md), [references/honeycomb.md](references/honeycomb.md), [references/axiom.md](references/axiom.md), [references/prometheus.md](references/prometheus.md), [references/cloudwatch.md](references/cloudwatch.md).

Per-deploy-system recipes:
- [references/github-actions.md](references/github-actions.md), [references/buildkite.md](references/buildkite.md), [references/argocd.md](references/argocd.md), [references/vercel.md](references/vercel.md).

## Workflow

Copy this checklist into the response and tick items off as work progresses:

```
plan-change-control progress:
- [ ] 1. Analyzed the diff (services, paths, data writes, infra)
- [ ] 2. Risk-tiered the change (low/medium/high + reason)
- [ ] 3. Enumerated target environments
- [ ] 4. Probed telemetry tools; picked one default
- [ ] 5. Picked checkpoint schedule from tier
- [ ] 6. Picked indicators (golden signals + intended + business); marked per-env vs shared
- [ ] 7. Queried 24h baseline per env per indicator
- [ ] 8. Picked deploy-detection recipe + exact command per env
- [ ] 9. Picked rollback hint (one line)
- [ ] 10. Asked the user about ambiguities (or noted N/A)
- [ ] 11. Rendered plan section + companion check
```

### 1. Analyse the diff

Run `git diff <base>...<head>` (three dots — merge-base). If the user pasted a PR url, use `gh pr diff <url>` first.

Identify:
- Services and packages touched.
- HTTP request paths or RPCs whose behaviour changes.
- Data writes (new columns, migrations, queue producers).
- Infrastructure changes (Terraform, Helm, k8s manifests, IAM).
- Dependencies bumped (note major-version vs minor-version).
- Public-API contract changes.

Quote the file paths you considered — the agent and the user both benefit from the explicit paper trail.

### 2. Risk-tier the change

Read [references/risk-rubric.md](references/risk-rubric.md) and pick `low | medium | high`. State the tier and one sentence of reasoning. The tier drives step 5; do not skip the reasoning.

### 3. Enumerate target environments

Run `bash plan-change-control/scripts/enumerate_envs.sh` from inside the repo being changed. The script inspects deploy config:
- `.github/workflows/*.y*ml` for matrix jobs and per-environment workflows.
- `argocd/`, `gitops/` for `ApplicationSet` definitions.
- `vercel.json`, `.vercel/` for preview/prod scopes.
- `terraform/stacks/`, `deployments/` for fan-out targets.

Surface its output to the user and ask once: *"This change will deploy to {env list}. Confirm or amend."* Don't proceed past step 3 with an unconfirmed env list — getting it wrong silently leaves environments unmonitored.

Defaults when the user can't tell you:
- Low-risk / hotfix → prod-only.
- Medium-risk → staging + prod.
- High-risk → all available envs (staging + prod + any regions / tenants the deploy system fans out to).

### 4. Probe telemetry tools and pick one default

Run `bash plan-change-control/scripts/probe_telemetry_tools.sh`. The script lists which telemetry tools are available locally (MCP servers + CLIs). Pick **one** primary using this priority order:

1. Datadog (if `Datadog:*` MCP tools or `dog` CLI present).
2. Honeycomb (if `Honeycomb:*` MCP tools or `hccli` CLI present).
3. Axiom (if `Axiom:*` MCP tools or `axiom` CLI present).
4. Prometheus (if a `mcp__prometheus__*` server, `promtool`, or scraped Grafana datasource is reachable).
5. CloudWatch (if AWS credentials are configured for the right account).
6. Plain HTTP health-endpoint polling (last-resort fallback for service liveness).

Do not list every available tool to the user as equal options — pick the priority winner, mention the alternatives in passing if the primary is somehow inadequate. Default-with-escape-hatch beats decision paralysis.

Then read the corresponding `references/<source>.md` for that primary tool's query syntax and example indicator queries. Use the `Server:tool_name` format when referencing MCP tools (e.g. `Datadog:query_metrics`, not `mcp__datadog__query_metrics`).

### 5. Pick the checkpoint schedule from the tier

Read [references/checkpoint-schedule.md](references/checkpoint-schedule.md). Use the tier→schedule mapping there verbatim. Do not invent new schedules unless the user explicitly overrides — the schedule shape is calibrated against production data and ad-hoc tweaks are rarely better.

### 6. Pick indicators

Read [references/indicator-design.md](references/indicator-design.md). Required minimum:
- At least one indicator per applicable golden signal (latency, traffic, errors, saturation) on each affected service.
- At least one **intended-effect** indicator (the thing this change is *supposed* to move). Mark its `direction` as `intended-up` or `intended-down`.
- At least one **business-outcome** indicator if one exists for the affected surface. If you can't infer one, ask the user (see step 10).

For each indicator capture:
- `name` — short, kebab-case.
- `kind` — `ratio` (preferred — good_events / total_events) or `gauge` (only when no honest denominator exists, e.g. queue depth, p95 latency value).
- `source` — exact query string for the primary telemetry tool (`Datadog:query_metrics` payload, Prom expression, Honeycomb breakdown, etc.).
- `direction` — `intended-up | intended-down | unintended-watch`.
- `per-env vs shared` — if the indicator is identical across envs (golden signals on the same service, with `service:my-svc` filter), mark *shared, applies to all*. If it differs (e.g. business KPI is region-specific), nest under the env. See [references/multi-env.md](references/multi-env.md).

### 7. Query the 24h baseline per env per indicator

Run each indicator's query right now against the last 24 hours, per environment. Capture the actual value (e.g. *baseline 0.18% over last 24h, p99 7.2 minutes ago*). The baseline value is what makes the threshold meaningful.

If the telemetry tool is unreachable for an indicator, flag it as `baseline-pending` rather than dropping the indicator silently — the executor will treat a missing baseline as `INCONCLUSIVE` and the user can fill it in before the executor runs.

Then express the threshold *relative to the baseline*, not as an absolute number:
- *"+30% vs baseline over a 5-minute window"* — good.
- *"alert at >1% error rate"* — bad (no context for what's normal).

### 8. Pick the deploy-detection recipe per env

Read the matching `references/<deploy-system>.md`. Copy the exact poll command into the plan's `Deploy detection` block for that environment. The command must:
- Take no interactive input.
- Print machine-parseable output (JSON or a single-line key=value).
- Match on the merge SHA (or its ancestor — see ArgoCD / canary recipes).

If the user uses multiple deploy systems (e.g. GH Actions for staging, ArgoCD for prod), give each environment its own command.

### 9. Pick the rollback hint

One line. Specific. The exact thing the user (or their on-call) will do if the executor reports `ISSUE_DETECTED`. Examples:
- *"Revert PR #1234 and redeploy via GH Actions deploy.yml."*
- *"Roll back ArgoCD app `my-svc-prod` to revision `abc123` (the previous synced rev)."*
- *"Flip feature flag `new-checkout-flow` to off in LaunchDarkly."*

This is the MTTR lever. Do not skip it. If you genuinely cannot infer one, ask the user (step 10) — never write a vague rollback hint.

### 10. Ask the user about ambiguities

Use [assets/ambiguity-questions.md](assets/ambiguity-questions.md) for the canonical wording. Hard rule: never proceed past step 10 on a `high`-tier change with unresolved ambiguity. Common ambiguities:
- *"Multiple telemetry tools are available — which is canonical for service X?"* (only ask if the priority order from step 4 was inconclusive.)
- *"What counts as a 'good' request — 2xx only, or 2xx+3xx? Should auth-required 401s count?"*
- *"Is this change behind a feature flag? If so, what fraction is the rollout?"*
- *"What's the rollback procedure?"* (only if you couldn't infer it.)
- *"Default monitoring window for this tier is N — increase or decrease?"*

### 11. Render the plan section + companion check

Run `bash plan-change-control/scripts/render_plan_section.sh` with the gathered fields and the template at [assets/monitoring-plan-template.md](assets/monitoring-plan-template.md). Append the result to the plan file (or to the user's draft response if there is no plan file).

Then run `bash plan-change-control/scripts/check_companion.sh`. If `execute-change-control` is not installed, print its install hint verbatim. The plan is useless without the executor.

End the section with the activation hand-off line:

```
After the change merges and the deploy is triggered, run:
  /execute-change-control <path-to-this-plan-file>
in this same session to monitor it.
```

## Worked examples

- [examples/low-risk-bugfix.md](../examples/low-risk-bugfix.md) — single-env, two early checkpoints.
- [examples/medium-risk-api-change.md](../examples/medium-risk-api-change.md) — staging + prod, golden signals + intended-effect.
- [examples/high-risk-db-migration.md](../examples/high-risk-db-migration.md) — staging + prod, full schedule including +24h and +72h.
- [examples/high-risk-infra-change.md](../examples/high-risk-infra-change.md) — infra, full schedule.
- [examples/multi-region-rollout.md](../examples/multi-region-rollout.md) — four regions fanned out via ArgoCD `ApplicationSet`.

## Limits

If the user asks one of these limit-questions, read [references/limitations.md](references/limitations.md):
- "Can this run while I'm offline / when my session ends?"
- "How does my team see what's being monitored?"
- "Can it learn from past deploys?"
- "Can I auto-rollback?"
- "Why can't I fix two regressions in parallel?"

## What this skill does NOT do

- Does not run the monitoring itself — that's `execute-change-control`.
- Does not promise to detect every possible regression. The plan is anchored on *this* change's failure modes.
- Does not write generic "monitor everything" plans. Generic alerting is upstream of change control.
- Does not file issues or modify CI. The plan is a markdown section the executor reads.
