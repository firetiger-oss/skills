# Status report templates (verbatim shapes)

## Contents
- Visual conventions
- DEPLOY_DETECTED
- CHECK_COMPLETE
- ISSUE_DETECTED
- COMPLETED
- FATAL_ERROR
- WARNING

These are the literal markdown shapes the executor emits. Keep them stable — adopters and downstream tooling may grep for the `## <emoji> **<STATUS>**` headings.

**Hard rule:** every block ends with a `**Next event expected:**` line so the user always knows when to expect the next message. For terminal blocks, the line reads `**Next event:** none — terminal state.` Silence is a bug.

## Visual conventions

The agent composes the user-facing message; the renderer emits the same shape. Follow these conventions consistently so the user can scan at a glance:

**Heading emoji** (one per status block — traffic-light for ongoing state, event glyphs for transitions):

| Block | Emoji | Why |
|-------|-------|-----|
| DEPLOY_DETECTED | 🚀 | Launch event — rollout has started for this env. |
| CHECK_COMPLETE (clean) | 🟢 | All indicators clean; nothing to act on. |
| CHECK_COMPLETE (any INCONCLUSIVE) | 🟡 | At least one indicator couldn't be evaluated; user may want to look. |
| ISSUE_DETECTED | 🔴 | Regression confirmed; rollback recommended. |
| COMPLETED | 🏁 | Monitoring window closed cleanly; finish flag. |
| FATAL_ERROR | 🔴 | Executor stopped; user intervention needed. |
| WARNING | ⚠️ | Mid-run user input needed (e.g. deploy never observed). |

**Other formatting** (no additional emoji — keep it restrained):

- Status type word in heading: **bold**
- Env name in heading: *italicised*
- Env name in tables: `code span`
- Field labels (`Env:`, `Deploy time:`, etc.): **bold**
- Timestamps, SHAs, paths, commands: `code spans`
- Verdict words (`confirmed`, `unchanged`, `regressed`, `inconclusive`): **bold**
- Per-indicator markers (`✓`, `✗`): `code spans`
- Offset markers (`+10m`, `+30m`) when they're a heading subject: **bold**

## DEPLOY_DETECTED

```markdown
## 🚀 **DEPLOY_DETECTED** — *<env>*

- **Env:** `<env-name>`
- **Deploy time:** `<iso8601 utc>`
- **Source:** <gh-actions | buildkite | argocd | vercel | http-poll> run `<id-or-url>`
- **Commit:** `<sha>`
- **Next checkpoint:** **+<offset>** at `<absolute time>`

Other envs:
- `<env-2>`: still polling for deploy
- `<env-3>`: deploy detected at `<ts>`, next checkpoint at `<abs>`

**Next event expected:** `<absolute time>` (`bash sleep_until.sh <abs> <plan> +<offset>` running in background)
```

## CHECK_COMPLETE

Heading is 🟢 when every indicator's verdict is `confirmed` / `unchanged`. Heading is 🟡 when any indicator is `inconclusive` (telemetry tool failed, baseline missing, evidence-discipline check rejected the reading).

```markdown
## 🟢 **CHECK_COMPLETE** @ **+<offset>**

| Env | Intended? | Indicators verdict | Notes |
|-----|-----------|--------------------|-------|
| `staging` | **confirmed** | error-rate `✓` unchanged, p99-latency `✓` unchanged, cache-hit **↑ confirmed** | Cache hit ratio rose from 78% baseline to 86% — intent met. |
| `prod`    | not yet visible | error-rate `✓` unchanged, p99-latency `✓` unchanged, cache-hit unchanged | Hit ratio steady — flag rollout still 0% in prod. |

**Next checkpoint:** **+<next-offset>** at `<abs time>`

**Next event expected:** `<absolute time>` (`bash sleep_until.sh <abs> <plan> +<next-offset>` running in background)
```

When an indicator goes to `INCONCLUSIVE`, switch the heading emoji to 🟡 and list the reason in the Notes column:

> "p99-latency: query failed twice (Datadog 5xx); marked **inconclusive**."

## ISSUE_DETECTED

```markdown
## 🔴 **ISSUE_DETECTED** — *<env>* @ **+<offset>**

**Env:** `<env-name>`

**Failing indicators:**

| Indicator | Pre | Post | Δ | Threshold |
|-----------|-----|------|---|-----------|
| `error-rate-checkout` | `0.18%` | `1.2%` | **6.7× baseline** | `> 5× sustained 5m` |
| `cache-hit-ratio`     | `78%`   | `22%`  | **−56pp**           | `< 90% of baseline` |

**Evidence (per evidence-discipline gate):**
- **Baseline window:** `<start>` → `<end>`
- **Same-time-of-day comparison:** prior-day `0.16%`, two-days-ago `0.20%`; today `1.2%` — not in prior-day range.
- **Analytical reason:** cache miss spike correlates with error spike, indicating the new cache layer is not serving reads as intended.
- **Variance test:** pre-deploy noise was `0.10%`–`0.32%`; the **+6.7×** delta dwarfs that range.

**Recommended action:** roll back via `<rollback hint copied verbatim from the plan>`. Re-run `/monitor-rollout <plan>` after the rollback to confirm metrics return to baseline.

**Other envs:**
- `<env-2>`: also showing regression on error-rate (`1.4%` post-deploy, baseline `0.05%`); deferred until current fix lands.
- `<env-3>`: unchanged.

**Handoff:** entering plan mode to design the fix.

**Next event:** none — terminal state.
```

## COMPLETED

```markdown
## 🏁 **COMPLETED**

- **Window:** `<start>` → `<end>` (**<tier>** tier, **<N>** checkpoints)
- **Envs:** `<list>`

**Intended effects confirmed:**
- `staging` — `cache-hit-ratio` rose from `78%` → `87%` (target: rise; **confirmed** at **+30m**)
- `prod` — `cache-hit-ratio` rose from `84%` → `91%` (**confirmed** at **+1h**)

**Inconclusive notes:**
- `staging` `p99-latency` at **+24h** was **inconclusive** (Datadog query rate-limited; manual check recommended).

**Monitoring window closed; no further checkpoints scheduled. Safe to close this loop.**

**Next event:** none — terminal state.
```

## FATAL_ERROR

```markdown
## 🔴 **FATAL_ERROR**

**Cause:** <one-line reason>

**Detail:**
- **Plan parse:** <ok | failed because: ...>
- **Polling:** `<env-1>` ok, `<env-2>` 30 min no deploy
- **Telemetry:** Datadog reachable | unreachable; tried 3 times

The executor is stopping. Resolve the underlying issue and re-invoke `/monitor-rollout <plan>`.

**Next event:** none — terminal state.
```

## WARNING

```markdown
## ⚠️ **WARNING** — *<env>*

<message>

<user-question — e.g. "Should I keep polling, abort this env, or stop entirely?">

**Next event expected:** awaiting user response (no background sleep scheduled).
```
