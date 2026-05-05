# Deploy-detection recipes (cross-reference)

This file exists so the executor's SKILL.md can stay short. The actual recipes live in the planner's reference set, where they're authored as part of plan-writing — but the executor needs the same commands at runtime.

## Cross-references

For each deploy system, read the corresponding planner reference:

- GitHub Actions → [`plan-rollout/references/github-actions.md`](../../plan-rollout/references/github-actions.md)
- Buildkite → [`plan-rollout/references/buildkite.md`](../../plan-rollout/references/buildkite.md)
- ArgoCD → [`plan-rollout/references/argocd.md`](../../plan-rollout/references/argocd.md)
- Vercel → [`plan-rollout/references/vercel.md`](../../plan-rollout/references/vercel.md)

## Polling helpers

The plan's `Deploy detection` block contains the exact command for each env. The `scripts/` directory in this skill provides per-system wrappers that handle the polling loop + match-condition evaluation:

- `scripts/poll_github_actions.sh` — wraps `gh run list` / `gh run view`, handles matrix-job parsing.
- `scripts/poll_buildkite.sh` — wraps the Buildkite REST API.
- `scripts/poll_argocd.sh` — wraps `argocd app get`, includes ancestry check via `git merge-base`.
- `scripts/poll_vercel.sh` — wraps `vercel ls --json`.
- `scripts/poll_http.sh` — generic HTTP probe; for git-integration deploys (Vercel app, Netlify, Cloudflare Pages, Render auto-deploy) and any generic deploy-system that exposes only an HTTP surface.

Use these scripts when the plan's deploy-detection block names a known system; fall back to running the plan's command verbatim when the script doesn't cover an edge case.

## When deploy detection is HTTP-only (git-integration, generic webhooks)

Some deploy systems (Vercel git-integration via the GitHub app, Netlify git-integration, Cloudflare Pages, Render auto-deploy) expose no API the planner can poll directly. The deploy is "live" when:
- The site's home URL serves a 200 response, AND
- The response body / headers carry a build identifier matching the merged commit.

`scripts/poll_http.sh` handles this generically. Three match modes:

```bash
# Match on HTTP status (simplest case)
bash scripts/poll_http.sh https://example.com --match-status 200

# Match on body content (build identifier embedded in response)
bash scripts/poll_http.sh https://example.com/version --match-body-contains "abc123def"

# Match on response header (e.g. X-Build-Sha set by deploy system)
bash scripts/poll_http.sh https://example.com --match-header "X-Build-Sha=abc123def"
```

Exit 0 on match, with a UTC timestamp on stdout (the recorded `deploy_time`). Exit 1 if not yet matched (caller retries on the 30s cadence).

In the plan's `Deploy detection` block:

```
#### production
Deploy detection:
  bash poll_http.sh https://example.com/api/version --match-body-contains "<merge_sha>"
Match: HTTP 200 AND body contains the merged commit SHA
```

## When the plan's command needs adjustment at runtime

Sometimes the plan was written against a placeholder (the user didn't yet know the merge_sha at plan-write time, so the command has `<merge_sha>` literal). At execute-time:
1. Resolve the actual merge_sha from `git log -1 --format=%H` against the merged commit (the user can paste it, or `gh pr view <pr> --json mergeCommit` if a PR url is in the plan).
2. Substitute it into the command.
3. Run.

If the plan doesn't carry an unambiguous merge_sha and the user can't tell you, ask once before polling.
