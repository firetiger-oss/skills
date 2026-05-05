# Status report formats

## Contents
- DEPLOY_DETECTED
- CHECK_COMPLETE
- ISSUE_DETECTED
- COMPLETED
- FATAL_ERROR
- WARNING

The executor emits one of these blocks at every significant transition. The blocks are normal markdown the user reads inline; no parse contract is needed because the main session is the one rendering them.

Each block starts with a `## [STATUS: <name>]` heading so the user (and the agent reading back the conversation) can find them quickly.

## DEPLOY_DETECTED

Emitted when an env's deploy-detection match condition fires for the first time.

```markdown
## [STATUS: DEPLOY_DETECTED — <env>]

- **Env:** <env-name>
- **Deploy time:** <iso8601 utc>
- **Source:** <gh-actions | buildkite | argocd | vercel | http-poll> run <id-or-url>
- **Commit:** <sha>
- **Next checkpoint:** +<offset> at <absolute time>

Other envs:
- <env-2>: still polling for deploy
- <env-3>: deploy detected at <ts>, next checkpoint at <abs>
```

## CHECK_COMPLETE

Emitted at every checkpoint that doesn't trigger a terminal state.

```markdown
## [STATUS: CHECK_COMPLETE @ +<offset>]

| Env | Intended? | Indicators verdict | Notes |
|-----|-----------|--------------------|-------|
| staging | confirmed | error-rate ✓ unchanged, p99-latency ✓ unchanged, cache-hit ↑ confirmed | Cache hit ratio rose from 78% baseline to 86% — intent met. |
| prod    | not yet visible | error-rate ✓ unchanged, p99-latency ✓ unchanged, cache-hit unchanged | Hit ratio steady — flag rollout still 0% in prod. |

**Next checkpoint:** +<next-offset> at <abs time>  *(or "none — final checkpoint reached" if this was the last)*
```

When an indicator goes to `INCONCLUSIVE`, list the reason in the Notes column:

> "p99-latency: query failed twice (Datadog 5xx); marked inconclusive."

## ISSUE_DETECTED

Emitted when any env's per-indicator verdict goes to `regressed` after the evidence-discipline gate. Triggers `EnterPlanMode`.

```markdown
## [STATUS: ISSUE_DETECTED — <env> @ +<offset>]

**Env:** <env-name>

**Failing indicators:**

| Indicator | Pre | Post | Δ | Threshold |
|-----------|-----|------|---|-----------|
| error-rate-checkout | 0.18% | 1.2% | 6.7× baseline | > 5× sustained 5m |
| cache-hit-ratio | 78% | 22% | -56pp | < 90% of baseline |

**Evidence (per evidence-discipline gate):**
- Baseline window: <start> → <end>  (24h, queried 2026-05-04T15:00Z, Datadog).
- Same-time-of-day comparison: prior-day reading 0.16%, two-days-ago 0.20%; today is 1.2% — not in prior-day range.
- Analytical reason: cache miss spike correlates with error spike, indicating the new cache layer is not serving reads as intended.
- Variance test: pre-deploy noise was 0.10%–0.32%; the +6.7× delta dwarfs that range.

**Recommended action:** roll back via `<rollback hint copied verbatim from the plan>`. Re-run `/monitor-rollout <plan>` after the rollback to confirm metrics return to baseline.

**Other envs:**
- <env-2>: also showing regression on error-rate (1.4% post-deploy, baseline 0.05%); deferred until the current fix lands.
- <env-3>: unchanged.

**Handoff:** entering plan mode to design the fix.
```

After this block, the skill calls `EnterPlanMode` with a seed plan from [`plan-mode-handoff.md`](plan-mode-handoff.md).

## COMPLETED

Emitted when all envs have reached their final checkpoint with no `ISSUE_DETECTED`.

```markdown
## [STATUS: COMPLETED]

**Window:** <start> → <end>  (<tier> tier, <N> checkpoints)
**Envs:** <list>

**Intended effects confirmed:**
- staging — cache-hit-ratio rose from 78% → 87% (target: rise; confirmed at +30m)
- prod — cache-hit-ratio rose from 84% → 91% (confirmed at +1h)

**Inconclusive notes:**
- staging p99-latency at +24h was inconclusive (Datadog query rate-limited; manual check recommended).

**Monitoring window closed; no further checkpoints scheduled. Safe to close this loop.**
```

The "safe to close this loop" line matters: it tells the user explicitly that the executor is done, so they don't sit waiting for further updates that aren't coming.

## FATAL_ERROR

Emitted when the executor cannot continue.

```markdown
## [STATUS: FATAL_ERROR]

**Cause:** <one-line reason>

**Detail:**
- Plan parse: <ok | failed because: ...>
- Polling: <env-1: ok, env-2: 30 min no deploy>
- Telemetry: <Datadog reachable | unreachable; tried 3 times>

The executor is stopping. Resolve the underlying issue and re-invoke `/monitor-rollout <plan>`.
```

Common FATAL_ERROR triggers:
- Plan file missing required fields (no `Rollback`, no `Indicators`, no `Environments`).
- All envs polled for 30+ minutes with no deploy detected (likely the deploy-detection command is wrong, or the deploy never started).
- Telemetry source is universally unreachable on every retry.
