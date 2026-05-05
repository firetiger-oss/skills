#!/usr/bin/env bash
# Sleep until an absolute time, then echo a resume marker.
#
# Usage: sleep_until.sh <absolute-rfc3339-time> <plan-path> [offset-label]
#
# Designed to be invoked via the agent's Bash tool with run_in_background:true.
# When the sleep completes, the echoed marker becomes a notification in the
# agent's chat — the agent reads it and resumes the next checkpoint.
#
# Why bash-bg over ScheduleWakeup: ScheduleWakeup is scoped to /loop dynamic
# mode; outside /loop the wake/resume contract is unclear. run_in_background
# + sleep + notification works in every coding-agent harness that supports
# background commands (Claude Code, Codex, Cursor, etc.).
set -u

ABS_TIME="${1:-}"
PLAN_PATH="${2:-}"
OFFSET_LABEL="${3:-checkpoint}"

if [ -z "$ABS_TIME" ] || [ -z "$PLAN_PATH" ]; then
    echo "usage: sleep_until.sh <absolute-rfc3339-time> <plan-path> [offset-label]" >&2
    exit 2
fi

# Convert RFC3339 → epoch seconds. Handle GNU and BSD date.
to_epoch() {
    local ts="$1"
    if date --version 2>/dev/null | grep -q GNU; then
        date -u -d "$ts" +%s
    else
        date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null \
            || date -u -j -f "%Y-%m-%dT%H:%M:%S%z" "$ts" +%s
    fi
}

TARGET_EPOCH=$(to_epoch "$ABS_TIME") || {
    echo "sleep_until.sh: cannot parse absolute time '$ABS_TIME'" >&2
    exit 2
}
NOW_EPOCH=$(date -u +%s)
DELAY=$((TARGET_EPOCH - NOW_EPOCH))

if [ "$DELAY" -lt 0 ]; then
    # Target is in the past — fire immediately. This handles edge cases like
    # clock skew or a missed wakeup; the agent's resume-handler will treat it
    # as "checkpoint due now."
    DELAY=0
fi

# Cap at 7 days. Beyond that, the agent harness is unlikely to keep the
# background process alive, and the user should restart monitoring manually.
MAX_DELAY=$((7 * 24 * 3600))
if [ "$DELAY" -gt "$MAX_DELAY" ]; then
    echo "sleep_until.sh: requested delay $DELAY > 7-day cap; refusing" >&2
    exit 2
fi

sleep "$DELAY"
echo "[RESUME at $ABS_TIME] $OFFSET_LABEL for plan $PLAN_PATH"
