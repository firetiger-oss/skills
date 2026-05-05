# Vercel telemetry (vercel-cli as primary source)

This file covers Vercel's own observability surfaces when the deploy target is hosted on Vercel — typically a static site, Next.js app, or serverless functions. Use these queries instead of (or alongside) general-purpose metrics backends, which usually don't have data for Vercel-hosted targets unless a log drain is wired up.

For deploy *detection* (waiting for the rollout to land), see [vercel.md](vercel.md). This file is about *telemetry queries* (indicator values during the monitoring window).

## Detection

Vercel CLI is available when `command -v vercel` succeeds AND `vercel whoami` returns a logged-in user. The repo doesn't need `.vercel/` or `vercel link` for these queries — the CLI works against the logged-in user's account scope.

Set `VERCEL_TOKEN` for non-interactive use; pass `--scope <team>` to scope to a specific team account.

## Indicator query patterns

Vercel exposes three classes of post-deploy data via the CLI: **deployment logs** (request/function-invocation logs), **deployment inspect** (build + runtime metadata), and **analytics** (Web Analytics + Speed Insights for static-site request data).

### Error rate from deployment logs

```
kind: ratio
source: shell
command: |
  ERRORS=$(vercel logs <deployment-url> --output raw --since 5m 2>&1 \
    | grep -c -E '\[(ERROR|FATAL)\]|status=5[0-9]{2}')
  TOTAL=$(vercel logs <deployment-url> --output raw --since 5m 2>&1 | wc -l)
  awk -v e=$ERRORS -v t=$TOTAL 'BEGIN{ if (t==0) print "0.0"; else printf "%.4f\n", e/t }'
threshold: > 0.01 (1% error rate) sustained 5m
```

Replace `<deployment-url>` with the deployment ID or URL captured at deploy detection. The `--since 5m` window gives a rolling 5-minute view.

### Function invocation count (traffic proxy)

```
kind: gauge
source: shell
command: |
  vercel logs <deployment-url> --output raw --since 5m 2>&1 \
    | grep -c -E '"method":\"(GET|POST|PUT|DELETE|PATCH)"'
baseline: capture at plan time via vercel logs --since 24h on prior deployment
```

### Status-code-class rates

```
kind: ratio
source: shell
command: |
  vercel logs <deployment-url> --output raw --since 5m 2>&1 \
    | awk '
      /status=2[0-9]{2}/ { ok++ }
      /status=[45][0-9]{2}/ { bad++ }
      END { if (ok+bad == 0) print 0; else printf "%.4f\n", bad/(ok+bad) }
    '
threshold: > 5× baseline sustained 5m
```

### Build / deploy duration (intended-effect for build-perf changes)

```
kind: gauge
source: shell
command: |
  vercel inspect <deployment-url> --json 2>/dev/null \
    | jq -r '(.ready - .createdAt) / 1000'
direction: intended-down (a perf improvement should reduce build time)
baseline: capture by running vercel inspect on previous N deploys, average
```

### Web Analytics / Speed Insights (static-site visitor data)

If the project has Vercel Web Analytics or Speed Insights enabled:

```
kind: gauge
source: shell
command: |
  vercel analytics query \
    --project <project-name> \
    --metric pageviews \
    --since 5m \
    --json 2>/dev/null | jq -r '.value'
```

The Vercel Analytics CLI surface evolves; check `vercel analytics --help` for the available metrics and scopes. For Speed Insights (Core Web Vitals like LCP, FID, CLS):

```
kind: gauge
source: shell
command: |
  vercel analytics query \
    --project <project-name> \
    --metric lcp_p75 \
    --since 5m \
    --json 2>/dev/null | jq -r '.value'
threshold: > baseline + 500ms sustained 30m
```

## Querying the 24-hour baseline

For log-derived indicators, use `vercel logs <deployment-url> --since 24h` and aggregate with the same shell pipeline. For analytics, `vercel analytics query --since 24h`. Capture per-env baselines in the plan's baseline block:

```
indicator: error-rate
baseline:
  production: 0.18%  (queried 2026-05-04T15:00Z, vercel logs --since 24h)
```

## Log drains: when Datadog / Axiom / Honeycomb actually have the data

If the team has configured a Vercel log drain (Vercel project settings → Integrations → Log Drains), the drained tool *does* have the deploy target's logs and is a valid primary source. The script can't auto-detect log-drain configuration — ask the user when ambiguous:

> "I see Datadog is available in your setup. Do you have a Vercel→Datadog log drain configured for `<project>`? If yes I'll query Datadog directly (better long-term retention + structured queries). If no, I'll use vercel-cli."

If the user confirms a drain, switch the source to the drain destination and use that source's reference ([datadog.md](datadog.md), [axiom.md](axiom.md), [honeycomb.md](honeycomb.md)).

## Common pitfalls

- **`vercel logs` without `--output raw` returns paginated, formatted output** with ANSI codes. Always pass `--output raw` (or `--output json`) for shell parsing.
- **`vercel logs` is rate-limited** (~100 req/min depending on plan). The 30s deploy-detection cadence is fine; running 10+ indicator queries every checkpoint may hit limits. Prefer batched single-query parsing (one `vercel logs` call producing multiple indicator values via awk) over per-indicator calls.
- **`vercel inspect`'s timing fields use milliseconds**, not seconds. The example above divides by 1000.
- **The `--scope` flag is required** if the user is in multiple teams — without it, the CLI may target the wrong account.
- **Function logs vs static asset logs.** Vercel separates these in the dashboard. `vercel logs` returns function/SSR logs; static asset requests (CDN-served) don't appear there. Use Web Analytics for static-asset request volume.
- **Speed Insights and Web Analytics need to be enabled** on the project (one-click in the dashboard) before `vercel analytics query` returns data.
