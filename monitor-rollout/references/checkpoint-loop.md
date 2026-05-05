# Checkpoint loop (foreground execution + background sleep)

## Contents
- Why foreground
- The sleep-bg pattern (canonical)
- Alternative: /loop /monitor-rollout for harnesses with native wake-up
- Per-environment checkpoint clocks
- What runs at each wakeup
- Edge cases (missed wakeups, clock skew, late deploys)

## Why foreground

The executor stays in the main coding-agent session for the entire monitoring window. This is a deliberate choice over running as a background subagent:

- **Visibility.** The user sees each poll, each checkpoint, each verdict in their own chat. The skill *feels* valuable, not opaque.
- **Plan-mode handoff.** When a regression is detected, the executor calls `EnterPlanMode` directly — the same session pivots to fixing the issue. A background subagent can't do that; it would have to marshal state across processes.
- **Simplicity.** No status-block parse contract between the executor and a coordinator session. The reports are normal markdown the user reads; that's the contract.

Trade-off: the user can't run unrelated work in the same session during monitoring. That's acceptable because the OSS workflow is single-issue-mode (see [`limitations.md`](limitations.md)) — one change, one focus.

## The sleep-bg pattern (canonical)

Between checkpoints, the executor needs to sleep without consuming context tokens. The mechanism: kick off `bash scripts/sleep_until.sh <abs-time> <plan-path> <offset>` via the `Bash` tool with `run_in_background: true`. The script sleeps until the absolute time, then echoes a `[RESUME at <abs-time>] <offset> for plan <path>` line. That echo arrives in the agent's chat as a notification — the agent reads it and resumes the next checkpoint.

Pseudocode:

```
parse_plan(path)
for each env in plan.envs:
    while not deploy_detected(env):
        run_poll_command(env)
        if matched: env.deploy_time = now; break
        sleep(30)
    schedule_next_checkpoint(env)

while any env has more checkpoints:
    next_wakeup = min(env.next_checkpoint for env in plan.envs)

    # Kick off background sleep + emit DEPLOY_DETECTED / CHECK_COMPLETE block
    # with "Next event expected: <next_wakeup>" line.
    Bash(
      command="bash scripts/sleep_until.sh <next_wakeup> <plan_path> <offset>",
      run_in_background=true,
    )
    YIELD  # session sleeps here

    # session resumes when the bg sleep completes and emits its notification
    for each env whose next_checkpoint <= now():
        run_indicators(env)
        apply_evidence_discipline(env)
        verdict = aggregate(env)
        emit_status_block(env, verdict)  # includes Next event expected line
        if verdict == ISSUE_DETECTED:
            seed = render_handoff_seed(env, regressions, plan.rollback_hint)
            EnterPlanMode(seed)
            # session pivots to fix; we exit
            return
        env.advance_to_next_checkpoint()

emit COMPLETED block
```

The `YIELD` is what makes this foreground without burning context: the agent waits for the bg-sleep notification, and the user's chat shows nothing until the wake-up resumes it.

**Why bash-bg over `ScheduleWakeup`:** `ScheduleWakeup` is scoped to `/loop` dynamic mode; outside `/loop` the wake/resume contract is unclear or non-functional. The bash-bg pattern works in every coding-agent harness that supports background commands (Claude Code, Codex, Cursor, etc.), so it's the canonical mechanism.

## Alternative: /loop /monitor-rollout for harnesses with native wake-up

If the user is already running under `/loop` dynamic mode (or an equivalent harness feature), `ScheduleWakeup` is the natural mechanism — the agent harness itself manages the wait + resume. Invocation:

```
/loop /monitor-rollout <plan-path>
```

In that mode, the skill should call `ScheduleWakeup(delaySeconds=N, prompt="<self-prompt>")` instead of starting `sleep_until.sh`. The semantics are equivalent — same checkpoint timing, same per-env multiplexing, same plan-mode handoff on regression.

Detect mode at runtime: if a system-reminder mentions `/loop` is active, prefer `ScheduleWakeup`. Otherwise, default to bash-bg sleep.

## Per-environment checkpoint clocks

Each environment's checkpoint clock starts at *its* deploy_time, not the plan's. If staging deploys at T=0 and prod deploys at T=2h (a slow rollout), staging's checkpoints fire at:

```
staging: T+10m, T+30m, T+1h, T+2h, T+24h, T+72h
prod:    T+2h+10m, T+2h+30m, T+2h+1h, T+2h+2h, T+2h+24h, T+2h+72h
```

This means the next-wakeup computation is `min(env.next_checkpoint for env in plan.envs)`. Multiple envs may have a checkpoint due at the same wake-up; process them all in one resumed slice.

## What runs at each wakeup

For each env whose next checkpoint is due:

1. Run each indicator's source query. Where the source supports `GROUP BY env`, batch across envs in one query and split the result. Otherwise per-env. For `kind: shell` indicators, run the indicator's `command` field and capture stdout/exit code.
2. For each indicator's reading, apply the four-check evidence-discipline gate (see [`evidence-discipline.md`](evidence-discipline.md)).
3. Aggregate per-env verdict.
4. Emit the per-env row in the `CHECK_COMPLETE` block (or transition to `ISSUE_DETECTED` / `COMPLETED`). Include the `Next event expected` line.
5. Advance the env's checkpoint pointer.

If multiple envs have a checkpoint due at the same wake-up, the report includes all of them in one `CHECK_COMPLETE` block (one table row per env).

## Edge cases

### Missed wakeup

If the user's machine was asleep / the harness was paused, the bg-sleep notification may fire late. Compute "is the *current* checkpoint still valid?" — if more than 2× the inter-checkpoint gap has elapsed, skip the missed checkpoint and run the latest-due checkpoint instead. Note the skip in the report.

This matches the closed-source product's catch-up logic in `service/monitoring_plans/scheduler.go`.

### Clock skew

The `deploy_time` was recorded from the deploy system's clock; checkpoint absolute times are computed from the local agent's clock. If they differ by minutes, alignment can drift. Use UTC throughout and accept up to ±60s of drift; treat anything larger as a `WARNING` and ask the user to verify the deploy system's clock.

### Late deploy

If an env's deploy never started (the poll command never matched), don't schedule any checkpoints for that env. After 30 minutes of polling with no match, emit a `WARNING` for that env and ask the user whether to keep polling or abort. Other envs continue regardless.

### Plan was edited during monitoring

The executor reads the plan once, at start. If the user edits the plan file mid-monitoring (adding an indicator, tightening a threshold), the executor doesn't pick up the change — re-running the skill picks up the fresh plan from the next checkpoint forward. This is documented in `limitations.md`.

### Background sleep killed externally

If the user's terminal closes mid-sleep, or the harness is restarted, the bg-sleep notification never arrives. The session won't auto-resume. The user re-invokes `/monitor-rollout <plan-path>` and the skill picks up where it left off (re-polling envs that haven't reached final checkpoint, computing next-wakeup based on their `deploy_time`).
