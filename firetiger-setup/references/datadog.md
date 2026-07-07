# Datadog Agent forwarding

If the project already runs the **Datadog Agent**, you can forward logs, metrics, and traces to Firetiger with
almost no code change by repointing the agent at Firetiger's Datadog-compatible ingest. This is the fastest
migration path off Datadog. Uses the Step 1 credentials.

Firetiger accepts Datadog-agent traffic on these endpoints (`$INGEST_URL` host):

| Signal | Endpoint(s) |
|--------|-------------|
| Logs | `/datadog/logs` |
| Metrics | `/datadog/api/v1/series`, `/datadog/api/v2/series` |
| Traces | `/datadog/api/v0.2/traces`, `/datadog/api/v0.7/traces` |

Authentication accepts the Datadog **`DD-API-KEY`** header (use the Firetiger-issued key) as well as HTTP Basic
auth. Discovery/validation endpoints (`/datadog/info`, `/datadog/api/v1/validate`) are public.

## Repoint the agent

Set the base URL (and API key) in `datadog.yaml` or via environment:

```yaml
# datadog.yaml
dd_url: "https://<ingest-host>/datadog"        # metrics
logs_config:
  logs_dd_url: "<ingest-host>:443"
  use_http: true
apm_config:
  apm_dd_url: "https://<ingest-host>/datadog"  # traces
api_key: "<firetiger-issued-key>"
```

Or with environment variables:

```bash
DD_DD_URL="https://<ingest-host>/datadog"
DD_APM_DD_URL="https://<ingest-host>/datadog"
DD_LOGS_CONFIG_LOGS_DD_URL="<ingest-host>:443"
DD_API_KEY="<firetiger-issued-key>"
```

## Dual-shipping

To validate before cutting over, run both backends in parallel (Datadog + Firetiger) using the agent's
multi-destination config, compare the data in Firetiger with `firetiger-query`, then remove the Datadog
destination once confident.

## Query-side connection (optional)

Separately from *forwarding*, you can add a `DATADOG` **Connection** (API key) so Firetiger's agents can query
your existing Datadog data and analyze Datadog cost during the migration — see
[connections.md](connections.md).
