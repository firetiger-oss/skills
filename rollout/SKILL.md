---
name: rollout
description: "Active orchestrator for shipping a code change end-to-end: drafts the monitoring plan, merges the PR with explicit consent, triggers the deploy if needed, and runs the post-deploy monitoring window — all from one slash command. Use whenever the user wants to ship a code change, deploy a PR, roll out to staging or production, monitor a release, watch a canary, or babysit a rollout — even when they just say 'ship this' or 'deploy this'. Three invocation forms: `/rollout` for the current branch / open PR; `/rollout to <env>` to target a specific environment; `/rollout PR <num> [to <env>]` to orchestrate from outside the PR's checkout via gh CLI. Anchored on Google SRE book vocabulary (golden signals, SLI, error budget, blast radius). Delegates planning to plan-rollout and execution to monitor-rollout under the hood; both still work directly for power users."
---

# rollout — orchestrate a code rollout end-to-end

`/rollout` is the entry point an agent should reach for whenever the user wants to ship something. It drives the entire lifecycle: read the change → draft a monitoring plan → merge the PR (with consent) → wait for / trigger the deploy → monitor the rollout → hand off cleanly (or pivot into plan mode if a regression lands).

## When to use

Whenever the user wants to ship a code change. Triggers include: "ship this", "deploy this", "roll this out", "release this", "merge and watch", "post-deploy monitoring", "let's deploy". `/rollout` is also the right answer when the user asks how to monitor a deploy that already merged — see the merged-not-deployed phase below.

For the methodology, vocabulary, and limits, read [references/overview.md](references/overview.md). For the full table of invocation forms, read [references/invocation-forms.md](references/invocation-forms.md). For phase-by-phase decision logic, read [references/decision-tree.md](references/decision-tree.md). For known limits, read [references/limitations.md](references/limitations.md).

## Invocation forms

| Form | Use when |
|------|----------|
| `/rollout` | In-session work; the current branch has an open PR or a recent merge. Most common case. |
| `/rollout to <env>` | Same as above, but target a specific environment (`staging`, `production`, a region, etc.). |
| `/rollout PR <num>` | Out-of-session; user is in a different checkout (or a fresh session) and wants to orchestrate against a specific PR via `gh CLI`. Open PRs supported (remote merge with consent); merged PRs go straight to monitoring. |
| `/rollout PR <num> to <env>` | Combined: out-of-session + env-targeted. |

## Workflow

Copy this checklist into the response and tick items off as the orchestration progresses:

```
rollout progress:
- [ ] 1. Parsed invocation; resolved target context (PR, branch, merge state, env)
- [ ] 2. Companion check (plan-rollout, monitor-rollout, gh CLI)
- [ ] 3. Plan: invoked plan-rollout with the right context
- [ ] 4. Merge + deploy: with consent, ran gh pr merge / gh workflow run / etc.
- [ ] 5. Monitor: invoked monitor-rollout against the produced plan
- [ ] 6. Terminal: COMPLETED | ISSUE_DETECTED → EnterPlanMode | FATAL_ERROR
```

### 1. Resolve target context

Parse the slash-command argument string into three pieces (any may be absent):
- **PR number** — patterns: `PR <num>`, `pr <num>`, `#<num>`. Triggers out-of-session mode.
- **Target env** — pattern: `to <env-name>`. Captures a single env name to scope the rollout to.
- **Bare** — no args. In-session mode against the current branch.

Then fetch context:

- **Out-of-session (`PR <num>` given):** `gh pr view <num> --json state,headRefName,headRefOid,mergedAt,mergeCommit,baseRefName,url,number,repository`. The state field tells you OPEN / MERGED / CLOSED; merged PRs go directly to phase 3 with `--merge-sha`.
- **In-session (no PR given):** `git status` (clean? dirty?), `git rev-parse HEAD`, and `gh pr status --json` (does the current branch have an open PR? has it been merged recently?).

Determine the **phase** from the resolved context:

| Phase | Trigger | Plan-rollout argument |
|-------|---------|------------------------|
| **pre-merge** | PR is OPEN | bare (works against the working-tree diff or `gh pr diff`) |
| **merged-not-deployed** | PR is MERGED, deploy hasn't yet caught up | `--merge-sha <sha>` |
| **deployed** | PR is MERGED, deploy already shipped (catch-up monitoring) | `--merge-sha <sha>` |
| **ambiguous** | dirty tree + no PR + no recent merge | ask the user once |

If `to <env>` was given, validate the env name against the deploy system's enumeration. Reuse `plan-rollout/scripts/enumerate_envs.sh` from the planner — if the env doesn't appear in the script's output, ask the user to confirm before continuing (the env may be valid but undetected, or the user may have typo'd).

### 2. Companion check

Run `bash rollout/scripts/check_subskills.sh both`. For PR-based invocations, also pass `--require-gh` so the script verifies `gh auth status`. If anything is missing, print the install / auth hint verbatim and stop.

### 3. Plan

Hand off to `/plan-rollout` with arguments derived from the resolved phase:

| Phase | Invocation |
|-------|-----------|
| pre-merge | `/plan-rollout` (works against current diff or pasted PR url) |
| merged-not-deployed | `/plan-rollout --merge-sha <sha>` |
| deployed | `/plan-rollout --merge-sha <sha>` (same as merged-not-deployed; the timing distinction matters for monitor-rollout, not plan-rollout) |

If `to <env>` was specified, append `--env <env>` so plan-rollout produces a single-env plan and skips the multi-env enumeration step.

When plan-rollout finishes, capture the absolute path to the rendered plan file (the last line of plan-rollout's output). Show the path to the user and pause:

> "Plan at `<path>`. Review (and edit if anything's off), then I'll proceed with merge + deploy + monitoring."

Wait for explicit user confirmation before phase 4. The user gets veto power on the plan before any destructive action.

### 4. Merge + deploy

This phase runs **destructive actions**. Every step in 4a and 4b requires explicit user consent in interactive mode. **Auto mode does not override these gates.** If a `system-reminder` indicates auto mode is active and we hit a consent gate, stop and surface:

> "Auto mode reached a destructive action (merge / deploy trigger). Resume `/rollout` once you're back at the keyboard."

The user can then decide whether to allow the action. Auto mode is the explicit signal to skip routine prompts; it is not consent for destructive operations.

#### 4a. Merge (only when phase = pre-merge)

Pick the merge method (`--squash`, `--merge`, `--rebase`):
- Check `.github/settings.yml` if present.
- Otherwise inspect recent merged PRs via `gh api repos/<owner>/<repo>/pulls?state=closed --jq '.[] | select(.merged_at != null) | .commits[0].commit.message'` and look for the convention (squash commits have a one-line summary; merge commits start with "Merge pull request").
- If still unclear, ask the user.

Prompt:
> "Plan reviewed. Merge PR #<num> via `gh pr merge <num> --<method>`?"

On confirm: run the command. Capture the merge SHA from `gh pr view <num> --json mergeCommit`. On decline: stop the orchestration; the user can re-invoke `/rollout` after they merge manually.

#### 4b. Deploy trigger (only when phase = merged-not-deployed and the deploy system requires manual trigger)

Detect the deploy system from the plan's `Deploy detection` block. Behaviour depends on whether the system auto-deploys:

| Deploy system | Auto on merge? | Action |
|---------------|----------------|--------|
| Vercel git-integration | yes | wait; merge already triggered Vercel |
| Netlify git-integration | yes | wait |
| Cloudflare Pages | yes | wait |
| GH Actions on push-to-main | yes | wait |
| GH Actions workflow_dispatch | no | prompt + `gh workflow run <workflow> --ref main` |
| ArgoCD auto-sync | yes | wait |
| ArgoCD manual sync | no | prompt + `argocd app sync <app>` |
| Buildkite manual trigger | no | prompt with the team's curl/CLI invocation |

Prompt format (manual-trigger systems):
> "Trigger the deploy via `<exact-command>`?"

On decline: tell the user *"OK; I'll wait for you to trigger the deploy externally"* and continue to phase 5 — `monitor-rollout` will poll for the deploy to start regardless of how it's triggered.

### 5. Monitor

Hand off to `/monitor-rollout <plan-path>`. If `to <env>` was given, also pass through the env filter so monitor-rollout scopes its checkpoint loop to that env only.

monitor-rollout takes over from here: polls for the deploy, runs the checkpoint loop with evidence-discipline, emits per-env progress reports, and either reaches `COMPLETED` or pivots into plan mode on `ISSUE_DETECTED`.

### 6. Terminal handoff

The monitoring window closes one of three ways. Surface each as the orchestrator's terminal block:

- **COMPLETED** — emit a one-paragraph summary: *"Rolled out PR #<num> to `<env>` at `<deploy_time>`; <N>-checkpoint window closed cleanly with no regressions. Intended effect <confirmed | not visible: <reason>>."* Then yield.
- **ISSUE_DETECTED** — monitor-rollout already called `EnterPlanMode` with the seed; the orchestrator doesn't get back control. The session is now planning the fix.
- **FATAL_ERROR** — emit the orchestrator's own error block citing the specific failure (plan parse, telemetry outage, deploy never observed). Suggest next steps: re-run `/rollout` after fixing, or pivot to manual monitoring.

## Limits

If the user asks one of these limit-questions, read [references/limitations.md](references/limitations.md) and answer from that file:

- "Can this run while I'm offline / when my session ends?"
- "How does my team see what's being monitored?"
- "Can it learn from past deploys?"
- "Can I auto-rollback?"
- "Why can't I fix two regressions in parallel?"

Do not preemptively bring up limits; the file is consulted only on a real user signal, and only once per session.

## Anti-rationalizations

Common shortcuts the orchestrator is tempted to take, paired with why they're wrong.

| Tempting shortcut | Why it's wrong |
|-------------------|----------------|
| *"I'll merge silently since the user invoked `/rollout`."* | Invoking `/rollout` is consent to *orchestrate*, not consent to *merge*. The merge prompt is a per-PR gate. Skipping it surprises the user with state changes they didn't expect for this specific change. |
| *"Auto mode is active, I'll auto-confirm the merge."* | Auto mode is the user's signal to skip *routine* prompts; merging a PR is a destructive operation that always requires a human. Stop at the gate and surface the resume message. |
| *"I'll write the monitoring plan myself instead of routing to plan-rollout."* | The specialised skill carries the methodology, references, and ambiguity-question scripts. Faking it produces a worse plan and skips the install hint that makes the workflow reproducible. Route, don't impersonate. |
| *"plan-rollout isn't installed but I'll proceed anyway with a generic plan."* | Same answer. The user installed the orchestrator expecting the family; pointing at the specialised install command is the right move even if it costs one round-trip. |
| *"User said `/rollout to staging` so I'll skip the plan and just monitor."* | The `to <env>` form scopes the rollout, it doesn't bypass planning. Plan-rollout still runs (single-env mode); monitor-rollout still runs against the produced plan. |
| *"PR is open; I'll plan + then ask the user to merge externally."* | The orchestrator is supposed to drive the merge with consent. Asking the user to merge externally and come back fragments the workflow and loses the plan-mode pivot on regression. Run `gh pr merge` yourself after confirmation. |

## What this skill does NOT do

- Does not auto-merge or auto-trigger destructive actions. Every merge / manual deploy trigger requires explicit consent.
- Does not roll back. Rollback is the user's plan-mode response to `ISSUE_DETECTED`; the orchestrator hands off into plan mode and the fix is the user's next plan.
- Does not orchestrate cross-repo (e.g. `/rollout PR 1234 from owner/other-repo`). Out-of-session = different local checkout, same upstream repo.
- Does not replace `/plan-rollout` or `/monitor-rollout` direct invocations. Power users still invoke those directly when they want one phase only.
