#!/usr/bin/env bash
# Poll Buildkite for a deploy build matching the given pipeline + commit.
#
# Usage: poll_buildkite.sh <pipeline-slug> <branch> <merge-sha> [step-key]
#
# Requires BUILDKITE_API_TOKEN and BUILDKITE_ORG env vars.
#
# Exit 0 on match (with finished_at on stdout); exit 1 if not yet matched.
set -u

PIPELINE="${1:-}"
BRANCH="${2:-}"
SHA="${3:-}"
STEP_KEY="${4:-}"

if [ -z "$PIPELINE" ] || [ -z "$BRANCH" ] || [ -z "$SHA" ]; then
    echo "usage: poll_buildkite.sh <pipeline> <branch> <sha> [step-key]" >&2
    exit 2
fi

if [ -z "${BUILDKITE_API_TOKEN:-}" ] || [ -z "${BUILDKITE_ORG:-}" ]; then
    echo "poll_buildkite.sh: BUILDKITE_API_TOKEN and BUILDKITE_ORG env vars required" >&2
    exit 2
fi

API="https://api.buildkite.com/v2"
URL="$API/organizations/$BUILDKITE_ORG/pipelines/$PIPELINE/builds?branch=$BRANCH&commit=$SHA&per_page=1"

RESPONSE=$(curl -sS -H "Authorization: Bearer $BUILDKITE_API_TOKEN" "$URL") || {
    echo "poll_buildkite.sh: API request failed" >&2
    exit 2
}

# Top-level build state.
if [ -z "$STEP_KEY" ]; then
    STATE=$(echo "$RESPONSE" | jq -r '.[0].state // empty')
    FINISHED_AT=$(echo "$RESPONSE" | jq -r '.[0].finished_at // empty')

    if [ "$STATE" = "passed" ] && [ -n "$FINISHED_AT" ]; then
        echo "$FINISHED_AT"
        exit 0
    fi
    exit 1
fi

# Per-step status: fetch the build's jobs and find the one with the matching step_key.
BUILD_NUMBER=$(echo "$RESPONSE" | jq -r '.[0].number // empty')
if [ -z "$BUILD_NUMBER" ]; then
    exit 1
fi

BUILD_URL="$API/organizations/$BUILDKITE_ORG/pipelines/$PIPELINE/builds/$BUILD_NUMBER"
BUILD_JSON=$(curl -sS -H "Authorization: Bearer $BUILDKITE_API_TOKEN" "$BUILD_URL")

STATE=$(echo "$BUILD_JSON" | jq -r --arg key "$STEP_KEY" '
    .jobs[] | select(.step_key == $key) | .state
' | head -1)
FINISHED_AT=$(echo "$BUILD_JSON" | jq -r --arg key "$STEP_KEY" '
    .jobs[] | select(.step_key == $key) | .finished_at
' | head -1)

if [ "$STATE" = "passed" ] && [ -n "$FINISHED_AT" ] && [ "$FINISHED_AT" != "null" ]; then
    echo "$FINISHED_AT"
    exit 0
fi

exit 1
