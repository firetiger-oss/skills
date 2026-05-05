#!/usr/bin/env bash
# Probe which telemetry tools are available locally and pick ONE primary
# according to the priority order documented in plan-rollout/SKILL.md.
#
# Usage: probe_telemetry_tools.sh
#
# Prints two sections:
#   PRIMARY=<name>   # the picked default
#   AVAILABLE=...    # all detected tools (for the escape-hatch case)
#
# Priority: datadog > honeycomb > axiom > prometheus > cloudwatch > http-poll
# Rationale (per SKILL.md): default-with-escape-hatch beats menu of N options.
set -u

# Detect a tool via either env-var presence or CLI presence on PATH. We don't
# probe MCP tool availability here — that's a runtime concern handled by the
# agent. This script gives a best-effort hint based on what's installed locally.
detect() {
    local name="$1"
    case "$name" in
        datadog)
            [ -n "${DD_API_KEY:-}" ] || command -v dog >/dev/null 2>&1 || command -v datadog-ci >/dev/null 2>&1
            ;;
        honeycomb)
            [ -n "${HONEYCOMB_API_KEY:-}" ] || command -v hccli >/dev/null 2>&1 || command -v honeycomb >/dev/null 2>&1
            ;;
        axiom)
            [ -n "${AXIOM_TOKEN:-}" ] || command -v axiom >/dev/null 2>&1
            ;;
        prometheus)
            [ -n "${PROMETHEUS_URL:-}" ] || command -v promtool >/dev/null 2>&1
            ;;
        cloudwatch)
            command -v aws >/dev/null 2>&1 && aws sts get-caller-identity >/dev/null 2>&1
            ;;
        http-poll)
            # Always available — last-resort fallback.
            true
            ;;
        *)
            return 1
            ;;
    esac
}

PRIORITY=(datadog honeycomb axiom prometheus cloudwatch http-poll)

available=()
primary=""
for tool in "${PRIORITY[@]}"; do
    if detect "$tool"; then
        available+=("$tool")
        if [ -z "$primary" ]; then
            primary="$tool"
        fi
    fi
done

echo "PRIMARY=$primary"
echo "AVAILABLE=${available[*]}"
echo
echo "# Note: this only checks for env vars + CLIs on PATH. The agent should"
echo "# also probe its MCP tool list (Datadog:*, Honeycomb:*, Axiom:*, etc.)."
echo "# If an MCP server for a higher-priority tool is available, prefer it."
