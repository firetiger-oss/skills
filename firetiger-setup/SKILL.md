---
name: firetiger-setup
description: >
  Use when onboarding a project to Firetiger end-to-end — authenticate, provision,
  detect the stack, wire up telemetry (OTEL SDK or a platform log/trace drain for
  Vercel/AWS/GCP/Cloudflare), connect integrations, register deployments, and create
  a monitoring agent, with minimal user interaction. Always use this skill for
  first-time Firetiger setup — it carries the critical gotchas (credentials from
  get_ingest_credentials auto-provision the backend, Basic-auth drains, connect
  integrations before creating the agent) so onboarding completes in one pass.
license: Apache-2.0
user_invocable: true
user_invocable_description: "Set up Firetiger for this project — detect the stack, instrument, connect integrations, create a monitoring agent"
metadata:
  author: firetiger
  version: "1.0.0"
  homepage: https://firetiger.com
  source: https://github.com/firetiger-oss/skills
references:
  - references/vercel.md
  - references/aws.md
  - references/gcp.md
  - references/cloudflare.md
---

# Firetiger Setup

Onboard this project to Firetiger with **minimal user interaction**: detect the stack, wire up telemetry,
connect integrations, register deployments, and create a monitoring agent — asking the user only when
genuinely necessary. Make changes automatically; only pause for confirmation when you're actually uncertain.

## Step 1 — Authenticate & provision

Call **`get_ingest_credentials`**. This one call does double duty: it auto-provisions the org's backend
(credentials, data storage) if needed, and returns the OTLP ingest endpoint plus username/password.

If the MCP tools aren't available (error about tools not loaded / tool doesn't exist), tell the user:

> Firetiger needs authentication. Connect the Firetiger MCP server
> (`https://api.cloud.firetiger.com/mcp/v1`) and sign in / create an account in the browser, then let me
> know. (In Claude Code: `/mcp` → select the Firetiger server → sign in.)

Retry `get_ingest_credentials` when they're done. Keep the returned endpoint, username, and password for
Step 3 — build the Basic auth header as `base64(username:password)`.

## Step 2 — Detect the stack

Explore the codebase to find telemetry sources and services Firetiger can connect to:

- **Deployment platforms** (log/trace drains): Vercel (`vercel.json`, `.vercel/`), Cloudflare
  (`wrangler.toml`), AWS (CloudFormation/CDK/Terraform), GCP (Cloud Logging).
- **Telemetry sources**: OpenTelemetry (`@opentelemetry/*`, `opentelemetry-*`, `go.opentelemetry.io`),
  Datadog (`dd-trace`), Prometheus (`prometheus.yml`), Vector (`vector.toml`).
- **Databases** (direct query): PostgreSQL / MySQL (Prisma, SQLAlchemy, connection strings), ClickHouse.
- **Event & incident sources**: GitHub (`.git/config`), SendGrid, Kafka, Incident.io, PagerDuty.
- **Language/framework** (for OTEL auto-instrumentation): `package.json` → Node.js; `requirements.txt` /
  `pyproject.toml` → Python; `go.mod` → Go.

## Step 3 — Set up telemetry

Prefer the deployment platform's native drain; fall back to the OTEL SDK. Each reference is a self-contained
recipe using the Step 1 credentials (`$INGEST_URL`, `$USERNAME`, `$PASSWORD`, `$AUTH_HEADER`).

| Detected platform | Recipe |
|-------------------|--------|
| Vercel (`which vercel`) | [references/vercel.md](references/vercel.md) — log + trace drains via the Vercel API |
| AWS (`which aws`) | [references/aws.md](references/aws.md) — CloudWatch logs via CloudFormation onboarding stack |
| GCP (`which gcloud`) | [references/gcp.md](references/gcp.md) — Cloud Logging sink + Pub/Sub + forwarder function |
| Cloudflare (`which wrangler`) | [references/cloudflare.md](references/cloudflare.md) — Workers observability destinations |
| None of the above | Hand off to **`firetiger-instrument`** — OTEL SDK for Node/Next.js/Python/Go/Rust |

## Step 4 — Connect integrations

Integrations are the `connections` collection. Inspect the shape with `schema` (collection: `connections`),
then use `list` / `create`. OAuth connections open a browser window.

- **Proactively connect** what you detected (the user can decline): GitHub (if the git remote is github.com),
  PostgreSQL/MySQL/ClickHouse, AWS/GCP, Datadog/Prometheus, Vercel/Cloudflare.
- **Ask once about the rest:** "Which of these do you use? (select all): Slack, Linear, PagerDuty,
  Incident.io" — then connect the selected ones.
- **Warn about gaps.** If nothing connected: "Your agent can monitor and analyze the app, but can't take
  actions like Slack alerts or GitHub issues — add connections later from the dashboard." Note specific gaps
  (no Slack → no real-time alerts; no GitHub → can't search the codebase or track deployments).

## Step 5 — Register deployments (recommended)

So monitors can verify each release, call **`get_deploy_credentials`** and wire a CI/CD step that POSTs a
deployment event (commit SHA, environment, version) to the returned endpoint using Basic auth. Details in
`firetiger-monitor-deploy`.

## Step 6 — Create a monitoring agent

Call **`create_agent_with_goal`** with a goal tailored to the detected stack:

- **Next.js/React:** "Monitor this Next.js application for API route errors, slow page loads, and database
  query issues. Alert on error-rate spikes and p95 latency increases."
- **Python API:** "Monitor this Python API for request errors, slow endpoints, and exception patterns. Track
  database query performance and alert on anomalies."
- **Go service:** "Monitor this Go service for errors, goroutine issues, and latency problems. Track memory
  usage patterns and alert on degradation."

If the planner asks a question, answer on the user's behalf from what you detected, replying with
`send_agent_message` on the returned plan `session`. See `firetiger-create-agent` for the full flow.

## Step 7 — Summary

Show the user: files changed, env vars needed in production, connections configured, the agent created and its
focus, a link to the Firetiger dashboard, and next steps (install deps, deploy, register deployments).

## Common Mistakes

| # | Mistake | Fix |
|---|---------|-----|
| 1 | **Waiting for a separate "provision" step** | `get_ingest_credentials` auto-provisions — there's no extra call. |
| 2 | **Bearer auth on drains** | Platform drains use HTTP Basic auth (`Authorization: Basic <base64(user:pass)>`). |
| 3 | **Creating the agent before connecting integrations** | Connect first, or the agent can't take actions (alerts, issues). |
| 4 | **Committing credentials** | Add credential/env files to `.gitignore`; use platform secret stores in CI. |
| 5 | **Duplicating existing instrumentation** | Detect existing OTEL setup and repoint it instead of adding a second SDK. |
| 6 | **Blocking on a failed connection** | Connections are optional — warn about the capability gap and continue. |

## Related

- OTEL SDK fallback for any language: `firetiger-instrument`.
- Deploy monitoring & the deployments API: `firetiger-monitor-deploy`.
- Agent configuration detail: `firetiger-create-agent`.
