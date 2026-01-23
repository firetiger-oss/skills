# Rust Dependencies

## Add to Cargo.toml

```toml
[dependencies]
opentelemetry = "0.31"
opentelemetry_sdk = { version = "0.31", features = ["rt-tokio"] }
opentelemetry-otlp = { version = "0.31", features = ["http-proto", "reqwest-client"] }
tracing = "0.1"
tracing-opentelemetry = "0.32"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
```

## Wire Entry Point

Call `init_telemetry` at the start of `main`:

```rust
mod instrumentation;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    instrumentation::init_telemetry()?;

    // ... rest of your application

    Ok(())
}
```

## Axum Integration

For automatic HTTP server instrumentation with Axum:

```toml
[dependencies]
tower-http = { version = "0.5", features = ["trace"] }
```

```rust
use tower_http::trace::TraceLayer;

let app = Router::new()
    .route("/", get(handler))
    .layer(TraceLayer::new_for_http());
```

## Actix-Web Integration

```toml
[dependencies]
tracing-actix-web = "0.7"
```

```rust
use tracing_actix_web::TracingLogger;

HttpServer::new(|| {
    App::new()
        .wrap(TracingLogger::default())
        .service(handler)
})
```
