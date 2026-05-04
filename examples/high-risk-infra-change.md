# Example: high-risk infra change monitoring plan

> Source change: replace the in-cluster ingress controller from nginx to Envoy. Deploys via Helm to staging then prod. Telemetry: Datadog (request metrics) + Prometheus (infra).

## Monitoring plan

**Risk tier:** high — every external request flows through the new ingress; misconfigured listener / TLS / rate-limit rules can take prod offline; rollback requires re-applying the previous Helm chart and waiting for pods to converge (≥5 min MTTR).
**Intended effect:** all services remain reachable from outside the cluster; observed throughput and latency on the ingress match nginx baselines (or improve).
**Blast radius (unintended):** every public-facing service (≈40 services); TLS handshake failures, HTTP/2 incompatibilities, header-rewriting differences; rate-limit-rule semantics may differ subtly from nginx.
**Rollback:** `helm rollback ingress -n ingress prod-revision-N` (the previous synced revision). On-call should be paged for any rollback decision — this is not a "just revert the PR" change; the chart is the source of truth.

### Environments

#### staging
Deploy detection:
```
helm list -n ingress -o json | jq '.[] | select(.name=="ingress") | .revision'
# match revision against expected post-deploy revision number; verify pod readiness.
kubectl rollout status deployment/ingress -n ingress --timeout=60s
```
Match: `helm revision matches expected && kubectl rollout returned successfully`

#### prod
Deploy detection:
```
kubectl --context=prod rollout status deployment/ingress -n ingress --timeout=60s
```
Match: `kubectl rollout returned successfully && all pods running new image tag`

### Indicators

| Name | Kind | Source | Baseline (24h) | Threshold | Direction | Scope |
|------|------|--------|----------------|-----------|-----------|-------|
| edge-error-rate | ratio | `Datadog:query_metrics` `sum:nginx.ingress.requests.errors{ingress:envoy}.as_count() / sum:nginx.ingress.requests{ingress:envoy}.as_count() by {env}` | staging 0.4% / prod 0.18% | > 3× baseline sustained 5m | unintended-watch | shared |
| edge-latency-p99 | gauge | `Datadog:query_metrics` `p99:nginx.ingress.upstream.response_time{ingress:envoy} by {env}` | staging 230ms / prod 110ms | > baseline + 100ms sustained 5m | unintended-watch | shared |
| edge-rps | gauge | `Datadog:query_metrics` `sum:nginx.ingress.requests{ingress:envoy}.as_rate() by {env}` | staging 1.2k req/s / prod 28k req/s | < 50% of baseline for 5m (degenerate fail) | unintended-watch | shared |
| tls-handshake-failures | ratio | `Datadog:query_metrics` `sum:nginx.ingress.tls.handshake.failures{ingress:envoy}.as_count() / sum:nginx.ingress.tls.handshakes{ingress:envoy}.as_count() by {env}` | staging 0.05% / prod 0.02% | > 5× baseline sustained 2m | unintended-watch | shared |
| ingress-pod-cpu | gauge | `Prometheus:query_range` `avg(rate(container_cpu_usage_seconds_total{namespace="ingress"}[5m])) by (env)` | staging 0.28 / prod 0.53 | > 0.90 sustained 2m | unintended-watch | shared |
| ingress-pod-memory | gauge | `Prometheus:query_range` `avg(container_memory_working_set_bytes{namespace="ingress"}) by (env)` | staging 380 MiB / prod 720 MiB | > 1.5× baseline sustained 5m | unintended-watch | shared |
| ingress-pod-restarts | gauge | `Prometheus:query_range` `sum(increase(kube_pod_container_status_restarts_total{namespace="ingress"}[10m])) by (env)` | 0 | > 0 sustained 5m | unintended-watch | shared |

### Checkpoints

`+10m, +30m, +1h, +2h, +24h, +72h`

(Full schedule because: TLS / HTTP/2 incompatibilities may not surface immediately if not all client libs hit them at first; +24h captures peak-hour traffic patterns; +72h captures weekly cycles for long-tail clients.)

### Activation

After the change merges and the deploy is triggered, run:

```
/execute-change-control examples/high-risk-infra-change.md
```

in this same session to monitor it.
