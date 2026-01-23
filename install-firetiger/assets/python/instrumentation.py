import os
import logging
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource, SERVICE_NAME
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry._logs import set_logger_provider
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter

OTEL_ENDPOINT = os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT', '{{INGEST_URL}}')
OTEL_AUTH = os.getenv('OTEL_AUTH_HEADER', 'Basic {{AUTH_HEADER}}')
OTEL_HEADERS = {'Authorization': OTEL_AUTH}
SERVICE = os.getenv('OTEL_SERVICE_NAME', '{{SERVICE_NAME}}')

resource = Resource.create({SERVICE_NAME: SERVICE})

# Traces
_tracer_provider = TracerProvider(resource=resource)
_tracer_provider.add_span_processor(
    BatchSpanProcessor(
        OTLPSpanExporter(
            endpoint=f"{OTEL_ENDPOINT}/v1/traces",
            headers=OTEL_HEADERS,
        )
    )
)
trace.set_tracer_provider(_tracer_provider)

# Metrics
_metric_reader = PeriodicExportingMetricReader(
    OTLPMetricExporter(
        endpoint=f"{OTEL_ENDPOINT}/v1/metrics",
        headers=OTEL_HEADERS,
    )
)
_meter_provider = MeterProvider(resource=resource, metric_readers=[_metric_reader])
metrics.set_meter_provider(_meter_provider)

# Logs
_logger_provider = LoggerProvider(resource=resource)
_logger_provider.add_log_record_processor(
    BatchLogRecordProcessor(
        OTLPLogExporter(
            endpoint=f"{OTEL_ENDPOINT}/v1/logs",
            headers=OTEL_HEADERS,
        )
    )
)
set_logger_provider(_logger_provider)
logging.getLogger().addHandler(LoggingHandler(logger_provider=_logger_provider))

# Convenience exports
tracer = trace.get_tracer(__name__)
meter = metrics.get_meter(__name__)
