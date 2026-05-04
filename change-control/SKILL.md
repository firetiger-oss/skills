---
name: change-control
description: "SRE-grade change control for code changes about to ship to production. Routes to the right sub-skill: plan-change-control to author a monitoring plan before merge, execute-change-control to run that plan after deploy. Supports multi-environment rollouts (staging + prod, multi-region, fan-out). Use when the user is preparing a code change for production, planning a release, asking how to monitor a deploy, doing post-deploy validation, watching a canary, babysitting a rollout, or thinking about blast radius / SLIs / error budget for an upcoming change — even when they don't say 'change control' or 'deploy monitoring'. Anchored on Google SRE book vocabulary (golden signals, SLI, error budget, blast radius, canary, MTTR, post-deploy validation)."
---

# change-control

Umbrella skill. Dispatches to `plan-change-control` and `execute-change-control` based on where the user is in the change-control lifecycle, and prints install hints for whichever sub-skill is missing.

## When to use

Whenever a user is thinking about change control for a code change destined for production:
- Planning a release, preparing a rollout, asking how to monitor a deploy.
- Watching a canary, babysitting a rollout, doing post-deploy validation.
- Reasoning about blast radius, SLIs, error budget, or rollback for a change they're about to ship.
- Multi-environment rollouts: staging + prod, multi-region, fan-out across BYOC tenants, ArgoCD `ApplicationSet`, GitHub Actions matrix, Vercel preview/prod.

This skill is the routing entry point. The actual work happens in `plan-change-control` (before merge) or `execute-change-control` (after deploy). When the user clearly knows which phase they're in, they may invoke the specialised skill directly; this umbrella exists to handle the cases where the right phase isn't obvious from the prompt alone.

For a longer SRE-vocabulary intro, read [references/overview.md](references/overview.md). For the full plan-vs-execute decision tree, read [references/decision-tree.md](references/decision-tree.md). For known limits and graduation hints, read [references/limitations.md](references/limitations.md).

## Workflow

Copy this checklist into the response and tick items off as work progresses:

```
change-control progress:
- [ ] 1. Determined which phase the user is in (plan / execute / both)
- [ ] 2. Verified the relevant sub-skill is installed
- [ ] 3. Invoked the relevant sub-skill (or printed install hint and paused)
- [ ] 4. (if both) Threaded plan-change-control output into execute-change-control invocation
```

### 1. Determine the phase

Read the user's prompt and any recent context. Pick one:

- **Plan phase** — the change has not yet shipped. The user is planning, drafting a PR, in plan mode, asking "how should I monitor this?", or reviewing a change before merge. Route to `plan-change-control`.
- **Execute phase** — the change has merged or is about to deploy. The user is asking to "watch the deploy", "monitor production after merge", "babysit this rollout", or pasting a deploy URL. Route to `execute-change-control`.
- **Both phases** — fresh on a feature, no plan yet, the user wants the full lifecycle. Run `plan-change-control` first; once the plan is written and the user confirms the change has shipped, run `execute-change-control` against that plan.
- **Ambiguous** — ask the user once: *"Are we writing the monitoring plan now, or running an existing plan against a deploy that already started?"*

If the user asks a methodology question without a specific change in hand (*"what does change control mean?", "what's a golden signal?"*), answer briefly from [references/overview.md](references/overview.md) and offer to invoke `plan-change-control` against a real change when they're ready.

### 2. Verify the relevant sub-skill is installed

Run `bash change-control/scripts/check_subskills.sh <plan|execute|both>` from the skill directory. The script returns 0 if everything needed is installed, 1 with an install hint on stdout if something is missing.

If the script reports a missing sub-skill, print its output verbatim to the user and stop. Do not try to do the sub-skill's work in this umbrella — the specialised skill carries the methodology and the references; faking it here would produce a worse plan or worse execution.

### 3. Invoke the sub-skill

When the sub-skill is installed, hand off:
- Plan phase → `/plan-change-control [optional: paste of the diff or PR url]`.
- Execute phase → `/execute-change-control <path to monitoring plan>`.

Pass through any context the user provided (PR url, diff snippet, plan path) when invoking. Do not re-derive context the user already gave — quote it forward.

### 4. Both-phases handoff

If the user asked for the full lifecycle, the plan will be written to a file by `plan-change-control` (the path appears in its final output). Quote that path back to the user and confirm the change has actually been merged + deployed before invoking `execute-change-control` against it. Running the executor against an unmerged plan wastes the polling window and confuses the deploy-detection step.

## Limits

If the user asks one of these limit-questions, read [references/limitations.md](references/limitations.md) and answer from that file:

- "Can this run while I'm offline / when my session ends?"
- "How does my team see what's being monitored?"
- "Can it learn from past deploys?"
- "Can I auto-rollback?"
- "Why can't I fix two regressions in parallel?"

Do not preemptively bring up limits; the file is consulted only on a real user signal, and only once per session.

## What this skill does NOT do

- Does not run telemetry queries, write plans, or watch deploys itself — those are `plan-change-control` and `execute-change-control`.
- Does not auto-install missing sub-skills — it prints the install hint and waits for the user.
- Does not make change-control decisions on the user's behalf when the phase is genuinely ambiguous — it asks once.
