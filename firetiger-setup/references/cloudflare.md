# Cloudflare Workers observability

Send Cloudflare Workers traces and logs to Firetiger via Workers observability destinations. Uses the Step 1
credentials: `$INGEST_URL`, `$AUTH_HEADER` = `base64(username:password)`. Requires `which wrangler`.

## Prerequisites

- Account ID (`$ACCOUNT_ID`) and API credentials (`$CF_EMAIL`, `$CF_API_KEY`) — try `wrangler whoami`, or ask
  the user.

## Create the destinations

```bash
# Traces
curl -X POST "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/observability/destinations" \
  -H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_API_KEY" -H "Content-Type: application/json" \
  -d '{"name":"firetiger-traces","enabled":true,"configuration":{"type":"logpush",
       "logpushDataset":"opentelemetry-traces","url":"'$INGEST_URL'/v1/traces",
       "headers":{"Authorization":"Basic '$AUTH_HEADER'"}}}'

# Logs
curl -X POST "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/observability/destinations" \
  -H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_API_KEY" -H "Content-Type: application/json" \
  -d '{"name":"firetiger-logs","enabled":true,"configuration":{"type":"logpush",
       "logpushDataset":"opentelemetry-logs","url":"'$INGEST_URL'/v1/logs",
       "headers":{"Authorization":"Basic '$AUTH_HEADER'"}}}'
```

## Enable observability in `wrangler.toml`

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

Then deploy:

```bash
wrangler deploy
```
