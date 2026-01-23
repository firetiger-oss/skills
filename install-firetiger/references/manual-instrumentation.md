# Manual Instrumentation

Add custom spans around business logic when auto-instrumentation isn't enough.

## Node.js/TypeScript

```typescript
import { trace } from '@opentelemetry/api';

const tracer = trace.getTracer('my-service');

async function processOrder(orderId: string) {
  return tracer.startActiveSpan('process-order', async (span) => {
    try {
      span.setAttribute('order.id', orderId);
      await doWork();
      span.setAttribute('order.status', 'completed');
    } catch (error) {
      span.recordException(error);
      span.setStatus({ code: SpanStatusCode.ERROR });
      throw error;
    } finally {
      span.end();
    }
  });
}
```

### Adding Events

```typescript
span.addEvent('validation-complete', { itemCount: 5 });
```

### Linking Spans

```typescript
const link = { context: parentSpan.spanContext() };
tracer.startActiveSpan('linked-operation', { links: [link] }, (span) => {
  // ...
});
```

## Python

```python
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

def process_order(order_id: str):
    with tracer.start_as_current_span("process-order") as span:
        span.set_attribute("order.id", order_id)
        try:
            do_work()
            span.set_attribute("order.status", "completed")
        except Exception as e:
            span.record_exception(e)
            span.set_status(trace.StatusCode.ERROR)
            raise
```

### Context Propagation

```python
from opentelemetry import context
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

# Inject into outgoing request
headers = {}
TraceContextTextMapPropagator().inject(headers)

# Extract from incoming request
ctx = TraceContextTextMapPropagator().extract(carrier=request.headers)
with tracer.start_as_current_span("handler", context=ctx):
    # ...
```

## Go

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/attribute"
    "go.opentelemetry.io/otel/codes"
)

var tracer = otel.Tracer("my-service")

func processOrder(ctx context.Context, orderID string) error {
    ctx, span := tracer.Start(ctx, "process-order")
    defer span.End()

    span.SetAttributes(attribute.String("order.id", orderID))

    if err := doWork(ctx); err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
        return err
    }

    return nil
}
```

### Nested Spans

```go
func processOrder(ctx context.Context, orderID string) error {
    ctx, span := tracer.Start(ctx, "process-order")
    defer span.End()

    // Child span inherits context
    if err := validateOrder(ctx, orderID); err != nil {
        return err
    }
    return fulfillOrder(ctx, orderID)
}

func validateOrder(ctx context.Context, orderID string) error {
    ctx, span := tracer.Start(ctx, "validate-order")
    defer span.End()
    // ...
}
```

## Rust

```rust
use tracing::{instrument, info_span, Instrument, Span};

#[instrument(fields(order.id = %order_id))]
async fn process_order(order_id: &str) -> Result<(), Error> {
    Span::current().record("order.status", "processing");

    do_work()
        .instrument(info_span!("do-work"))
        .await?;

    Span::current().record("order.status", "completed");
    Ok(())
}
```

### Manual Span Creation

```rust
use tracing::span;

let span = span!(tracing::Level::INFO, "my-operation", key = "value");
let _guard = span.enter();
// ... work happens here
// span ends when _guard drops
```

### Async Context

```rust
async fn handler() {
    let span = info_span!("handler");

    async move {
        // This work is traced under "handler"
        do_async_work().await;
    }
    .instrument(span)
    .await;
}
```
