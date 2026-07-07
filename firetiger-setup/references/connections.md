# Connections, providers & discovery

A **Connection** is a configured integration Firetiger reaches an external system through — to query data, take
actions, or receive events. Connections are the `connections` MCP collection.

## Connect mechanism

Three ways, by connection kind:

- **OAuth** (GitHub, Slack, Linear): use the MCP tools `onboard_github`, `onboard_slack`, `onboard_linear` —
  each returns an authorization URL that opens a browser. (These tools appear for users who haven't yet
  connected that provider.)
- **API key / token** (Datadog, PagerDuty, incident.io, Vanta, Pylon, Google Postmaster): `schema` then
  `create` on the `connections` collection with the credential, or complete it in the Firetiger dashboard.
- **IAM role / SigV4** (AWS), **service account** (GCP): cloud-provider trust setup.

**Key gotcha:** for query/action connections, credentials are **injected by a host-keyed egress proxy**. Once a
connection exists, an agent's plain request to that host gets auth added automatically — never hand-set an
`Authorization` header for a connected service, and never paste the secret into a command.

## Connection catalog

**Databases / query engines** — Firetiger's agents query *through* these:
`POSTGRES` (incl. Supabase, Neon, RDS), `MYSQL` (incl. MariaDB, RDS), `CLICKHOUSE`, `TRINO` (incl. Starburst),
`ELASTICSEARCH`, `ICEBERG` (Firetiger's own lake, the `iceberg-gateway` virtual connection).

**Observability / metrics backends:** `DATADOG` (also a forwarding source), `PROMQL` (Prometheus/Thanos/Mimir),
`GCP` Cloud Monitoring.

**Cloud providers:** `AWS` (IAM role; tested via STS GetCallerIdentity), `GCP` (service account).

**Dev-tools / SaaS:** `GITHUB`, `SLACK`, `LINEAR`, `PAGERDUTY`, `INCIDENT_IO`, `PYLON`, `VANTA`, `CLERK`,
`WORKOS`, `GOOGLE_POSTMASTER` (Gmail deliverability), `CONVEX`.

**Generic protocols (custom):** `HTTP`, `OPENAPI`, `GRPC` (server reflection), `GRAPHQL`, `EMAIL_WEBHOOK`
(inbound), `WEB_SEARCH`.

**Coding-agent launchers** (hand off issue fixes): `CURSOR`, `INSPECT`, `TEMBO`, `REPLICAS`, `CODER`.

## What each unlocks

- **GitHub** — deploy monitoring (`@firetiger`), codebase search, issue/PR actions, and (with telemetry) the
  discovery sweep. This is the highest-leverage connection.
- **Slack** — real-time alerts, PR-author DMs, and mention-triggered agents.
- **Databases / observability backends** — let agents query production data and existing metrics directly
  during investigations.
- **PagerDuty / incident.io / Linear** — let agents open and manage incidents/tickets.

## Private networks (NetworkTransports)

A Connection whose target isn't publicly reachable references a **NetworkTransport** — currently **Tailscale**
(OAuth client credentials). The egress proxy joins the tailnet on demand and tunnels to the private host. The
transport's route `domain` must match the target host exactly, or via a `*.prefix` wildcard. Required for any
database or service on a private network.

## Providers & discovery

- A **Provider** is an external dependency the customer's software relies on (the sibling of a **Service**, the
  customer's own boundary). Provider types include `AWS`, `GCP`, `VERCEL`, `SUPABASE`, `POSTGRES`, `MYSQL`,
  `CLICKHOUSE`, `ELASTICSEARCH`, `TEMPORAL`, `ANTHROPIC`, `OPENAI`, `TOGETHER_AI`.
- **Discovery** auto-detects what a customer uses by triangulating three signals: existing Connections, OTEL
  telemetry signatures (`db.system`, `rpc.system`, `cloud.provider`, outbound host addresses), and a scan of
  connected GitHub repos (SDK imports, DSNs, env vars). It recommends only providers Firetiger can actually
  connect to and monitor.
- **The qualifying pair:** the discovery sweep runs for an org only once it has a healthy **GitHub** connection
  **and** a healthy **telemetry/query** connection (or data landing via OTLP). Connecting both is what turns on
  automated Service/Provider cataloging — make it an explicit onboarding goal.

See <https://docs.firetiger.com> for per-integration setup detail.
