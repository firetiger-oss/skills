use opentelemetry::global;
use opentelemetry_otlp::{Protocol, SpanExporter, WithExportConfig, WithHttpConfig};
use opentelemetry_sdk::{trace::SdkTracerProvider, Resource};
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

    let exporter = SpanExporter::builder()
        .with_http()
        .with_protocol(Protocol::HttpBinary)
        .with_endpoint(format!("{}/v1/traces", endpoint))
        .with_headers(headers)
        .build()?;

    let provider = SdkTracerProvider::builder()
        .with_batch_exporter(exporter)
        .with_resource(Resource::builder().with_service_name(service_name).build())
        .build();

    global::set_tracer_provider(provider.clone());

    let tracer = provider.tracer("app");
    let telemetry_layer = tracing_opentelemetry::layer().with_tracer(tracer);

    tracing_subscriber::registry()
        .with(telemetry_layer)
        .with(tracing_subscriber::fmt::layer())
        .with(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    Ok(())
}
