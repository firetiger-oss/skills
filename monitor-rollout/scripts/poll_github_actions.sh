#!/usr/bin/env bash
# Poll GitHub Actions for a deploy run matching the given workflow + commit.
#
# Usage: poll_github_actions.sh <workflow-file> <branch> <merge-sha> [matrix-key]
#
# Examples:
#   poll_github_actions.sh deploy.yml main abc123def         # single-env
#   poll_github_actions.sh deploy.yml main abc123def staging # matrix entry
#
# Exits 0 on match (with deploy_time on stdout as RFC3339); exits 1 if not yet
# matched (caller should retry); exits 2 on usage error or unrecoverable error.
set -u

WORKFLOW="${1:-}"
BRANCH="${2:-}"
SHA="${3:-}"
MATRIX_KEY="${4:-}"

if [ -z "$WORKFLOW" ] || [ -z "$BRANCH" ] || [ -z "$SHA" ]; then
    echo "usage: poll_github_actions.sh <workflow> <branch> <sha> [matrix-key]" >&2
    exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "poll_github_actions.sh: gh CLI not found on PATH" >&2
    exit 2
fi

# Find the latest run for this workflow on this branch with this commit.
RUN_JSON=$(gh run list \
    --workflow="$WORKFLOW" \
    --branch="$BRANCH" \
    --limit=10 \
    --json databaseId,headSha,status,conclusion,updatedAt 2>/dev/null) || {
    echo "poll_github_actions.sh: gh run list failed (auth? network?)" >&2
    exit 2
}

# Pick the run matching the SHA (most recent first).
RUN_ID=$(echo "$RUN_JSON" | jq -r --arg sha "$SHA" '
    map(select(.headSha == $sha)) | first | .databaseId // empty
')

if [ -z "$RUN_ID" ]; then
    # No run yet for this commit. Caller should keep polling.
    exit 1
fi

# Top-level run status check (used when no matrix-key given).
if [ -z "$MATRIX_KEY" ]; then
    STATUS=$(echo "$RUN_JSON" | jq -r --arg sha "$SHA" '
        map(select(.headSha == $sha)) | first | .status
    ')
    CONCLUSION=$(echo "$RUN_JSON" | jq -r --arg sha "$SHA" '
        map(select(.headSha == $sha)) | first | .conclusion
    ')
    UPDATED_AT=$(echo "$RUN_JSON" | jq -r --arg sha "$SHA" '
        map(select(.headSha == $sha)) | first | .updatedAt
    ')

    if [ "$STATUS" = "completed" ] && [ "$CONCLUSION" = "success" ]; then
        echo "$UPDATED_AT"
        exit 0
    fi
    exit 1
fi

# Matrix-job status check: walk the run's jobs and match on job name containing
# the matrix-key.
JOBS_JSON=$(gh run view "$RUN_ID" --json jobs 2>/dev/null) || {
    echo "poll_github_actions.sh: gh run view $RUN_ID failed" >&2
    exit 2
}

JOB_STATUS=$(echo "$JOBS_JSON" | jq -r --arg key "$MATRIX_KEY" '
    .jobs[] | select(.name | contains($key)) | .status
' | head -1)
JOB_CONCLUSION=$(echo "$JOBS_JSON" | jq -r --arg key "$MATRIX_KEY" '
    .jobs[] | select(.name | contains($key)) | .conclusion
' | head -1)
JOB_COMPLETED=$(echo "$JOBS_JSON" | jq -r --arg key "$MATRIX_KEY" '
    .jobs[] | select(.name | contains($key)) | .completedAt
' | head -1)

if [ "$JOB_STATUS" = "completed" ] && [ "$JOB_CONCLUSION" = "success" ]; then
    echo "$JOB_COMPLETED"
    exit 0
fi

exit 1
