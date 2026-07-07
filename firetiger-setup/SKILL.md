---
name: firetiger-setup
description: "Onboard a project to Firetiger end-to-end with minimal user interaction: authenticate, provision, detect the stack, set up telemetry (OTEL SDK or platform log/trace drains for Vercel/AWS/GCP/Cloudflare), connect integrations, register deployments, and create a monitoring agent. Use when the user wants to set up Firetiger, onboard a project, or connect their app to Firetiger for the first time."
user_invocable: true
user_invocable_description: "Set up Firetiger for this project — detect the stack, instrument, connect integrations, create a monitoring agent"
---

# Firetiger Setup

You are setting up Firetiger observability for this project. Goal: **minimal user interaction** — detect the
stack, instrument the code, connect integrations, register deployments, and create a monitoring agent, asking
the user only when genuinely necessary.

## Step 1: Authenticate

Check whether the Firetiger MCP tools are available by calling **`get_ingest_credentials`**.

If the tools are NOT available (error about tools not loaded, or the tool doesn't exist), tell the user to
connect the Firetiger MCP server and sign in:

```
Firetiger needs authentication. Please connect the Firetiger MCP server
(https://api.cloud.firetiger.com/mcp/v1) and sign in / create an account in the
browser window, then let me know when you're done.
```

In Claude Code, that's `/mcp` → select the Firetiger server → sign in. When the user is done, retry
`get_ingest_credentials`.

## Step 2: Provision

`get_ingest_credentials` auto-provisions the org's backend (credentials, data storage) if it isn't set up
yet, and returns the OTLP ingest endpoint plus username/password. Keep these for Step 5.

## Step 3: Detect the stack

Explore the codebase to identify telemetry sources and services Firetiger can connect to.

**Deployment platforms (log/trace drains)**
- **Vercel**: `vercel.json`, `.vercel/`
- **Cloudflare**: `wrangler.toml`
- **AWS**: CloudFormation/CDK/Terraform — CloudWatch, ALB, CloudFront, EventBridge logs
- **GCP**: Cloud Logging

**Telemetry sources**
- **OpenTelemetry**: `@opentelemetry/*`, `opentelemetry-*` (Python), `go.opentelemetry.io`
- **Datadog**: `dd-trace`, `datadog`
- **Prometheus**: `prometheus.yml`, Grafana configs
- **Vector**: `vector.toml`

**Databases (direct query)**: PostgreSQL / MySQL (Prisma, SQLAlchemy, connection strings), ClickHouse.

**Event & incident sources**: GitHub (`.git/config`), SendGrid, Kafka, Incident.io, PagerDuty.

**Language/framework (for OTEL auto-instrumentation)**: `package.json` → Node.js (Next.js, Express);
`requirements.txt` / `pyproject.toml` → Python; `go.mod` → Go.

## Step 4: Connect integrations

Integrations are the `connections` collection. Inspect the shape first with `schema` (collection:
`connections`), then use `list` / `create`. OAuth connections open a browser window.

**Proactively connect** what you detected in Step 3 (the user can decline): GitHub (if the git remote points
to github.com), PostgreSQL/MySQL/ClickHouse, AWS/GCP, Datadog/Prometheus, Vercel/Cloudflare.

**Ask once about the rest:** "Which of these do you use? (select all that apply): Slack, Linear, PagerDuty,
Incident.io" — then connect the selected ones.

**Warn about gaps** after attempting connections:
> "No integrations connected. Your agent can monitor and analyze the app, but can't take actions like sending
> Slack alerts or opening GitHub issues. You can add connections later from the Firetiger dashboard."

If only some were skipped, note what's missing — e.g. no Slack → no real-time alerts; no GitHub → can't
search the codebase or track deployments.

## Step 5: Set up telemetry

Use the credentials from Step 2. Prefer the deployment platform's native drain; fall back to the OTEL SDK.
Build the Basic auth header as `base64(username:password)` and reference it as `$AUTH_HEADER` below.

### Vercel
If `which vercel` succeeds, create log and trace drains via the Vercel API (needs a Vercel token; try
`vercel whoami`). List projects with
`curl -H "Authorization: Bearer $TOKEN" "https://api.vercel.com/v9/projects"`, then:

```bash
# Logs drain
curl -X POST "https://api.vercel.com/v1/drains" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"Send logs to Firetiger","projects":"some","projectIds":["'$PROJECT_ID'"],
       "schemas":{"log":{"version":"v1"}},
       "delivery":{"type":"http","endpoint":"'$INGEST_URL'/vercel/logs","encoding":"json",
                   "headers":{"Authorization":"Basic '$AUTH_HEADER'"}},
       "filter":{"version":"v2","filter":{"type":"basic","log":{"sources":["lambda","edge"]},
                 "deployment":{"environments":["production"]}}}}'

# Traces drain
curl -X POST "https://api.vercel.com/v1/drains" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"Send traces to Firetiger","projects":"some","projectIds":["'$PROJECT_ID'"],
       "schemas":{"trace":{"version":"v1"}},
       "delivery":{"type":"otlphttp","endpoint":{"traces":"'$INGEST_URL'/v1/traces"},"encoding":"json",
                   "headers":{"Authorization":"Basic '$AUTH_HEADER'"}}}'
```

### AWS CloudWatch
If `which aws` succeeds, deploy the onboarding CloudFormation stack:
```bash
aws cloudformation create-stack \
  --stack-name firetiger-cloudwatch-logs \
  --template-url https://firetiger-public-$REGION.s3.$REGION.amazonaws.com/ingest/aws/cloudwatch/logs/ingest-and-iam-onboarding.yaml \
  --parameters \
    ParameterKey=FiretigerEndpoint,ParameterValue=$INGEST_URL \
    ParameterKey=FiretigerUsername,ParameterValue=$USERNAME \
    ParameterKey=FiretigerPassword,ParameterValue=$PASSWORD \
    ParameterKey=FiretigerExternalId,ParameterValue=$(uuidgen) \
  --capabilities CAPABILITY_NAMED_IAM --region $REGION
# then: aws cloudformation describe-stacks --stack-name firetiger-cloudwatch-logs --query 'Stacks[0].Outputs'
```

### GCP Cloud Logging
If `which gcloud` succeeds:
```bash
PROJECT=$(gcloud config get-value project)
gcloud services enable cloudfunctions.googleapis.com pubsub.googleapis.com logging.googleapis.com \
  run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com eventarc.googleapis.com
gcloud pubsub topics create firetiger-cloud-logs
gcloud logging sinks create firetiger-cloud-logs pubsub.googleapis.com/projects/$PROJECT/topics/firetiger-cloud-logs
SINK_SA=$(gcloud logging sinks describe firetiger-cloud-logs --format='value(writerIdentity)')
gcloud pubsub topics add-iam-policy-binding firetiger-cloud-logs --member="$SINK_SA" --role="roles/pubsub.publisher"
gcloud functions deploy firetiger-cloud-logs-forwarder --gen2 --runtime=python313 \
  --trigger-topic=firetiger-cloud-logs --entry-point=process_log_entry \
  --set-env-vars="FT_EXPORTER_ENDPOINT=$INGEST_URL,FT_EXPORTER_BASIC_AUTH_USERNAME=$USERNAME,FT_EXPORTER_BASIC_AUTH_PASSWORD=$PASSWORD" \
  --source=gs://firetiger-public/ingest/gcp/cloud-logging/function.zip --region=$REGION
```

### Cloudflare Workers
If `which wrangler` succeeds, create observability destinations via the Cloudflare API and enable them in
`wrangler.toml`:
```bash
curl -X POST "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/observability/destinations" \
  -H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_API_KEY" -H "Content-Type: application/json" \
  -d '{"name":"firetiger-traces","enabled":true,"configuration":{"type":"logpush",
       "logpushDataset":"opentelemetry-traces","url":"'$INGEST_URL'/v1/traces",
       "headers":{"Authorization":"Basic '$AUTH_HEADER'"}}}'
# repeat with name "firetiger-logs" / dataset "opentelemetry-logs" / url $INGEST_URL/v1/logs
```
```toml
[observability.traces]
enabled = true
head_sampling_rate = 1.0
destinations = ["firetiger-traces"]

[observability.logs]
enabled = true
head_sampling_rate = 1.0
destinations = ["firetiger-logs"]
```
Then `wrangler deploy`.

### OpenTelemetry SDK (fallback)
If no deployment-platform CLI is available, instrument the code directly. Hand off to the
`firetiger-instrument` skill, which covers Node.js/Next.js, Python, Go, and Rust with the exporter pointed at
the Firetiger ingest credentials.

## Step 6: Register deployments (optional but recommended)

So monitors can verify each release, call **`get_deploy_credentials`** and wire a CI/CD step that POSTs a
deployment event (commit SHA, environment, version) to the returned endpoint using Basic auth. See
`firetiger-monitor-deploy` for details.

## Step 7: Create a monitoring agent

Use **`create_agent_with_goal`** with a goal tailored to the detected stack:

- **Next.js/React**: "Monitor this Next.js application for API route errors, slow page loads, and database
  query issues. Alert on error-rate spikes and p95 latency increases."
- **Python API**: "Monitor this Python API for request errors, slow endpoints, and exception patterns. Track
  database query performance and alert on anomalies."
- **Go service**: "Monitor this Go service for errors, goroutine issues, and latency problems. Track memory
  usage patterns and alert on degradation."

If the planner asks a question, answer on the user's behalf from what you detected, replying with
`send_agent_message` on the returned plan `session`. See `firetiger-create-agent` for the full flow.

## Step 8: Summary

Show the user:
1. Changes made (files modified).
2. Environment variables needed in production.
3. Connections configured (GitHub, Slack, …).
4. The agent created and its monitoring focus.
5. A link to the Firetiger dashboard.
6. Next steps (install deps, deploy, register deployments).

## Notes

- **Make changes automatically** — only ask when genuinely uncertain.
- **Never commit credentials** — add credential files to `.gitignore`.
- **Prefer environment variables** — use OTEL standard env vars.
- **Show diffs** — let the user review before saving.
- **Detect existing setup** — don't duplicate instrumentation already present.
- **Connections are optional** — don't block on connection failures.
