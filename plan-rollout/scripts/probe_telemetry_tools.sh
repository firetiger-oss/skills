#!/usr/bin/env bash
# Probe which telemetry tools are available locally and pick ONE primary
# according to the priority order documented in plan-rollout/SKILL.md.
#
# Usage: probe_telemetry_tools.sh
#
# Prints:
#   PRIMARY=<name>            # the picked default
#   PRIMARY_VERIFIED=<yes|no> # whether the primary's queryable endpoint actually responded
#   AVAILABLE=...             # all detected tools (for the escape-hatch case)
#   # Push-only endpoints detected (cannot query): ...   (when applicable)
#
# Priority: datadog > honeycomb > axiom > grafana-stack > cloudwatch > http-poll
# Where grafana-stack is "two or more of {tempo, loki, prometheus|mimir} are queryable".
#
# Rationale (per SKILL.md): default-with-escape-hatch beats menu of N options.
# This script distinguishes queryable telemetry from push-only (e.g. an OTLP push
# endpoint set in OTEL_EXPORTER_OTLP_ENDPOINT) so the planner doesn't propose
# indicators against an endpoint it cannot read from.
set -u

# --- queryable detection per tool ---
# Each function exits 0 if the tool is queryable, 1 otherwise. A separate set
# of functions records push-only detection so we can warn the user.

# 5-second timeout on probe HTTP calls so a hung endpoint can't stall the
# planner. curl alone retries on connection refused; --max-time is a hard cap.
PROBE_TIMEOUT_SECS=5

queryable_datadog() {
    # Datadog requires both DD_API_KEY (ingest) and DD_APP_KEY (query) for the
    # query path. We don't probe the API in this script — it's well-known and
    # rate-limited; the planner will hit it when running a query.
    [ -n "${DD_API_KEY:-}" ] && [ -n "${DD_APP_KEY:-}" ]
}

queryable_honeycomb() {
    [ -n "${HONEYCOMB_API_KEY:-}" ] || command -v hccli >/dev/null 2>&1 || command -v honeycomb >/dev/null 2>&1
}

queryable_axiom() {
    [ -n "${AXIOM_TOKEN:-}" ] || command -v axiom >/dev/null 2>&1
}

# Prometheus / Mimir are wire-compatible at the query API. We probe whichever
# URL the user has configured.
queryable_prometheus_or_mimir() {
    local url="${PROMETHEUS_URL:-${MIMIR_URL:-}}"
    if [ -z "$url" ] && command -v promtool >/dev/null 2>&1; then
        # promtool present but no URL: assume reachable via default localhost
        # in dev environments; mark as queryable but unverified.
        return 0
    fi
    [ -z "$url" ] && return 1
    # Strip trailing slash, hit the runtime-info endpoint (cheap, no auth on
    # most setups; if auth is required this will 401 which still indicates a
    # queryable surface, just with credentials needed).
    if curl -fsS --max-time "$PROBE_TIMEOUT_SECS" -o /dev/null "${url%/}/api/v1/status/runtimeinfo" 2>/dev/null; then
        return 0
    fi
    # Some setups require auth; a 401 is still queryable, just credentials
    # missing. curl returns 22 for >=400 with -f.
    if curl -sS --max-time "$PROBE_TIMEOUT_SECS" -o /dev/null -w '%{http_code}' "${url%/}/api/v1/status/runtimeinfo" 2>/dev/null | grep -qE '^(200|401|403)$'; then
        return 0
    fi
    return 1
}

queryable_tempo() {
    local url="${TEMPO_URL:-}"
    [ -z "$url" ] && return 1
    if curl -fsS --max-time "$PROBE_TIMEOUT_SECS" -o /dev/null "${url%/}/api/echo" 2>/dev/null; then
        return 0
    fi
    if curl -sS --max-time "$PROBE_TIMEOUT_SECS" -o /dev/null -w '%{http_code}' "${url%/}/api/echo" 2>/dev/null | grep -qE '^(200|401|403)$'; then
        return 0
    fi
    return 1
}

queryable_loki() {
    local url="${LOKI_URL:-}"
    [ -z "$url" ] && return 1
    if curl -fsS --max-time "$PROBE_TIMEOUT_SECS" -o /dev/null "${url%/}/ready" 2>/dev/null; then
        return 0
    fi
    if curl -sS --max-time "$PROBE_TIMEOUT_SECS" -o /dev/null -w '%{http_code}' "${url%/}/ready" 2>/dev/null | grep -qE '^(200|401|403)$'; then
        return 0
    fi
    return 1
}

queryable_cloudwatch() {
    command -v aws >/dev/null 2>&1 && aws sts get-caller-identity >/dev/null 2>&1
}

# --- Platform-native CLIs (for Vercel / Netlify / Cloudflare Pages targets) ---
# These are the right primary telemetry source for static-site / serverless
# deploys on those platforms — the platform's own log + analytics surface
# carries the request-time data that no general-purpose metrics backend
# (Datadog, Prometheus, etc.) sees unless the team has a log drain wired up.

queryable_vercel_cli() {
    command -v vercel >/dev/null 2>&1 && timeout 3 vercel whoami >/dev/null 2>&1
}

queryable_netlify_cli() {
    command -v netlify >/dev/null 2>&1 && timeout 3 netlify status >/dev/null 2>&1
}

queryable_wrangler_cli() {
    command -v wrangler >/dev/null 2>&1 && timeout 3 wrangler whoami >/dev/null 2>&1
}

# Push-only endpoint detection — these mean telemetry is *being sent* but we
# can't query it. Worth surfacing to the user so they know the data is going
# somewhere reachable, just not by us.
push_only_endpoints() {
    local out=()
    if [ -n "${OTEL_EXPORTER_OTLP_ENDPOINT:-}" ] && ! queryable_prometheus_or_mimir && ! queryable_tempo && ! queryable_loki; then
        out+=("OTEL_EXPORTER_OTLP_ENDPOINT=${OTEL_EXPORTER_OTLP_ENDPOINT}")
    fi
    if [ -n "${OTEL_EXPORTER_OTLP_TRACES_ENDPOINT:-}" ] && ! queryable_tempo; then
        out+=("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=${OTEL_EXPORTER_OTLP_TRACES_ENDPOINT}")
    fi
    if [ -n "${OTEL_EXPORTER_OTLP_METRICS_ENDPOINT:-}" ] && ! queryable_prometheus_or_mimir; then
        out+=("OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=${OTEL_EXPORTER_OTLP_METRICS_ENDPOINT}")
    fi
    if [ -n "${OTEL_EXPORTER_OTLP_LOGS_ENDPOINT:-}" ] && ! queryable_loki; then
        out+=("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=${OTEL_EXPORTER_OTLP_LOGS_ENDPOINT}")
    fi
    if [ "${#out[@]}" -gt 0 ]; then
        printf '%s\n' "${out[@]}"
    fi
}

# --- main ---
# Build the available list in priority order, then derive PRIMARY +
# PRIMARY_VERIFIED. Verification is whether we actually got a successful probe
# response (vs. just having env vars set).

available=()
verified=()

probe_one() {
    local name="$1"
    local probe_fn="$2"
    if "$probe_fn"; then
        available+=("$name")
        # The probe functions all currently return 0 only on actual queryable
        # response (or env-var presence for tools where we don't probe). Mark
        # accordingly:
        case "$name" in
            datadog|honeycomb|axiom|cloudwatch)
                # No HTTP probe, just env/CLI presence. Mark unverified so the
                # planner knows to double-check at first query.
                verified+=("no")
                ;;
            *)
                verified+=("yes")
                ;;
        esac
    fi
}

probe_one datadog queryable_datadog
probe_one honeycomb queryable_honeycomb
probe_one axiom queryable_axiom
probe_one tempo queryable_tempo
probe_one loki queryable_loki
probe_one prometheus queryable_prometheus_or_mimir
probe_one cloudwatch queryable_cloudwatch
probe_one vercel-cli queryable_vercel_cli
probe_one netlify-cli queryable_netlify_cli
probe_one wrangler-cli queryable_wrangler_cli

# Detect a Grafana-stack tier: two or more of {tempo, loki, prometheus} present.
gs_count=0
if [ "${#available[@]}" -gt 0 ]; then
    for t in tempo loki prometheus; do
        for a in "${available[@]}"; do
            [ "$a" = "$t" ] && gs_count=$((gs_count + 1))
        done
    done
fi

# Deploy-target heuristic: is this a static-site / front-end-only repo?
# Signal: package.json with a known JS-meta-framework AND no obvious backend
# code (no go.mod, no Cargo.toml, no python entry points, no cmd/, no Go
# files at the root). When true, metrics backends like Prometheus/Tempo
# almost certainly don't carry telemetry for the deploy target — they cover
# server-side services, not static sites. Demote them in the priority
# selection so PRIMARY defaults to http-poll for this repo shape.
#
# Even when demoted, the backends stay in AVAILABLE so the agent retains
# the option to override (e.g. if the static site does emit RUM metrics
# into Prometheus via a custom collector).
is_static_site_target=0
ROOT="${ROOT:-.}"
if [ -f "$ROOT/package.json" ] && grep -qE '"(next|astro|@remix-run/[^"]+|nuxt|@sveltejs/kit)"\s*:' "$ROOT/package.json" 2>/dev/null; then
    has_backend=0
    [ -f "$ROOT/go.mod" ] && has_backend=1
    [ -f "$ROOT/Cargo.toml" ] && has_backend=1
    [ -f "$ROOT/pyproject.toml" ] && has_backend=1
    [ -f "$ROOT/setup.py" ] && has_backend=1
    [ -f "$ROOT/Gemfile" ] && has_backend=1
    [ -f "$ROOT/pom.xml" ] && has_backend=1
    [ -f "$ROOT/build.gradle" ] && has_backend=1
    [ -d "$ROOT/cmd" ] && has_backend=1
    if compgen -G "$ROOT/*.go" >/dev/null 2>&1; then has_backend=1; fi
    if [ "$has_backend" = "0" ]; then
        is_static_site_target=1
    fi
fi

# Pick PRIMARY by priority order
primary=""
primary_verified="no"
priority_lookup() {
    # Re-derive priority pick from available list. Order:
    # datadog > honeycomb > axiom > grafana-stack > prometheus (alone) > cloudwatch > http-poll
    #
    # Special case: when the deploy target is a static site / front-end-only,
    # general-purpose metrics backends (Datadog/Prometheus/Tempo/Loki) almost
    # certainly don't have telemetry for the deploy target — they cover
    # backend services, not static sites. Prefer the platform's own
    # observability surface (Vercel CLI logs+analytics, Netlify CLI logs,
    # Cloudflare wrangler tail) over them, falling back to http-poll.
    #
    # Caveat: if the team has wired a log drain (e.g. Vercel → Datadog), the
    # drain destination IS a valid source — but this script can't auto-detect
    # that. The agent should ask the user when in doubt; see SKILL.md step 4.
    if [ "$is_static_site_target" = "1" ]; then
        for p in vercel-cli netlify-cli wrangler-cli; do
            for i in "${!available[@]}"; do
                if [ "${available[$i]}" = "$p" ]; then
                    primary="$p"
                    primary_verified="yes"
                    return
                fi
            done
        done
        primary="http-poll"
        primary_verified="yes"
        return
    fi
    if [ "${#available[@]}" -gt 0 ]; then
        for p in datadog honeycomb axiom; do
            for i in "${!available[@]}"; do
                if [ "${available[$i]}" = "$p" ]; then
                    primary="$p"
                    primary_verified="${verified[$i]}"
                    return
                fi
            done
        done
        if [ "$gs_count" -ge 2 ]; then
            primary="grafana-stack"
            primary_verified="yes"
            return
        fi
        for p in prometheus cloudwatch; do
            for i in "${!available[@]}"; do
                if [ "${available[$i]}" = "$p" ]; then
                    primary="$p"
                    primary_verified="${verified[$i]}"
                    return
                fi
            done
        done
    fi
    # Fallback: http-poll always available
    primary="http-poll"
    primary_verified="yes"
}
priority_lookup

# Always include http-poll in available (last-resort fallback)
available+=("http-poll")

echo "PRIMARY=$primary"
echo "PRIMARY_VERIFIED=$primary_verified"
echo "AVAILABLE=${available[*]}"

# Push-only warnings
po=$(push_only_endpoints)
if [ -n "$po" ]; then
    echo "# Push-only endpoints detected (cannot query):"
    while IFS= read -r line; do
        [ -n "$line" ] && echo "#   $line"
    done <<< "$po"
fi

echo
echo "# Note: this script verifies queryable HTTP surfaces (Prometheus/Mimir, Tempo,"
echo "# Loki) by hitting each tool's status endpoint. Tools without HTTP probes"
echo "# (Datadog, Honeycomb, Axiom, CloudWatch) are marked PRIMARY_VERIFIED=no;"
echo "# the planner will confirm them on first real query."
echo "# The agent should also probe its MCP tool list (Datadog:*, Honeycomb:*,"
echo "# Axiom:*, Grafana:*, etc.). MCP-served tools take precedence over CLIs."
