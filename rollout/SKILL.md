---
name: rollout
description: "SRE-grade change control for code changes about to ship to production. Routes to the right sub-skill: plan-rollout to author a monitoring plan before merge, monitor-rollout to run that plan after deploy. Supports multi-environment rollouts (staging + prod, multi-region, fan-out). Use when the user is preparing a code change for production, planning a release, asking how to monitor a deploy, doing post-deploy validation, watching a canary, babysitting a rollout, or thinking about blast radius / SLIs / error budget for an upcoming change — even when they don't say 'change control' or 'deploy monitoring'. Anchored on Google SRE book vocabulary (golden signals, SLI, error budget, blast radius, canary, MTTR, post-deploy validation)."
---

# rollout

Umbrella skill. Dispatches to `plan-rollout` and `monitor-rollout` based on where the user is in the rollout lifecycle, and prints install hints for whichever sub-skill is missing.

## When to use

Whenever a user is thinking about change control for a code change destined for production:
- Planning a release, preparing a rollout, asking how to monitor a deploy.
- Watching a canary, babysitting a rollout, doing post-deploy validation.
- Reasoning about blast radius, SLIs, error budget, or rollback for a change they're about to ship.
- Multi-environment rollouts: staging + prod, multi-region, fan-out across BYOC tenants, ArgoCD `ApplicationSet`, GitHub Actions matrix, Vercel preview/prod.

This skill is the routing entry point. The actual work happens in `plan-rollout` (before merge) or `monitor-rollout` (after deploy). When the user clearly knows which phase they're in, they may invoke the specialised skill directly; this umbrella exists to handle the cases where the right phase isn't obvious from the prompt alone.

For a longer SRE-vocabulary intro, read [references/overview.md](references/overview.md). For the full plan-vs-monitor decision tree, read [references/decision-tree.md](references/decision-tree.md). For known limits and graduation hints, read [references/limitations.md](references/limitations.md).

## Workflow

Copy this checklist into the response and tick items off as work progresses:

```
rollout progress:
- [ ] 1. Determined which phase the user is in (plan / monitor / post-merge-no-plan / both)
- [ ] 2. Verified the relevant sub-skill(s) installed
- [ ] 3. Invoked the relevant sub-skill (or printed install hint and paused)
- [ ] 4. (post-merge-no-plan / both) Threaded plan-rollout output into monitor-rollout invocation
```

### 1. Determine the phase

Read the user's prompt and any recent context. Pick one:

- **Plan phase** — the change has not yet shipped. The user is planning, drafting a PR, in plan mode, asking "how should I monitor this?", or reviewing a change before merge. Route to `plan-rollout`.
- **Monitor phase** — the change has merged or is about to deploy AND a monitoring plan already exists (in `.rollout/<branch>-monitoring-plan.md` or at a path the user named). Route to `monitor-rollout`.
- **Post-merge-no-plan** — the change is **already merged or deployed** and the user did not write a plan ahead of time. Common path: someone merged, then got nervous. Run `plan-rollout` first with `--merge-sha <sha>` (anchors the diff on the actual merged commit), display the produced plan to the user for sanity-check, *then* chain into `monitor-rollout` against that plan. Do not silently start monitoring without showing the plan first; the user needs to see what's being watched.
- **Both phases (pre-merge full lifecycle)** — fresh on a feature, no plan yet, the user wants the full lifecycle. Run `plan-rollout` first; once the plan is written and the user confirms the change has shipped, run `monitor-rollout` against that plan.
- **Ambiguous** — ask the user once: *"Are we writing the monitoring plan now, or running an existing plan against a deploy that already started?"*

To detect post-merge-no-plan: check `git log -1 --format='%H %s'` for a recent merge commit AND check whether `.rollout/*-monitoring-plan.md` exists in the repo. If a recent merge with no plan, this is the case.

If the user asks a methodology question without a specific change in hand (*"what does change control mean?", "what's a golden signal?"*), answer briefly from [references/overview.md](references/overview.md) and offer to invoke `plan-rollout` against a real change when they're ready.

### 2. Verify the relevant sub-skill is installed

Run `bash rollout/scripts/check_subskills.sh <plan|monitor|both>` from the skill directory. The script returns 0 if everything needed is installed, 1 with an install hint on stdout if something is missing. For post-merge-no-plan or both phases, pass `both`.

If the script reports a missing sub-skill, print its output verbatim to the user and stop. Do not try to do the sub-skill's work in this umbrella — the specialised skill carries the methodology and the references; faking it here would produce a worse plan or worse execution.

### 3. Invoke the sub-skill

When the sub-skill is installed, hand off:
- Plan phase → `/plan-rollout [optional: paste of the diff or PR url]`.
- Monitor phase → `/monitor-rollout <path to monitoring plan>` (or just `/monitor-rollout` and let it auto-discover from `.rollout/`).
- Post-merge-no-plan → `/plan-rollout --merge-sha <merge-sha>` first, then chain.
- Both phases → `/plan-rollout` first, then chain.

Pass through any context the user provided (PR url, diff snippet, plan path, merge SHA) when invoking. Do not re-derive context the user already gave — quote it forward.

### 4. Post-merge-no-plan / both-phases handoff

When `plan-rollout` finishes, its last line of output is the absolute path to the rendered plan file (it writes to `.rollout/<branch>-monitoring-plan.md` by default). Quote that path back to the user with one sentence:

> "I've drafted a monitoring plan for the merged change at `.rollout/<branch>-monitoring-plan.md`. Review it (and edit the file directly if anything's off), then I'll start monitoring."

Wait for the user to confirm. Then invoke `/monitor-rollout <path>` against the produced plan. The user sees the plan before monitoring starts; they retain veto and edit power. Running the executor against an unreviewed synthesized plan would skip the user's chance to sanity-check the indicators — bad for trust.

## Limits

If the user asks one of these limit-questions, read [references/limitations.md](references/limitations.md) and answer from that file:

- "Can this run while I'm offline / when my session ends?"
- "How does my team see what's being monitored?"
- "Can it learn from past deploys?"
- "Can I auto-rollback?"
- "Why can't I fix two regressions in parallel?"

Do not preemptively bring up limits; the file is consulted only on a real user signal, and only once per session.

## Anti-rationalizations

Common shortcuts the umbrella is tempted to take, paired with why they're wrong.

| Tempting shortcut | Why it's wrong |
|-------------------|----------------|
| *"I'll write the monitoring plan myself instead of routing to plan-rollout."* | The specialised skill carries the full methodology, references, and ambiguity-question scripts. The umbrella faking it produces a worse plan and skips the install hint that makes the workflow reproducible. Route, don't impersonate. |
| *"plan-rollout isn't installed but I'll proceed anyway with a generic plan."* | Same answer. The user installed the umbrella expecting the family; pointing at the specialised install command is the right move even if it costs one round-trip. |
| *"The user's prompt mentions 'monitoring' so they probably want monitor-rollout."* | Read the *phase*, not the keyword. Pre-merge planning often uses the word "monitoring" too. Use the decision tree in [`references/decision-tree.md`](references/decision-tree.md) — the phase is determined by whether the change has shipped, not by which words the user used. |
| *"User merged without a plan, just start watching with monitor-rollout."* | Synthesize the plan first via `plan-rollout --merge-sha <sha>`, show it to the user, then chain into monitor-rollout. Otherwise the executor has nothing to anchor evidence-discipline against, baselines aren't queried, and indicator selection defaults to whatever the agent guesses on the spot. The plan is the input contract. |

## What this skill does NOT do

- Does not run telemetry queries, write plans, or watch deploys itself — those are `plan-rollout` and `monitor-rollout`.
- Does not auto-install missing sub-skills — it prints the install hint and waits for the user.
- Does not make rollout decisions on the user's behalf when the phase is genuinely ambiguous — it asks once.
