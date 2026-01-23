# Troubleshooting

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| No data in Firetiger | Credentials invalid | Re-run `get_ingest_credentials` |
| No data in Firetiger | Instrumentation not loaded | Ensure import is first line in entry point |
| Connection refused | Network/firewall | Verify egress to ingest endpoint |
| Missing spans | Auto-instrumentation gaps | Add manual instrumentation |
| Duplicate spans | Multiple SDK initializations | Ensure init runs once |

## Debugging

### Enable Debug Logging

**Node.js:**
```bash
export OTEL_LOG_LEVEL=debug
```

**Python:**
```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

**Go:**
```go
import "go.opentelemetry.io/otel/sdk/trace"
tp := trace.NewTracerProvider(
    trace.WithSampler(trace.AlwaysSample()),
    // ...
)
```

**Rust:**
```bash
RUST_LOG=opentelemetry=debug cargo run
```

### Verify Connectivity

Test endpoint reachability:

```bash
curl -v -X POST "${OTEL_EXPORTER_OTLP_ENDPOINT}/v1/traces" \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic ${AUTH_HEADER}" \
  -d '{}'
```

Expected: 400 Bad Request (endpoint works, but empty payload rejected)

### Check Batching

Telemetry is batched before export. Default intervals:
- **Traces**: 5 seconds or 512 spans
- **Metrics**: 60 seconds
- **Logs**: 1 second or 512 records

For immediate export during debugging, reduce batch size or force flush:

**Node.js:**
```typescript
await sdk.shutdown(); // Forces flush
```

**Python:**
```python
_tracer_provider.force_flush()
```

**Go:**
```go
tp.ForceFlush(ctx)
```

## Framework-Specific Issues

### Next.js

- Instrumentation only runs on server components
- Client components don't emit traces
- Ensure `instrumentationHook: true` in next.config.js

### Django

- Must call `DjangoInstrumentor().instrument()` before `django.setup()`
- Or add to `INSTALLED_APPS` before other apps

### FastAPI

- Call `FastAPIInstrumentor.instrument()` before creating `app`
- Or use `instrument_app(app)` after creation
