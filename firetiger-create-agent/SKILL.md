---
name: firetiger-create-agent
description: >
  Use when creating a Firetiger monitoring agent or configuring its triggers —
  monitoring something automatically, scheduling recurring analysis, or setting up
  on-demand automation. Always use this skill to create an agent — it carries the
  critical gotchas (prefer create_agent_with_goal and answer the planner's questions,
  run schema before manual create, triggers are separate resources) that produce a
  working, well-scoped agent.
license: Apache-2.0
user_invocable: true
user_invocable_description: "Create a monitoring agent in Firetiger"
metadata:
  author: firetiger
  version: "1.0.0"
  homepage: https://firetiger.com
  source: https://github.com/firetiger-oss/skills
---

# Firetiger Create Agent

Firetiger agents autonomously analyze telemetry, detect anomalies, investigate issues, and take actions through
connections (Slack, GitHub, Linear, …). They run on schedules or on demand. There are two ways to create one —
**prefer the goal-based path** unless the user needs precise control.

## Quick Start

```
create_agent_with_goal with:
  goal: "Monitor Next.js API routes for errors and slow responses; alert on error-rate spikes and p95 latency increases"
  title: "Checkout Health Monitor"   # optional
```

The agent-planner configures the prompt, connections, and triggers from the goal, then returns a planner
conversation. **If the planner asked a question, you must answer it** or the agent won't finish configuring.

## Path A (recommended): create from a goal

1. Call `create_agent_with_goal` with a clear `goal`.
2. **Handle planner questions.** The result includes the planner conversation. If it asked something (e.g.
   "Which database should I monitor?"), answer on the user's behalf from the codebase/context (or ask the user
   if genuinely unknown), replying with `send_agent_message` on the plan `session` from the output. The tool
   waits for the planner to finish and returns the updated conversation.
3. **Confirm** — once the agent is active, share its name and what it's set to monitor.

### Example goals
- "Monitor Next.js API routes for errors and slow responses"
- "Track database query latency and alert if p99 exceeds 500ms"
- "Watch for deployment failures and notify on Slack"
- "Monitor authentication endpoints for unusual patterns"
- "Track error rates across all services and create incidents for spikes"

## Path B: manual configuration

Use the generic CRUD tools when you need explicit control. **Always run `schema` first** — the fields below are
illustrative and may drift.

```
schema with collection: "agents"
schema with collection: "triggers"
```

### Agent fields
`name` (`agents/{agent-id}`) · `title` · `description` · `prompt` (guides behavior) · `connections` (enabled
tools) · `state` (`AGENT_STATE_ON` / `AGENT_STATE_OFF`).

```
create with resource: "agents"
  title: "Checkout Health Monitor"
  description: "Daily health analysis of the checkout service"
  prompt: "You are a daily health check agent..."
  state: "AGENT_STATE_ON"
```

### Triggers are separate resources
A trigger invokes an agent; it is **not** embedded in the agent. Fields: `name` (`triggers/{trigger-id}`),
`display_name` (required), `description`, `agent` (`agents/{agent-id}`, required), `enabled`, and a
`configuration` of one kind:

Cron (periodic):
```
configuration:
  cron:
    schedule: "0 9 * * *"           # standard 5-field cron
    timezone: "America/Los_Angeles"  # IANA timezone (default UTC)
```
Examples: `0 9 * * *` daily 9am · `*/15 * * * *` every 15 min · `0 0 * * 1` Mondays midnight.

Manual (on-demand only):
```
configuration:
  manual: {}
```

Create it:
```
create with resource: "triggers"
  display_name: "Daily Checkout Health Check"
  agent: "agents/{agent-id}"
  enabled: true
  configuration:
    cron: { schedule: "0 9 * * *", timezone: "America/Los_Angeles" }
```

## Writing good agent prompts

Specific, scoped, actionable — and say what the agent should NOT do.

```
You are a daily health check agent for the checkout service.

Your job:
1. Query the last 24 hours of traces for the checkout service.
2. Calculate error rates and p99 latency.
3. Compare against the previous 24-hour period.
4. If error rate increased >10% or p99 increased >20%, open an investigation.
5. Summarize findings in a brief report.

Focus only on the checkout service. Do not investigate other services.
```

## Patterns

| Pattern | Trigger | Actions |
|---------|---------|---------|
| Daily health monitor | Cron | Query metrics, compare to baseline, report anomalies |
| On-demand investigator | Manual | Deep-dive analysis and root-cause when issues arise |
| Periodic report generator | Cron | Aggregate data, generate insights for stakeholders |

## Common Mistakes

| # | Mistake | Fix |
|---|---------|-----|
| 1 | **Ignoring the planner's questions** | `create_agent_with_goal` isn't done until you answer via `send_agent_message` on the plan session. |
| 2 | **Manual `create` without `schema`** | Field names drift — call `schema` for `agents`/`triggers` first. |
| 3 | **Embedding the trigger in the agent** | Triggers are separate resources referencing `agents/{id}`. |
| 4 | **Enabling a cron schedule before testing** | Validate with a manual trigger first, then schedule. |
| 5 | **Unbounded prompt** | State what the agent should NOT do; scope it to specific services. |
| 6 | **Over-frequent cron** | Don't run more often than the signal changes — it wastes runs and adds noise. |

## Related

- Run and steer an existing agent's session: `firetiger-monitor-deploy`.
- Manual investigations without an agent: `firetiger-investigate`.
