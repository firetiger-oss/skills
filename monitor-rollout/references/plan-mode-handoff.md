# Plan-mode handoff seed

When the executor calls `EnterPlanMode` after `ISSUE_DETECTED`, it passes a seed plan that the agent uses as the starting point for the fix. The seed has a strict shape so the agent doesn't have to re-derive context from the conversation log.

## Seed structure

```markdown
# Fix the regression detected by monitor-rollout

## What's happening

`<env-name>` regressed at the +<offset> checkpoint after the deploy of <commit>.

### Failing indicators

| Indicator | Pre | Post | Δ | Threshold |
|-----------|-----|------|---|-----------|
| <name> | <pre> | <post> | <delta> | <threshold> |
| ... | ... | ... | ... | ... |

### Evidence summary

- Baseline window: <start> → <end> (queried <ts>, source: <tool>).
- Same-time-of-day comparison: prior-day readings <list>; today's reading <value> falls outside that range.
- Analytical reason: <one-line reason from the executor>.
- Variance test: <pre-deploy noise range>; the post-deploy delta is <within | outside> that range.

## Other envs

- `<env-2>`: <unchanged | also regressed but deferred until current fix lands>.
- `<env-3>`: ...

## Rollback (if needed before fixing forward)

<rollback hint copied verbatim from the plan>

## Suggested next steps

1. **Investigate.** Read the diff again with the failing indicators in mind:
   - <one-line hint based on the indicator pattern; e.g. "cache-hit ratio dropped sharply, suggesting the cache key derivation or read path changed">
   - <second hint if applicable>
2. **Decide between fix-forward and rollback.**
   - Fix-forward if the cause is small and the fix is fast.
   - Rollback if the cause is unclear or the fix would be larger than the rollback's impact.
3. **After shipping the fix:**
   - Re-run `/monitor-rollout <path-to-this-plan>` to resume monitoring.
   - The deferred-env regression will be re-evaluated at the next checkpoint.

## Open questions

- Was `<env-2>` regression caused by the same root cause, or are these two independent issues? (We'll know after fix + re-monitor.)
```

## Why this shape

- The agent enters plan mode with **enough context to start designing the fix** — it doesn't need to re-read the executor's conversation history to know which indicators failed.
- The **rollback hint copied verbatim** means the on-call user has the call-the-shot in front of them, even if the agent's reasoning goes off the rails.
- The **other envs section** preserves continuity: the user knows what's deferred and why.
- The **suggested next steps** give the agent a starting point but don't prescribe — fixes are design work and the agent should bring its own thinking.

## When the seed is incomplete

If the executor doesn't have all the data (e.g. evidence-discipline failed for some checks but the threshold was very large so the verdict was still `regressed`), the seed should be honest about it:

> "Evidence summary: baseline window ok; same-time-of-day comparison was inconclusive (only 1 prior day of data); analytical reason: error rate spike clearly correlates with deploy_time. Verdict was based on threshold magnitude alone."

Honest seeds produce better fixes than confident ones.
