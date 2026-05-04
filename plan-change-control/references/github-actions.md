# GitHub Actions (deploy detection)

## Detection

The repo uses GitHub Actions when `.github/workflows/*.y*ml` exists. The deploy workflow is usually one of: `deploy.yml`, `release.yml`, `cd.yml`, `production.yml`. Inspect workflow files to find the one that ships to production.

The `gh` CLI must be authenticated (`gh auth status`).

## Single-env deploy detection

```
gh run list --workflow=deploy.yml --branch=main --limit=1 --json status,conclusion,headSha
```

Expected match:
- `status == "completed"`
- `conclusion == "success"`
- `headSha == <merge_sha>`

The poll loop runs this every 30 seconds. The deploy_time is recorded as the moment `status` first transitions to `completed` with success.

## Matrix-strategy multi-env

When `deploy.yml` uses `strategy.matrix` to fan out across envs:

```yaml
strategy:
  matrix:
    env: [staging, prod-us-east-1, prod-eu-west-1]
```

Each matrix entry is a separate job. Use `gh run view <run-id> --json jobs` to get per-matrix-entry status:

```
gh run list --workflow=deploy.yml --branch=main --limit=1 --json databaseId,headSha
# capture databaseId and headSha; verify headSha matches merge_sha

gh run view <databaseId> --json jobs --jq '.jobs[] | {name, status, conclusion}'
# match each matrix entry's job by name (e.g. "deploy (prod-us-east-1)")
```

In the plan, give each environment its own deploy-detection block:

```
#### prod-us-east-1
Deploy detection:
  RUN_ID=$(gh run list --workflow=deploy.yml --branch=main --limit=1 --json databaseId,headSha --jq 'select(.[0].headSha=="<merge_sha>") | .[0].databaseId')
  gh run view "$RUN_ID" --json jobs --jq '.jobs[] | select(.name | contains("prod-us-east-1")) | {status, conclusion}'
Match: status==completed && conclusion==success
```

## Multi-workflow setups

Some teams use one workflow per env (`deploy-staging.yml`, `deploy-prod.yml`). Each env's deploy-detection then references the right workflow file.

## Reusable workflows + downstream jobs

When the deploy uses a reusable workflow (`uses: org/repo/.github/workflows/deploy.yml@main`), the run shows in the *caller* repo, not the reusable-workflow repo. Use `gh run list --repo <caller>`.

## OIDC / approval gates

If the prod env requires an approval, the workflow `status` will be `waiting` while the gate is pending. The poll loop should treat `waiting` as not-yet-deployed (deploy_time isn't set until the approval is granted and the deploy actually ran).

## Common pitfalls

- **`branch` filter.** If the deploy workflow runs on `push` to `main`, filter `--branch=main`. If it runs on tag, use `--event=push --json headBranch` and match the tag pattern.
- **Cancelled runs.** A re-run replaces the original; always sort by latest and verify `headSha`.
- **Multiple PRs merged in quick succession.** The first PR's merge_sha may not equal the final deployed SHA. The executor handles ancestry (a merge sha is "deployed" if it's an ancestor of the deployed sha) — see [`plan-change-control` step 8 in the SKILL.md].
