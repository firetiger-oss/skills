use opentelemetry::trace::TracerProvider;
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::{runtime, trace as sdktrace, Resource};
use std::collections::HashMap;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

fn env_or(key: &str, default: &str) -> String {
    std::env::var(key).unwrap_or_else(|_| default.to_string())
}

/// Initialize OpenTelemetry with Firetiger backend.
/// Call once at application startup.
pub fn init_telemetry() -> Result<(), Box<dyn std::error::Error>> {
    let endpoint = env_or("OTEL_EXPORTER_OTLP_ENDPOINT", "{{INGEST_URL}}");
    let auth_header = env_or("OTEL_AUTH_HEADER", "Basic {{AUTH_HEADER}}");
    let service_name = env_or("OTEL_SERVICE_NAME", "{{SERVICE_NAME}}");

    let mut headers = HashMap::new();
    headers.insert("Authorization".to_string(), auth_header);

    let exporter = opentelemetry_otlp::new_exporter()
        .http()
        .with_endpoint(format!("{}/v1/traces", endpoint))
        .with_headers(headers);

    let provider = opentelemetry_otlp::new_pipeline()
        .tracing()
        .with_exporter(exporter)
        .with_trace_config(
            sdktrace::Config::default().with_resource(Resource::new(vec![
                opentelemetry::KeyValue::new("service.name", service_name),
            ])),
        )
        .install_batch(runtime::Tokio)?;

    let tracer = provider.tracer("app");
    let telemetry_layer = tracing_opentelemetry::layer().with_tracer(tracer);

    tracing_subscriber::registry()
        .with(telemetry_layer)
        .with(tracing_subscriber::fmt::layer())
        .with(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    Ok(())
}
