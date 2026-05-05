# rollout decision tree

## Contents
- The four cases
- Worked examples per case
- Edge cases

## The four cases

```
                          Has the change shipped yet?
                                    │
                  ┌─────────────────┴─────────────────┐
                no│                                   │yes
                  ▼                                   ▼
       Has a monitoring plan                 Has a monitoring plan
       already been written?                 already been written?
              │                                       │
        ┌─────┴─────┐                           ┌─────┴─────┐
      no│           │yes                      no│           │yes
        ▼           ▼                           ▼           ▼
   PLAN-ONLY    BOTH-NOW           POST-MERGE-NO-PLAN   MONITOR-ONLY
                (rare)              (common)
```

| Case | Route to | Notes |
|------|----------|-------|
| PLAN-ONLY | `plan-rollout` | The common pre-merge case. Result is a monitoring section in the plan file; no execution yet. |
| MONITOR-ONLY | `monitor-rollout <plan>` | The common post-deploy case. Plan exists, deploy started or about to start. |
| POST-MERGE-NO-PLAN | `plan-rollout --merge-sha <sha>` first, then `monitor-rollout <produced plan>` | **Common path**. User merged without writing a plan, then realised they want monitoring. The umbrella synthesizes a plan from the actual merged diff (anchored on `--merge-sha`), shows it to the user for sanity-check, then chains into the executor. |
| BOTH-NOW | `plan-rollout` first, then `monitor-rollout <produced plan>` | Rare. The user wants the full pre-merge lifecycle in one go and the change is already in flight. |

## Worked examples per case

**PLAN-ONLY**
- *"I'm about to merge a PR that adds a new endpoint, can you draft a monitoring plan?"*
- *"In the plan, include how we'll watch this rollout."*
- *"What SLIs should we track for this change?"*

**MONITOR-ONLY**
- *"I just merged #1234, watch the deploy."* (with the plan at `.rollout/feat-foo-monitoring-plan.md`)
- *"The plan is at docs/plans/feature-x.md, run it."*
- *"Babysit the production rollout for the next hour."*

**POST-MERGE-NO-PLAN**
- *"This PR went out 10 minutes ago and I'm getting nervous, can you watch it?"* (no plan exists)
- *"Just merged a refactor — should I be monitoring something?"*
- *"Production deploy is rolling now, set up monitoring."* (no `.rollout/` plan)

For this case the umbrella runs:

```
1. /plan-rollout --merge-sha <sha-of-recent-merge-commit>
2. Show the user the produced plan path: ".rollout/<branch>-monitoring-plan.md"
3. Wait for user to confirm or edit
4. /monitor-rollout <path>
```

Do **not** skip step 2 (silently chaining straight to monitor-rollout). The user needs to see what's being watched; they retain veto and edit power. A synthesized plan against a fresh diff often picks reasonable defaults but occasionally misses an intended-effect indicator the user knows about — give them the chance to fix it.

**BOTH-NOW**
- *"Plan and monitor this rollout for this PR."*
- *"Set up monitoring for this release end-to-end."*

## Edge cases

- **Change is behind a feature flag at 0%** — treat as not-yet-shipped from a monitoring perspective, even if the code is in the binary. Route to `plan-rollout` and note the rollout-percentage trigger in the plan.
- **Hotfix that's already merged + deploying** — POST-MERGE-NO-PLAN with the schedule trimmed. Skip the +24h and +72h checkpoints unless the hotfix touches infra. The user can override the default schedule when invoking `plan-rollout`.
- **Change is a documentation-only update** — neither skill applies. Tell the user no monitoring is warranted (no production behaviour change).
- **Multi-PR coordinated rollout** — write one plan that lists all PRs in the `Description` and treat the deploys collectively. Multi-issue parallelism is not supported (see `limitations.md`).
- **Multiple recent merges, ambiguous which one to anchor on** — ask: *"I see commits A, B, C in the last hour. Which one's the change you want monitored?"* Don't guess; the planner anchors evidence on the wrong diff if you pick the wrong commit.
