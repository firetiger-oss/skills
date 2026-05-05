# Status report formats

## Contents
- Hard rules
- Visual conventions
- DEPLOY_DETECTED
- CHECK_COMPLETE
- ISSUE_DETECTED
- COMPLETED
- FATAL_ERROR
- WARNING

The executor emits one of these blocks at every significant transition. The blocks are normal markdown the user reads inline; no parse contract is needed because the main session is the one rendering them.

Each block starts with a `## <emoji> **<STATUS-TYPE>**` heading so the user (and the agent reading back the conversation) can find them quickly.

## Hard rules

**Every status block declares the next event.**

- For non-terminal blocks: `**Next event expected:** `<absolute time>` (`bash sleep_until.sh ...` running in background)`.
- For terminal blocks (`COMPLETED`, `ISSUE_DETECTED`, `FATAL_ERROR`): `**Next event:** none — terminal state.`
- For `WARNING` (awaiting user input): `**Next event expected:** awaiting user response (no background sleep scheduled).`

This is the silence-prevention contract. The user should never wonder "is the executor still running?" — every block tells them when to expect the next message.

## Visual conventions

The agent composes the user-facing message; the renderer emits the same shape. Follow these conventions consistently so the user can scan at a glance:

**Heading emoji** (one per status block — traffic-light circles for ongoing state, event glyphs for transitions):

| Block | Emoji | Why |
|-------|-------|-----|
| DEPLOY_DETECTED | 🚀 | Launch event — rollout has started for this env. |
| CHECK_COMPLETE (clean) | 🟢 | All indicators clean; nothing to act on. |
| CHECK_COMPLETE (any INCONCLUSIVE) | 🟡 | At least one indicator couldn't be evaluated; user may want to look. |
| ISSUE_DETECTED | 🔴 | Regression confirmed; rollback recommended. |
| COMPLETED | 🏁 | Monitoring window closed cleanly; finish flag. |
| FATAL_ERROR | 🔴 | Executor stopped; user intervention needed. |
| WARNING | ⚠️ | Mid-run user input needed (e.g. deploy never observed). |

**Other formatting:**

| Element | Style |
|---------|-------|
| Status-type word in heading | `**bold**` |
| Env name in heading | `*italicised*` |
| Env name in tables | `` `code span` `` |
| Field labels (`Env:`, `Deploy time:`, etc.) | `**bold**` |
| Timestamps, SHAs, paths, commands | `` `code spans` `` |
| Verdict words (`confirmed`, `unchanged`, `regressed`, `inconclusive`) | `**bold**` |
| Per-indicator markers (`✓`, `✗`) | `` `code spans` `` |
| Offset markers (`+10m`, `+30m`) when they're a heading subject | `**bold**` |

**Restraint principle:** one emoji per block heading, none inside tables. The heading emoji is the at-a-glance "what kind of event is this and is it good or bad?" signal; verdict cells stay text-only with the existing `✓` / `✗` Unicode marks.

The render script (`scripts/render_status_report.sh`) emits these conventions automatically; when the agent composes a block freely, follow the same conventions for consistency. Adopters and downstream tooling may grep `## <emoji> \*\*<STATUS>` patterns; keep the bold-heading shape stable.

## DEPLOY_DETECTED

Emitted when an env's deploy-detection match condition fires for the first time.

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

Emitted at every checkpoint that doesn't trigger a terminal state. Heading is 🟢 when every indicator's verdict is `confirmed` / `unchanged`; heading is 🟡 when any indicator is `inconclusive`.

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

Emitted when any env's per-indicator verdict goes to `regressed` after the evidence-discipline gate. Triggers `EnterPlanMode`.

```markdown
## 🔴 **ISSUE_DETECTED** — *<env>* @ **+<offset>**

**Env:** `<env-name>`

**Failing indicators:**

| Indicator | Pre | Post | Δ | Threshold |
|-----------|-----|------|---|-----------|
| `error-rate-checkout` | `0.18%` | `1.2%` | **6.7× baseline** | `> 5× sustained 5m` |
| `cache-hit-ratio`     | `78%`   | `22%`  | **−56pp**           | `< 90% of baseline` |

**Evidence (per evidence-discipline gate):**
- **Baseline window:** `<start>` → `<end>` (24h, queried `2026-05-04T15:00Z`, Datadog).
- **Same-time-of-day comparison:** prior-day reading `0.16%`, two-days-ago `0.20%`; today is `1.2%` — not in prior-day range.
- **Analytical reason:** cache miss spike correlates with error spike, indicating the new cache layer is not serving reads as intended.
- **Variance test:** pre-deploy noise was `0.10%`–`0.32%`; the **+6.7×** delta dwarfs that range.

**Recommended action:** roll back via `<rollback hint copied verbatim from the plan>`. Re-run `/monitor-rollout <plan>` after the rollback to confirm metrics return to baseline.

**Other envs:**
- `<env-2>`: also showing regression on error-rate (`1.4%` post-deploy, baseline `0.05%`); deferred until the current fix lands.
- `<env-3>`: unchanged.

**Handoff:** entering plan mode to design the fix.

**Next event:** none — terminal state.
```

After this block, the skill calls `EnterPlanMode` with a seed plan from [`plan-mode-handoff.md`](plan-mode-handoff.md).

## COMPLETED

Emitted when all envs have reached their final checkpoint with no `ISSUE_DETECTED`.

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

The "safe to close this loop" line matters: it tells the user explicitly that the executor is done, so they don't sit waiting for further updates that aren't coming.

## FATAL_ERROR

Emitted when the executor cannot continue.

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

Common FATAL_ERROR triggers:
- Plan file missing required fields (no `Rollback`, no `Indicators`, no `Environments`).
- All envs polled for 30+ minutes with no deploy detected (likely the deploy-detection command is wrong, or the deploy never started).
- Telemetry source is universally unreachable on every retry.

## WARNING

Emitted when the executor needs user input mid-run (e.g. a deploy didn't start within 30 min, or telemetry's authentication state changed).

```markdown
## ⚠️ **WARNING** — *<env>*

<message>

<user-question — e.g. "Should I keep polling, abort this env, or stop entirely?">

**Next event expected:** awaiting user response (no background sleep scheduled).
```

`WARNING` blocks pause the per-env state machine until the user replies. Other envs that are not in WARNING state continue on their own checkpoint clocks.
