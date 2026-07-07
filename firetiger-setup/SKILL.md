---
name: firetiger-setup
description: >
  Use when onboarding a project to Firetiger end-to-end — authenticate, subscribe,
  detect the stack, wire telemetry from any source (OTLP SDK, platform log/trace
  drains, Datadog Agent, Prometheus, Vector, or a generic HTTP sink), connect
  integrations (GitHub, Slack, databases, cloud, observability backends), register
  deployments, let discovery map services, and create a monitoring agent. Always use
  this skill for first-time setup — it carries the gotchas (credentials auto-provision,
  Basic-auth ingest, connect GitHub + telemetry to unlock discovery) that finish
  onboarding in one pass.
license: Apache-2.0
user_invocable: true
user_invocable_description: "Set up Firetiger for this project — detect the stack, wire telemetry, connect integrations, create a monitoring agent"
metadata:
  author: firetiger
  version: "1.1.0"
  homepage: https://firetiger.com
  source: https://github.com/firetiger-oss/skills
references:
  - references/ingest-sources.md
  - references/connections.md
  - references/vercel.md
  - references/aws.md
  - references/gcp.md
  - references/cloudflare.md
  - references/datadog.md
---

# Firetiger Setup

Onboard this project to Firetiger with **minimal user interaction**: subscribe, wire up telemetry, connect
integrations, register deployments, let discovery map the system, and create a monitoring agent. Make changes
automatically; pause only when genuinely uncertain. Firetiger also ships two built-in MCP **prompts** —
`onboard-firetiger` (this whole flow) and `integrate-firetiger` (SDK instrumentation) — that mirror these steps.

## Step 1 — Authenticate & provision

Call **`get_ingest_credentials`**. It auto-provisions the org backend (credentials, storage) if needed and
returns the OTLP endpoint + username/password. If the MCP tools aren't available, tell the user to connect the
Firetiger MCP server (`https://api.cloud.firetiger.com/mcp/v1`) and sign in (Claude Code: `/mcp` → Firetiger →
sign in), then retry. Build the Basic auth header as `base64(username:password)` for Step 3.

## Step 2 — Subscribe

Check **`get_subscription_status`**:
- `active` / `trialing` → continue.
- `none` / `canceled` / `past_due` → call **`get_checkout_url`** (plan `bootstrap` is the free tier; `growth`
  is paid), open it for the user, and wait for them to finish before continuing.

(These tools appear only on deployments with billing enabled; skip this step if they're absent.)

## Step 3 — Detect the stack

Explore the codebase to find telemetry sources and services Firetiger can connect to:

- **Deployment platforms** (log/trace drains): Vercel, Cloudflare, AWS, GCP.
- **Telemetry sources**: OpenTelemetry (`@opentelemetry/*`, `opentelemetry-*`, `go.opentelemetry.io`), Datadog
  (`dd-trace`, `datadog`), Prometheus (`prometheus.yml`), Vector (`vector.toml`).
- **Databases**: PostgreSQL / MySQL (Prisma, SQLAlchemy, connection strings), ClickHouse, Trino, Elasticsearch.
- **Event & incident sources**: GitHub (`.git/config`), SendGrid, Convex, Kafka, incident.io, PagerDuty.
- **Language/framework** (for OTEL auto-instrumentation): `package.json` → Node.js; `requirements.txt` /
  `pyproject.toml` → Python; `go.mod` → Go.

## Step 4 — Wire up telemetry ingestion

Pick the path that matches what you detected. All ingest is **HTTP Basic auth** using the Step 1 credentials
(`$INGEST_URL`, `$USERNAME`, `$PASSWORD`, `$AUTH_HEADER = base64(user:pass)`). The full source menu — with
endpoint paths — is in **[references/ingest-sources.md](references/ingest-sources.md)**.

| Detected | Recipe |
|----------|--------|
| Vercel | [references/vercel.md](references/vercel.md) — log + trace drains via the Vercel API |
| AWS (`which aws`) | [references/aws.md](references/aws.md) — CloudWatch/ALB/CloudFront/ECS via CloudFormation + Firehose |
| GCP (`which gcloud`) | [references/gcp.md](references/gcp.md) — Cloud Logging sink → Pub/Sub → forwarder, or HTTP push |
| Cloudflare (`which wrangler`) | [references/cloudflare.md](references/cloudflare.md) — Workers observability + Logpush |
| Datadog Agent already deployed | [references/datadog.md](references/datadog.md) — repoint `DD_URL` at Firetiger (logs+metrics+traces) |
| Prometheus / Vector / generic HTTP | [references/ingest-sources.md](references/ingest-sources.md) — `remote_write`, Vector sink, `/datapoints/` |
| None of the above | Hand off to **`firetiger-instrument`** — OTLP SDK for Node/Next.js/Python/Go/Rust |

## Step 5 — Connect integrations

Integrations are **Connections** — how agents read from and act on external systems. The full catalog and the
connect mechanism (OAuth via `onboard_*`, API key / IAM, private-network transports) is in
**[references/connections.md](references/connections.md)**.

- **GitHub first** — it's required for deploy monitoring *and* discovery. Use `onboard_github` (or `create` on
  `connections`); the OAuth flow opens a browser.
- **Proactively connect** what you detected: databases (Postgres/MySQL/ClickHouse/Trino/Elasticsearch),
  cloud (AWS/GCP), observability backends (Datadog/PromQL), Vercel/Cloudflare.
- **Ask once about the rest:** "Which do you use? Slack, Linear, PagerDuty, incident.io" — then connect them
  (`onboard_slack`, `onboard_linear`, or `create` on `connections`).
- **Private databases** need a NetworkTransport (Tailscale) — see the reference.
- **Warn about gaps.** No integrations → the agent can monitor and analyze but can't act (Slack alerts, GitHub
  issues). Note specifics: no Slack → no alerts; no GitHub → no codebase search, no deploy tracking, no discovery.

## Step 6 — Register deployments

Call **`get_deploy_credentials`** and wire a CI/CD step that POSTs deploy events (`repository`, `environment`,
`sha`) to the returned endpoint with Basic auth, so monitors verify each release. Details in
`firetiger-monitor-deploy`.

## Step 7 — Let discovery run

Once **GitHub + a telemetry/query source** are connected (the "qualifying" pair), Firetiger auto-discovers
**Services** (the customer's own software boundaries) and **Providers** (external dependencies — Postgres,
Vercel, OpenAI, etc.) by triangulating connections, OTEL signals, and the connected repos, and recommends what
to monitor. You don't build this by hand — connecting the qualifying pair unlocks it.

## Step 8 — Create a monitoring agent

Use **`create_agent_with_goal`** with a goal tailored to the stack (or install a prebuilt catalog agent — see
`firetiger-create-agent`):

- **Next.js/React:** "Monitor this Next.js app for API route errors, slow page loads, and DB query issues.
  Alert on error-rate spikes and p95 latency increases."
- **Python API:** "Monitor this Python API for request errors, slow endpoints, and exception patterns. Track
  DB performance and alert on anomalies."
- **Go service:** "Monitor this Go service for errors, goroutine issues, and latency; alert on degradation."

If the planner asks a question, answer from what you detected via `send_agent_message` on the plan session.

## Step 9 — Summary

Show: files changed, env vars needed in prod, connections configured, telemetry sources wired, deploys
registered, the agent created and its focus, discovered services/providers, and a dashboard link.

## Common Mistakes

| # | Mistake | Fix |
|---|---------|-----|
| 1 | **Only considering the OTLP SDK** | Datadog Agent, Prometheus `remote_write`, Vector, platform drains, and `/datapoints/` are all first-class — match the source you actually have. |
| 2 | **Skipping GitHub** | GitHub is required for deploy monitoring and to unlock discovery — connect it early. |
| 3 | **Bearer auth on ingest/drains** | Everything ingest-side is HTTP Basic auth (`base64(user:pass)`). |
| 4 | **Creating the agent before connecting integrations** | Connect first, or the agent can't act (alerts, issues). |
| 5 | **Hand-hardcoding auth for query connections** | Connection credentials are proxy-injected by host — reference the connection, don't set `Authorization` yourself. |
| 6 | **Expecting discovery with only telemetry** | Discovery needs the qualifying pair: GitHub + a telemetry/query source. |
| 7 | **Committing credentials** | Add credential/env files to `.gitignore`; use platform secret stores in CI. |

## Related

- OTLP SDK instrumentation: `firetiger-instrument`.
- Deploy monitoring & the deployments API: `firetiger-monitor-deploy`.
- Agent & catalog configuration: `firetiger-create-agent`.
- Firetiger integration docs: <https://docs.firetiger.com>.
