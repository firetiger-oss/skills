# Go Dependencies

## Install

```bash
go get go.opentelemetry.io/otel \
  go.opentelemetry.io/otel/sdk \
  go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp \
  go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp \
  go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp
```

## Wire Entry Point

Call `InitOtel` at the start of `main()`:

```go
func main() {
	ctx := context.Background()
	shutdown, err := InitOtel(ctx)
	if err != nil {
		log.Fatal(err)
	}
	defer shutdown(ctx)

	// ... rest of your application
}
```

## HTTP Middleware

For automatic HTTP server instrumentation:

```bash
go get go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp
```

```go
import "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

handler := otelhttp.NewHandler(mux, "server")
http.ListenAndServe(":8080", handler)
```

## gRPC Interceptors

For automatic gRPC instrumentation:

```bash
go get go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc
```

```go
import "go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc"

server := grpc.NewServer(
	grpc.StatsHandler(otelgrpc.NewServerHandler()),
)
```
