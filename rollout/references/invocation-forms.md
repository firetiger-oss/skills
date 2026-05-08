# Invocation forms

`/rollout` accepts a freeform argument string. The parser recognises three orthogonal pieces, all optional:

- **PR number** — patterns: `PR <num>`, `pr <num>`, `#<num>`. When given, switches to out-of-session mode.
- **Target environment** — pattern: `to <env-name>`. When given, scopes the entire rollout to that single env.
- **(implicit)** Bare invocation with no recognised tokens → in-session mode against the current branch.

Token order is flexible: `/rollout PR 1234 to staging` and `/rollout to staging PR 1234` both parse. Unknown tokens trigger a one-shot clarification: *"I parsed `<recognised>` from your invocation but didn't recognise `<unknown>`. Did you mean …?"*

## The four shapes

| Shape | Args parsed | Resulting behaviour |
|-------|-------------|---------------------|
| `/rollout` | none | In-session; resolve context from current branch + `gh pr status`. Phase = pre-merge / merged-not-deployed / deployed. Multi-env if the deploy system fans out. |
| `/rollout to <env>` | `to <env>` | In-session, scoped to `<env>`. Plan-rollout invoked with `--env <env>`. Monitor scopes to `<env>` only. |
| `/rollout PR <num>` | `PR <num>` | Out-of-session; resolve context from `gh pr view <num>`. No local checkout required. State (OPEN / MERGED) determines the phase. Multi-env unless the PR's deploy system targets a single env. |
| `/rollout PR <num> to <env>` | both | Out-of-session, scoped. Combines the previous two. |

## Parsing in practice

The agent parses the args in its own thinking — no parser script needed. Recognise these patterns:

```
/rollout                            → bare
/rollout to staging                 → env: "staging"
/rollout to prod-us-east-1          → env: "prod-us-east-1"
/rollout PR 1234                    → pr: 1234
/rollout pr 1234                    → pr: 1234
/rollout #1234                      → pr: 1234
/rollout PR 1234 to staging         → pr: 1234, env: "staging"
/rollout to staging PR 1234         → pr: 1234, env: "staging"  (token order flexible)
/rollout #1234 to prod              → pr: 1234, env: "prod"
```

These trigger the clarification prompt:

```
/rollout 1234                       → ambiguous (number alone — is that a PR? a tag? a sha?)
/rollout staging                    → ambiguous (env name without "to")
/rollout PR feat/foo                → ambiguous (PR token expects a number)
/rollout PR 1234 to                 → ambiguous (incomplete env)
```

When in doubt, ask once. Don't guess.

## Resolving the target context

After parsing, fetch context per the parsed args:

### PR-based (out-of-session)

```bash
gh pr view <num> --json state,headRefName,headRefOid,mergedAt,mergeCommit,baseRefName,url,number,repository
```

The fields you need:
- `state` — OPEN / MERGED / CLOSED. CLOSED-without-merge → refuse.
- `headRefOid` — the head commit. Used for `gh pr diff <num>` (pre-merge) and as the diff anchor.
- `mergeCommit.oid` — the merge SHA. Used for `--merge-sha` (merged-not-deployed and deployed).
- `mergedAt` — timestamp of the merge. If `null`, PR is open.
- `baseRefName` — the base branch (usually `main`). Useful for diff base.
- `url`, `number`, `repository` — for human-readable status messages.

### Bare (in-session)

```bash
git status --porcelain                        # dirty?
git rev-parse --abbrev-ref HEAD               # current branch
git rev-parse HEAD                            # current commit
gh pr status --json currentBranch             # open PR for this branch?
```

If `gh pr status` returns a PR for the current branch, use its data the same way as the PR-based path. If not, check whether HEAD is on `main` (or the deploy branch) and look back via `git log --oneline -10` for a recent merge commit — that's the `merged-not-deployed` case.

### Env validation (when `to <env>` was given)

```bash
bash plan-rollout/scripts/enumerate_envs.sh
```

If `<env>` appears verbatim in the script's output, proceed. If not, ask the user once before continuing — the env may be valid but undetected (e.g. an MCP-managed env), or the user may have typo'd. Don't silently expand to an env list that ignores the filter.

## What the orchestrator passes to plan-rollout / monitor-rollout

After context resolution:

| Phase | plan-rollout invocation |
|-------|-------------------------|
| pre-merge | `/plan-rollout` (works against current diff or `gh pr diff <num>`) |
| pre-merge + env | `/plan-rollout --env <env>` |
| merged-not-deployed | `/plan-rollout --merge-sha <sha>` |
| merged-not-deployed + env | `/plan-rollout --merge-sha <sha> --env <env>` |
| deployed | `/plan-rollout --merge-sha <sha>` (catch-up; same as merged-not-deployed) |
| deployed + env | `/plan-rollout --merge-sha <sha> --env <env>` |

monitor-rollout invocation is uniform across phases: `/monitor-rollout <plan-path> [--env <env>]`. The plan-path is captured from plan-rollout's last line of output.
