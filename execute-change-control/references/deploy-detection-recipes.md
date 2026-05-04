# Deploy-detection recipes (cross-reference)

This file exists so the executor's SKILL.md can stay short. The actual recipes live in the planner's reference set, where they're authored as part of plan-writing — but the executor needs the same commands at runtime.

## Cross-references

For each deploy system, read the corresponding planner reference:

- GitHub Actions → [`plan-change-control/references/github-actions.md`](../../plan-change-control/references/github-actions.md)
- Buildkite → [`plan-change-control/references/buildkite.md`](../../plan-change-control/references/buildkite.md)
- ArgoCD → [`plan-change-control/references/argocd.md`](../../plan-change-control/references/argocd.md)
- Vercel → [`plan-change-control/references/vercel.md`](../../plan-change-control/references/vercel.md)

## Polling helpers

The plan's `Deploy detection` block contains the exact command for each env. The `scripts/` directory in this skill provides per-system wrappers that handle the polling loop + match-condition evaluation:

- `scripts/poll_github_actions.sh` — wraps `gh run list` / `gh run view`, handles matrix-job parsing.
- `scripts/poll_buildkite.sh` — wraps the Buildkite REST API.
- `scripts/poll_argocd.sh` — wraps `argocd app get`, includes ancestry check via `git merge-base`.
- `scripts/poll_vercel.sh` — wraps `vercel ls --json`.

Use these scripts when the plan's deploy-detection block names a known system; fall back to running the plan's command verbatim when the script doesn't cover an edge case.

## When the plan's command needs adjustment at runtime

Sometimes the plan was written against a placeholder (the user didn't yet know the merge_sha at plan-write time, so the command has `<merge_sha>` literal). At execute-time:
1. Resolve the actual merge_sha from `git log -1 --format=%H` against the merged commit (the user can paste it, or `gh pr view <pr> --json mergeCommit` if a PR url is in the plan).
2. Substitute it into the command.
3. Run.

If the plan doesn't carry an unambiguous merge_sha and the user can't tell you, ask once before polling.
