#!/usr/bin/env bash
# Render a status report block (DEPLOY_DETECTED | CHECK_COMPLETE | ISSUE_DETECTED |
# COMPLETED | FATAL_ERROR | WARNING) by filling in fields from JSON on stdin.
#
# Usage: cat report.json | render_status_report.sh <type>
#
# type: deploy_detected | check_complete | issue_detected | completed | fatal_error | warning
#
# The JSON shape per type is documented in references/status-report-formats.md.
# This script keeps the rendering deterministic so the user sees consistent
# blocks across checkpoints.
set -euo pipefail

TYPE="${1:-}"

if [ -z "$TYPE" ]; then
    echo "usage: render_status_report.sh <type>" >&2
    exit 2
fi

INPUT="$(cat)"
if [ -z "$INPUT" ]; then
    echo "render_status_report.sh: empty stdin (expected JSON)" >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "render_status_report.sh: jq is required" >&2
    exit 2
fi

# Helper: extract a top-level field, returning empty string when missing.
field() {
    printf '%s' "$INPUT" | jq -r ".$1 // empty"
}

case "$TYPE" in
    deploy_detected)
        cat <<EOF
## [STATUS: DEPLOY_DETECTED — $(field env)]

- **Env:** $(field env)
- **Deploy time:** $(field deploy_time)
- **Source:** $(field source)
- **Commit:** $(field commit)
- **Next checkpoint:** $(field next_offset) at $(field next_abs)

Other envs:
$(printf '%s' "$INPUT" | jq -r '.other_envs[]? | "- \(.name): \(.note)"')

**Next event expected:** $(field next_abs) (\`bash sleep_until.sh $(field next_abs) $(field plan_path) $(field next_offset)\` running in background)
EOF
        ;;

    check_complete)
        cat <<EOF
## [STATUS: CHECK_COMPLETE @ $(field offset)]

| Env | Intended? | Indicators verdict | Notes |
|-----|-----------|--------------------|-------|
$(printf '%s' "$INPUT" | jq -r '.envs[] | "| \(.name) | \(.intended_status) | \(.indicators_summary) | \(.notes) |"')

**Next checkpoint:** $(field next_offset_or_terminal)

**Next event expected:** $(field next_abs) (\`bash sleep_until.sh $(field next_abs) $(field plan_path) $(field next_offset_or_terminal)\` running in background)
EOF
        ;;

    issue_detected)
        cat <<EOF
## [STATUS: ISSUE_DETECTED — $(field env) @ $(field offset)]

**Env:** $(field env)

**Failing indicators:**

| Indicator | Pre | Post | Δ | Threshold |
|-----------|-----|------|---|-----------|
$(printf '%s' "$INPUT" | jq -r '.failing[] | "| \(.name) | \(.pre) | \(.post) | \(.delta) | \(.threshold) |"')

**Evidence (per evidence-discipline gate):**
- Baseline window: $(field evidence.baseline_window)
- Same-time-of-day comparison: $(field evidence.same_tod)
- Analytical reason: $(field evidence.reason)
- Variance test: $(field evidence.variance)

**Recommended action:** roll back via \`$(field rollback_hint)\`. Re-run \`/monitor-rollout $(field plan_path)\` after the rollback to confirm metrics return to baseline.

**Other envs:**
$(printf '%s' "$INPUT" | jq -r '.other_envs[]? | "- \(.name): \(.note)"')

**Handoff:** entering plan mode to design the fix.

**Next event:** none — terminal state.
EOF
        ;;

    completed)
        cat <<EOF
## [STATUS: COMPLETED]

**Window:** $(field window_start) → $(field window_end)  ($(field tier) tier, $(field n_checkpoints) checkpoints)
**Envs:** $(field envs)

**Intended effects confirmed:**
$(printf '%s' "$INPUT" | jq -r '.intended_confirmed[]? | "- \(.env) — \(.detail)"')

**Inconclusive notes:**
$(printf '%s' "$INPUT" | jq -r '.inconclusive[]? | "- \(.env) — \(.detail)"')

**Monitoring window closed; no further checkpoints scheduled. Safe to close this loop.**

**Next event:** none — terminal state.
EOF
        ;;

    fatal_error)
        cat <<EOF
## [STATUS: FATAL_ERROR]

**Cause:** $(field cause)

**Detail:**
- Plan parse: $(field detail.plan_parse)
- Polling: $(field detail.polling)
- Telemetry: $(field detail.telemetry)

The executor is stopping. Resolve the underlying issue and re-invoke \`/monitor-rollout $(field plan_path)\`.

**Next event:** none — terminal state.
EOF
        ;;

    warning)
        cat <<EOF
## [STATUS: WARNING — $(field env)]

$(field message)

$(field user_question)

**Next event expected:** awaiting user response (no background sleep scheduled).
EOF
        ;;

    *)
        echo "render_status_report.sh: unknown type '$TYPE'" >&2
        exit 2
        ;;
esac
