#!/usr/bin/env bash
# Poll an HTTP endpoint and exit 0 when a match condition holds.
#
# Usage: poll_http.sh <url> <match-mode> <match-value>
#
# match-mode:
#   --match-status <code>          # exit 0 when HTTP status equals <code>
#   --match-body-contains <text>   # exit 0 when response body contains <text>
#   --match-header <name=value>    # exit 0 when response header matches
#
# Designed for the http-poll path: deploy systems with no API (Vercel
# git-integration, Netlify, Cloudflare Pages, generic webhook-driven CI).
# The plan's Deploy detection block names this script + the match args.
#
# Exits 0 on match (with current ISO timestamp on stdout); exits 1 if not yet
# matched (caller should retry); exits 2 on usage error.
set -u

URL="${1:-}"
MATCH_MODE="${2:-}"
MATCH_VALUE="${3:-}"

if [ -z "$URL" ] || [ -z "$MATCH_MODE" ] || [ -z "$MATCH_VALUE" ]; then
    cat >&2 <<EOF
usage: poll_http.sh <url> <match-mode> <match-value>

  match-mode:
    --match-status <code>           exit 0 when HTTP status == <code>
    --match-body-contains <text>    exit 0 when body contains <text>
    --match-header <name=value>     exit 0 when response header matches
EOF
    exit 2
fi

# 5-second timeout — the deploy poll cadence is 30s, so 5s is plenty without
# wedging the loop on a hung endpoint.
TIMEOUT_SECS=5

case "$MATCH_MODE" in
    --match-status)
        actual=$(curl -sS --max-time "$TIMEOUT_SECS" -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null) || exit 1
        if [ "$actual" = "$MATCH_VALUE" ]; then
            date -u +"%Y-%m-%dT%H:%M:%SZ"
            exit 0
        fi
        exit 1
        ;;
    --match-body-contains)
        body=$(curl -fsS --max-time "$TIMEOUT_SECS" "$URL" 2>/dev/null) || exit 1
        if printf '%s' "$body" | grep -qF -- "$MATCH_VALUE"; then
            date -u +"%Y-%m-%dT%H:%M:%SZ"
            exit 0
        fi
        exit 1
        ;;
    --match-header)
        # MATCH_VALUE is "name=value"
        local_name="${MATCH_VALUE%%=*}"
        local_value="${MATCH_VALUE#*=}"
        headers=$(curl -sIS --max-time "$TIMEOUT_SECS" "$URL" 2>/dev/null) || exit 1
        # Header lines are "name: value"
        if printf '%s' "$headers" | grep -iE "^${local_name}:\s*${local_value}\b" >/dev/null; then
            date -u +"%Y-%m-%dT%H:%M:%SZ"
            exit 0
        fi
        exit 1
        ;;
    *)
        echo "poll_http.sh: unknown match mode '$MATCH_MODE'" >&2
        exit 2
        ;;
esac
