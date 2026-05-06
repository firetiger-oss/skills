# Telemetry-gap nudge

When `probe_telemetry_tools.sh` reports `TELEMETRY_GAP=yes`, the user has no telemetry backend visible from this session AND the deploy target is a backend service (where http-poll alone is thin — no error-rate / latency-tail / saturation visibility). Surface two escape hatches to the user before continuing.

## When to read this file

`plan-rollout` step 4 reads this file *only* when the probe script's output contains `TELEMETRY_GAP=yes`. Static-site targets (Vercel / Netlify / Cloudflare Pages) are not gaps — http-poll + the platform CLI is the right primary there.

## Decision tree

The probe script also reports push-only OTLP endpoints when present (`OTEL_EXPORTER_OTLP_ENDPOINT` set without a queryable Prometheus / Tempo / Loki). Use that signal to bias the suggestion:

| Signal | What it means | Escape hatch |
|--------|---------------|--------------|
| `# Push-only endpoints detected:` line lists `api.honeycomb.io` | User exports OTLP to Honeycomb but no MCP server is connected | **Connect Honeycomb MCP** (one command — no code change needed) |
| Push-only endpoint hostname matches `*.datadoghq.com` / `dd.datadoghq.eu` | User exports to Datadog | **Connect Datadog MCP** |
| Push-only endpoint matches `*.axiom.co` | User exports to Axiom | **Connect Axiom MCP** |
| Push-only endpoint generic (e.g. self-hosted collector at `localhost:4317`) | Telemetry is being emitted but destination unclear | Ask the user where it goes; suggest the matching MCP |
| **No** push-only endpoints, **no** OTel-shaped env vars, no `OTEL_*` references in code | User has no observability emission at all | **Instrument the code** — pivot to plan mode |
| Some hint of telemetry but unclear which vendor | — | Ask the user once: *"What telemetry vendor (if any) does this project send to?"* |

## Per-MCP install commands (curated)

Verify the canonical command at the time of suggestion (these change as vendors publish/update their MCPs). The shape is consistent across most coding-agent harnesses:

```sh
# Datadog
claude mcp add datadog "npx @datadog/mcp-server" --env DD_API_KEY=... --env DD_APP_KEY=...

# Honeycomb
claude mcp add honeycomb "npx @honeycombio/mcp-server" --env HONEYCOMB_API_KEY=...

# Axiom
claude mcp add axiom "npx @axiomhq/mcp-server" --env AXIOM_TOKEN=...

# Grafana stack (Tempo + Loki + Prometheus/Mimir)
claude mcp add grafana "npx @grafana/mcp-server" --env GRAFANA_URL=... --env GRAFANA_TOKEN=...

# Sentry (errors)
claude mcp add sentry "npx @sentry/mcp-server" --env SENTRY_AUTH_TOKEN=...

# PostHog (product analytics — useful for static sites that don't have request-level metrics)
claude mcp add posthog "npx @posthog/mcp-server" --env POSTHOG_API_KEY=...
```

If the install command above doesn't match the current published MCP, the user's coding-agent harness should have its own `mcp add` flow — point them at it and let the harness lead.

After the user installs, re-run `bash plan-rollout/scripts/probe_telemetry_tools.sh` to confirm the new source shows up; the planner then proceeds with the richer source as PRIMARY.

## Per-language instrumentation hints

For the "no telemetry exists at all" path, give the user one paragraph + one example per language so they can either run with it or extract it into a fuller plan-mode sub-task.

**Node / TypeScript** — Pino for structured logging + OpenTelemetry SDK for metrics + traces:
```js
// instrument.ts (loaded before the app)
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
new NodeSDK({
  traceExporter: new OTLPTraceExporter({ url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT }),
  instrumentations: [getNodeAutoInstrumentations()],
}).start();
// app.ts
import pino from 'pino';
export const log = pino({ level: process.env.LOG_LEVEL ?? 'info' });
```

**Go** — `log/slog` (stdlib) + OpenTelemetry SDK:
```go
import (
  "log/slog"
  "go.opentelemetry.io/otel"
  "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
  "go.opentelemetry.io/otel/sdk/trace"
)
func initTelemetry(ctx context.Context) (func(), error) {
  exp, err := otlptracehttp.New(ctx)
  if err != nil { return nil, err }
  tp := trace.NewTracerProvider(trace.WithBatcher(exp))
  otel.SetTracerProvider(tp)
  return func() { _ = tp.Shutdown(ctx) }, nil
}
slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
```

**Python** — `structlog` + OpenTelemetry SDK:
```python
import structlog
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
provider = TracerProvider()
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
trace.set_tracer_provider(provider)
log = structlog.get_logger()
```

**Rust** — `tracing` + `tracing-opentelemetry`:
```rust
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
let tracer = opentelemetry_otlp::new_pipeline().tracing()
    .with_exporter(opentelemetry_otlp::new_exporter().http())
    .install_batch(opentelemetry::runtime::Tokio)?;
tracing_subscriber::registry()
    .with(tracing_subscriber::fmt::layer().json())
    .with(tracing_opentelemetry::layer().with_tracer(tracer))
    .init();
```

These are starting points, not full guides. The plan-mode sub-task should fill in details specific to the user's framework (Express / Fastify, Gin / Echo, FastAPI / Flask, Axum / Actix).

## Plan-mode handoff seed (instrument the code)

When the user picks "instrument the code", call `EnterPlanMode` with this seed (substitute the user's language + framework):

```markdown
# Add observability to <project> before resuming /plan-rollout

The current rollout plan would have used HTTP probes only because no telemetry backend is reachable. Adding observability now will give future deploys a much richer signal (error-rate, latency-tail, saturation, custom business indicators).

## Scope

1. Pick a destination — OTLP endpoint or vendor MCP. Common picks: self-hosted Tempo+Loki+Prometheus, or Honeycomb / Datadog / Axiom (managed). Set `OTEL_EXPORTER_OTLP_ENDPOINT` in the deploy environment.
2. Add the OTel SDK + auto-instrumentation library for <language>. (See `plan-rollout/references/telemetry-gap.md` for one-paragraph starter snippets per language.)
3. Add structured logging (Pino / slog / structlog / tracing). Wire to stdout JSON for the deploy platform's log collector.
4. Add request-handler middleware that emits a span per request with `http.method`, `http.route`, `http.status_code`, `service.name`.
5. (Optional) Add 1–2 custom business metrics relevant to <project> — e.g. checkout-success-ratio, signup-rate.
6. Verify locally: hit a route, see a trace + log line.
7. Deploy. Confirm telemetry shows up at the destination.
8. Return to `/plan-rollout` for the rollout plan; re-run the probe and see the new source as PRIMARY.

## Out of scope

- Tuning sample rates / retention — defaults are fine for a first pass.
- Replacing existing logging frameworks if the project already has one — wrap, don't replace.
- Setting up SLOs in the vendor UI — separate work, after the SDK lands.
```

The user reviews this seed, edits as needed, and the agent works through the instrumentation as a normal coding task. No follow-up from `plan-rollout` until the user comes back.

## What to log when the user declines both escape hatches

If the user explicitly chooses to continue with `http-poll` only (or auto mode is active and skips the prompt), log this in the rendered monitoring plan section verbatim:

```
**Assumption:** no telemetry backend reachable; plan uses http-poll only — request-path indicators only, no error-rate / latency-tail / saturation visibility. Connect an MCP server or instrument the code to upgrade telemetry on the next deploy. See plan-rollout/references/telemetry-gap.md.
```

This makes the gap visible at execution time — the executor surfaces the same assumption when it emits status reports, so the user remembers why the plan is thin.
