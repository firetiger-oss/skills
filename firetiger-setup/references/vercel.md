# Vercel log & trace drains

Forward Vercel logs and traces to Firetiger via the Vercel API. Uses the Step 1 credentials: `$INGEST_URL`,
and `$AUTH_HEADER` = `base64(username:password)`.

## Prerequisites

- `which vercel` succeeds.
- A Vercel token (check `vercel whoami`, or ask the user for one).

## Find the project and team

```bash
curl -H "Authorization: Bearer $TOKEN" "https://api.vercel.com/v9/projects"
```

Grab the `$PROJECT_ID` for the project being onboarded.

## Create the logs drain

```bash
curl -X POST "https://api.vercel.com/v1/drains" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"Send logs to Firetiger","projects":"some","projectIds":["'$PROJECT_ID'"],
       "schemas":{"log":{"version":"v1"}},
       "delivery":{"type":"http","endpoint":"'$INGEST_URL'/vercel/logs","encoding":"json",
                   "headers":{"Authorization":"Basic '$AUTH_HEADER'"}},
       "filter":{"version":"v2","filter":{"type":"basic","log":{"sources":["lambda","edge"]},
                 "deployment":{"environments":["production"]}}}}'
```

## Create the traces drain

```bash
curl -X POST "https://api.vercel.com/v1/drains" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"Send traces to Firetiger","projects":"some","projectIds":["'$PROJECT_ID'"],
       "schemas":{"trace":{"version":"v1"}},
       "delivery":{"type":"otlphttp","endpoint":{"traces":"'$INGEST_URL'/v1/traces"},"encoding":"json",
                   "headers":{"Authorization":"Basic '$AUTH_HEADER'"}}}'
```

The logs drain targets production `lambda` and `edge` sources; adjust the `filter` block to include other
environments or sources as needed.
