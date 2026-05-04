# Failure modes

What can go wrong, and what the executor does about it.

## Plan parse failure

**Trigger:** the file passed in the argument doesn't exist, isn't readable, or is missing required sections (`### Indicators`, `### Environments`, `### Checkpoints`, `Rollback:` line).

**Action:** emit `FATAL_ERROR` with a one-line cause naming the missing field. Do not try to guess defaults — the plan is the input contract.

**User remediation:** fix the plan file (or re-run `/plan-change-control`) and re-invoke.

## Telemetry MCP / CLI unreachable

**Trigger:** the indicator's source query fails (HTTP 5xx, timeout, auth error, MCP server returns error).

**Action:** retry once after 10 seconds. If second call also fails:
- Mark this indicator's verdict for this env at this checkpoint as `INCONCLUSIVE`.
- Include the failing query verbatim in the `CHECK_COMPLETE` block's Notes column for that env.
- Continue with the rest of the indicators and the rest of the envs — one failure doesn't poison the whole checkpoint.

**Do not silently mark the indicator as `unchanged`.** That would let an actual regression hide behind a tooling outage.

## Universal telemetry outage

**Trigger:** every indicator on every env returns errors. Two consecutive checkpoints in this state.

**Action:** emit `FATAL_ERROR`; the monitoring window can't yield useful information. Better to fail loudly than to keep emitting empty `CHECK_COMPLETE` blocks.

**User remediation:** fix the telemetry connection (re-auth, re-install MCP server, fix network) and re-invoke.

## Deploy never observed (per env)

**Trigger:** an env's poll command never matches within the first 30 minutes of polling.

**Action:** emit a `WARNING` block (it's not a failure of any indicator; the deploy itself never happened). Ask the user inline:

> "Env `<name>` has not shown a successful deploy after 30 minutes of polling. Should I keep polling, abort this env (continue monitoring others), or stop entirely (the deploy may be misconfigured)?"

Other envs continue regardless. If the user says "abort this env," remove it from the plan's active env set and continue.

**Common causes:**
- The poll command's match condition is wrong (filter on the wrong workflow, wrong branch, wrong sha format).
- The deploy is gated on an approval that hasn't been granted.
- The deploy failed at the CI level before reaching the rollout step.

## Clock skew

**Trigger:** the env's deploy_time and the local agent's clock differ by >60 seconds.

**Action:** emit a `WARNING` and continue. Use the local clock for `ScheduleWakeup` (the only one we control) but record the deploy system's time in the `DEPLOY_DETECTED` block for the user's reference.

## Missed wake-up (machine asleep / harness paused)

**Trigger:** the wake-up fires more than 2× the inter-checkpoint gap late.

**Action:** skip the missed checkpoint and run the latest-due checkpoint instead. Note the skip in the report:

> "Checkpoint @ +30m was missed (session was paused 28 minutes); proceeding directly to +1h."

## Indicator unsupported on source

**Trigger:** the plan references a metric or attribute that doesn't exist on the configured source (typo, deleted metric, wrong tag).

**Action:** the source returns a "not found" error. Treat as `INCONCLUSIVE` per "telemetry MCP / CLI unreachable" above, and note specifically *"metric `<name>` returned not-found on `<source>`"* in the Notes column.

**Do not retry** for not-found — it's not a transient failure.

## Rate limiting

**Trigger:** the source enforces query-per-minute or query-per-hour limits and the executor exceeds them at peak (multi-env multiplexing should keep this rare, but very high-cardinality plans can hit it).

**Action:** the failing query is `INCONCLUSIVE` for that checkpoint. The next checkpoint will retry — that's a fresh budget window in most rate-limit schemes. If two consecutive checkpoints rate-limit, treat as a universal outage.

**User remediation:** consolidate indicators or upgrade the source plan.

## Plan was edited mid-window

**Trigger:** the user edits the plan file after the executor has started.

**Action:** the executor doesn't pick up the edit (the plan is parsed once at start). The window continues with the originally-loaded plan. If the user wants the edit to take effect, they re-invoke `/execute-change-control` against the updated plan; the new run starts polling again from scratch.

This is documented in `limitations.md` so the user isn't surprised.
