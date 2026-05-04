# Buildkite (deploy detection)

## Detection

The repo uses Buildkite when `.buildkite/pipeline.y*ml` exists or the `BUILDKITE_*` env vars are set. The CLI is `buildkite-agent`; `BUILDKITE_API_TOKEN` is required for API queries.

## Single-env deploy detection

Buildkite exposes pipelines and builds; deploys are typically a build step (or a separate trigger pipeline).

```
curl -sH "Authorization: Bearer $BUILDKITE_API_TOKEN" \
  "https://api.buildkite.com/v2/organizations/$BUILDKITE_ORG/pipelines/deploy/builds?branch=main&commit=<merge_sha>&per_page=1" \
  | jq '.[0] | {state, finished_at, commit}'
```

Expected match:
- `state == "passed"`
- `commit == <merge_sha>` (or an ancestor — see ArgoCD recipe for ancestry handling)

## Multi-env (multiple pipelines)

If the team uses `deploy-staging` and `deploy-prod` as separate pipelines:

```
# staging
curl -sH "Authorization: Bearer $BUILDKITE_API_TOKEN" \
  "https://api.buildkite.com/v2/organizations/$BUILDKITE_ORG/pipelines/deploy-staging/builds?branch=main&commit=<merge_sha>&per_page=1"

# prod
curl -sH "Authorization: Bearer $BUILDKITE_API_TOKEN" \
  "https://api.buildkite.com/v2/organizations/$BUILDKITE_ORG/pipelines/deploy-prod/builds?branch=main&commit=<merge_sha>&per_page=1"
```

## Multi-env (one pipeline, multiple deploy steps)

When `deploy.pipeline.yml` has separate steps for each env (matrix-style), inspect the build's jobs:

```
BUILD_NUMBER=$(curl ... | jq '.[0].number')
curl -sH "Authorization: Bearer $BUILDKITE_API_TOKEN" \
  "https://api.buildkite.com/v2/organizations/$BUILDKITE_ORG/pipelines/deploy/builds/$BUILD_NUMBER" \
  | jq '.jobs[] | select(.step_key | startswith("deploy-")) | {step_key, state, finished_at}'
```

Match per-env by `step_key` (e.g. `deploy-staging`, `deploy-prod-us-east-1`).

## Block steps / manual approvals

Buildkite block steps appear as `state: blocked`. The executor treats blocked as not-yet-deployed.

## Common pitfalls

- **`buildkite-agent` is the runtime CLI** for use *inside* a build, not for querying. Use `curl` + REST API for deploy-detection.
- **Multiple branches with the same commit.** Filter on `branch` to disambiguate.
- **Org name in the URL.** Buildkite URL paths are `org-slug`-based, not the human-readable org name.
