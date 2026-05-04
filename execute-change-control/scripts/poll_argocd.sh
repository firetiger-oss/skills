#!/usr/bin/env bash
# Poll ArgoCD for an app sync matching the given commit (or descendant of it).
#
# Usage: poll_argocd.sh <app-name> <merge-sha> [repo-path]
#
# repo-path: optional path to a local checkout used for ancestry checking
# (default: current directory). The script assumes `git merge-base --is-ancestor`
# can verify whether merge-sha is an ancestor of the deployed revision.
#
# Exit 0 on match (with sync time on stdout); exit 1 if not yet matched.
set -u

APP="${1:-}"
SHA="${2:-}"
REPO_PATH="${3:-.}"

if [ -z "$APP" ] || [ -z "$SHA" ]; then
    echo "usage: poll_argocd.sh <app-name> <merge-sha> [repo-path]" >&2
    exit 2
fi

if ! command -v argocd >/dev/null 2>&1; then
    echo "poll_argocd.sh: argocd CLI not found on PATH" >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "poll_argocd.sh: jq required" >&2
    exit 2
fi

JSON=$(argocd app get "$APP" -o json 2>/dev/null) || {
    echo "poll_argocd.sh: argocd app get $APP failed (login? wrong cluster?)" >&2
    exit 2
}

SYNC_STATUS=$(echo "$JSON" | jq -r '.status.sync.status // empty')
HEALTH_STATUS=$(echo "$JSON" | jq -r '.status.health.status // empty')
DEPLOYED_REV=$(echo "$JSON" | jq -r '.status.sync.revision // empty')
RECONCILED_AT=$(echo "$JSON" | jq -r '.status.reconciledAt // .status.operationState.finishedAt // empty')

# Quick exit: not synced or not healthy yet.
if [ "$SYNC_STATUS" != "Synced" ] || [ "$HEALTH_STATUS" != "Healthy" ]; then
    exit 1
fi

if [ -z "$DEPLOYED_REV" ]; then
    exit 1
fi

# Match: deployed-rev equals merge-sha, OR merge-sha is an ancestor of deployed-rev.
if [ "$DEPLOYED_REV" = "$SHA" ]; then
    echo "${RECONCILED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    exit 0
fi

# Ancestry check requires a local git checkout.
if [ -d "$REPO_PATH/.git" ]; then
    if (cd "$REPO_PATH" && git merge-base --is-ancestor "$SHA" "$DEPLOYED_REV" 2>/dev/null); then
        echo "${RECONCILED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
        exit 0
    fi
fi

exit 1
