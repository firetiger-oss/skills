#!/usr/bin/env bash
# Poll Vercel for a deployment matching the given commit + target.
#
# Usage: poll_vercel.sh <merge-sha> <target>
#
# target: production | preview | <custom env name>
#
# Requires VERCEL_TOKEN env var. The vercel CLI must be on PATH.
#
# Exit 0 on match (with createdAt on stdout); exit 1 if not yet matched.
set -u

SHA="${1:-}"
TARGET="${2:-production}"

if [ -z "$SHA" ]; then
    echo "usage: poll_vercel.sh <merge-sha> [target]" >&2
    exit 2
fi

if ! command -v vercel >/dev/null 2>&1; then
    echo "poll_vercel.sh: vercel CLI not found on PATH" >&2
    exit 2
fi

if [ -z "${VERCEL_TOKEN:-}" ]; then
    echo "poll_vercel.sh: VERCEL_TOKEN env var required" >&2
    exit 2
fi

JSON=$(vercel ls --json --token="$VERCEL_TOKEN" 2>/dev/null) || {
    echo "poll_vercel.sh: vercel ls failed" >&2
    exit 2
}

# Find a deployment matching the SHA + target with state READY.
MATCH=$(echo "$JSON" | jq -r --arg sha "$SHA" --arg t "$TARGET" '
    .[] | select(
        .target == $t
        and (.meta.githubCommitSha == $sha or .meta.gitlabCommitSha == $sha or .meta.bitbucketCommitSha == $sha)
        and .state == "READY"
    ) | .createdAt
' | head -1)

if [ -n "$MATCH" ] && [ "$MATCH" != "null" ]; then
    # Vercel returns a unix epoch in ms; convert to RFC3339.
    SECONDS=$((MATCH / 1000))
    if date --version 2>/dev/null | grep -q GNU; then
        date -u -d "@$SECONDS" +"%Y-%m-%dT%H:%M:%SZ"
    else
        # macOS BSD date
        date -u -r "$SECONDS" +"%Y-%m-%dT%H:%M:%SZ"
    fi
    exit 0
fi

exit 1
