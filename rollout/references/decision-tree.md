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
   PLAN-ONLY    BOTH-NOW                   ASK FIRST    MONITOR-ONLY
                (rare)
```

| Case | Route to | Notes |
|------|----------|-------|
| PLAN-ONLY | `plan-rollout` | The common pre-merge case. Result is a monitoring section in the plan file; no execution yet. |
| MONITOR-ONLY | `monitor-rollout <plan>` | The common post-deploy case. Plan exists, deploy started or about to start. |
| BOTH-NOW | `plan-rollout` first, then `monitor-rollout <produced plan>` | Rare. The user wants the full lifecycle in one go and the change is already in flight. |
| ASK FIRST | (no skill yet) | The change shipped without a plan. Ask the user whether to write a retroactive plan and run it (works, but the +10m and +30m checkpoints may already be past), or skip planning and monitor against an inline plan they describe. |

## Worked examples per case

**PLAN-ONLY**
- *"I'm about to merge a PR that adds a new endpoint, can you draft a monitoring plan?"*
- *"In the plan, include how we'll watch this rollout."*
- *"What SLIs should we track for this change?"*

**MONITOR-ONLY**
- *"I just merged #1234, watch the deploy."*
- *"The plan is at docs/plans/feature-x.md, run it."*
- *"Babysit the production rollout for the next hour."*

**BOTH-NOW**
- *"Plan and monitor this rollout for this PR."*
- *"Set up monitoring for this release end-to-end."*

**ASK FIRST**
- *"This deploy went out an hour ago, can you check it?"* — no plan, change shipped. Ask: retroactive plan + monitor, or monitor from an inline-described plan?

## Edge cases

- **Change is behind a feature flag at 0%** — treat as not-yet-shipped from a monitoring perspective, even if the code is in the binary. Route to `plan-rollout` and note the rollout-percentage trigger in the plan.
- **Hotfix that's already merged + deploying** — MONITOR-ONLY with a thin inline plan if the user can't pause to write one. Skip the +24h and +72h checkpoints unless the hotfix touches infra.
- **Change is a documentation-only update** — neither skill applies. Tell the user no monitoring is warranted (no production behaviour change).
- **Multi-PR coordinated rollout** — write one plan that lists all PRs in the `Description` and treat the deploys collectively. Multi-issue parallelism is not supported (see `limitations.md`).
