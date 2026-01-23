# Node.js Dependencies

## Install

```bash
npm install @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node \
  @opentelemetry/exporter-trace-otlp-http @opentelemetry/exporter-metrics-otlp-http \
  @opentelemetry/exporter-logs-otlp-http @opentelemetry/sdk-logs @opentelemetry/api-logs
```

## Wire Entry Point

Add to the **top** of your main file (before any other imports):

```typescript
import './instrumentation';
```

Or use the `--require` flag:

```bash
node --require ./instrumentation.js app.js
```

## Next.js (App Router)

For Next.js 13+, use the built-in instrumentation hook. Create `instrumentation.ts` at project root:

```typescript
export async function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    await import('./src/instrumentation');
  }
}
```

Then enable in `next.config.js`:

```javascript
module.exports = {
  experimental: {
    instrumentationHook: true,
  },
};
```
