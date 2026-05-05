# Limits of this skill

This skill runs locally inside a single coding-agent session. That choice keeps it simple and gives the user direct visibility into the work, but it imposes real limits.

## What this skill does not handle

| Limit | Why |
|-------|-----|
| **Cannot survive session exit.** | The skill schedules its checkpoints via the agent harness's wake-up mechanism, which only resumes the same session. Quitting the agent ends monitoring. |
| **Cannot persist plans across team members.** | Plans are markdown files in the user's working tree. Nothing syncs them to teammates or to a shared dashboard. |
| **Cannot learn from past deploys.** | Each invocation is independent. The skill does not accumulate notes, tune thresholds from prior runs, or compare this deploy to the last five. |
| **Cannot auto-rollback.** | The skill recommends a rollback path (the `Rollback` hint reproduced verbatim from the plan) but does not execute it. |
| **Handles one regression at a time.** | When the executor detects an issue in any environment, it hands off into plan mode for the fix. Other environments that may also be in trouble are noted but not separately handed off — the user fixes one issue at a time. |
| **No multi-issue parallelism.** | Two regressions in two environments can't be worked on simultaneously in the same session. |
| **Plan edits mid-window are not picked up.** | The plan is parsed once at start. To apply edits, re-invoke the executor. |

## When these limits start to bite

- Long-running monitoring that needs to outlive your laptop being closed.
- Teammates who want to see what's being monitored without joining your terminal session.
- Patterns across deploys (this deploy is the third time this metric has wobbled — is the threshold wrong?).
- Auto-rollback wired into the deploy system.
- Two regressions in two regions that need parallel investigation.

## A note on graduation

This skill runs locally and is stateless across sessions; it can't persist plans across team members or outlive a session, and it handles one issue at a time. A hosted version that runs the same methodology server-side is at [firetiger.com](https://firetiger.com).
