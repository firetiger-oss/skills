#!/usr/bin/env bash
# Compute the next checkpoint absolute time given deploy_time and tier.
#
# Usage: compute_next_checkpoint.sh <deploy-time-rfc3339> <tier> [last-fired-offset]
#
# tier: low | medium | high
# last-fired-offset: optional; the offset string of the most recently fired
#   checkpoint (e.g. "+30m"). If omitted, returns the first checkpoint.
#
# Output: <absolute-rfc3339-time>\t<offset-string>\n
# Exit 0 on success; exit 1 when there are no more checkpoints; exit 2 on
# usage error.
set -u

DEPLOY_TIME="${1:-}"
TIER="${2:-}"
LAST_OFFSET="${3:-}"

if [ -z "$DEPLOY_TIME" ] || [ -z "$TIER" ]; then
    echo "usage: compute_next_checkpoint.sh <deploy-time-rfc3339> <tier> [last-fired-offset]" >&2
    exit 2
fi

# Tier-to-schedule mapping. Keep in sync with plan-change-control/references/checkpoint-schedule.md.
case "$TIER" in
    low)
        OFFSETS="+10m +30m"
        ;;
    medium)
        OFFSETS="+10m +30m +1h +2h"
        ;;
    high)
        OFFSETS="+10m +30m +1h +2h +24h +72h"
        ;;
    *)
        echo "compute_next_checkpoint.sh: unknown tier '$TIER' (low|medium|high)" >&2
        exit 2
        ;;
esac

# Parse deploy_time (RFC3339 → epoch seconds). Handle GNU and BSD date.
to_epoch() {
    local ts="$1"
    if date --version 2>/dev/null | grep -q GNU; then
        date -u -d "$ts" +%s
    else
        # macOS BSD date — strip the trailing Z and use ISO format.
        date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null \
            || date -u -j -f "%Y-%m-%dT%H:%M:%S%z" "$ts" +%s
    fi
}

from_epoch() {
    local secs="$1"
    if date --version 2>/dev/null | grep -q GNU; then
        date -u -d "@$secs" +"%Y-%m-%dT%H:%M:%SZ"
    else
        date -u -r "$secs" +"%Y-%m-%dT%H:%M:%SZ"
    fi
}

# Convert an offset string (+10m / +1h / +24h / +72h) to seconds.
offset_to_seconds() {
    local off="$1"
    local n unit
    n=$(echo "$off" | sed -E 's/^\+([0-9]+).*/\1/')
    unit=$(echo "$off" | sed -E 's/^\+[0-9]+(.*)/\1/')
    case "$unit" in
        m) echo $((n * 60)) ;;
        h) echo $((n * 3600)) ;;
        d) echo $((n * 86400)) ;;
        *)
            echo "compute_next_checkpoint.sh: bad offset unit in '$off'" >&2
            exit 2
            ;;
    esac
}

DEPLOY_EPOCH=$(to_epoch "$DEPLOY_TIME") || {
    echo "compute_next_checkpoint.sh: cannot parse deploy_time '$DEPLOY_TIME'" >&2
    exit 2
}

# Find the next offset after $LAST_OFFSET.
next_offset=""
if [ -z "$LAST_OFFSET" ]; then
    next_offset=$(echo "$OFFSETS" | awk '{print $1}')
else
    found=0
    for o in $OFFSETS; do
        if [ "$found" = "1" ]; then
            next_offset="$o"
            break
        fi
        if [ "$o" = "$LAST_OFFSET" ]; then
            found=1
        fi
    done
fi

if [ -z "$next_offset" ]; then
    exit 1
fi

DELTA_SECS=$(offset_to_seconds "$next_offset")
ABS_EPOCH=$((DEPLOY_EPOCH + DELTA_SECS))
ABS_TS=$(from_epoch "$ABS_EPOCH")

printf '%s\t%s\n' "$ABS_TS" "$next_offset"
