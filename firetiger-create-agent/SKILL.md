---
name: firetiger-create-agent
description: "Create a Firetiger monitoring agent and configure its triggers. Use when the user wants to create an agent, monitor something automatically, schedule recurring analysis, or set up on-demand automation. Covers the fast path (create_agent_with_goal with a natural-language goal and the agent-planner) and the manual path (schema/create over the agents and triggers collections, including cron and manual triggers)."
user_invocable: true
user_invocable_description: "Create a monitoring agent in Firetiger"
---

# Firetiger Create Agent

You are an expert at designing and creating AI agents in Firetiger that automate observability workflows.
Firetiger agents autonomously analyze telemetry, detect anomalies, investigate issues, and take actions
through connections (Slack, GitHub, Linear, …). They run on schedules or on demand.

There are two ways to create an agent. Prefer the goal-based path unless the user needs precise control.

## Path A (recommended): create from a goal

Use the MCP tool **`create_agent_with_goal`**. The agent-planner configures the agent — prompt, connections,
triggers — from a natural-language goal.

```
create_agent_with_goal with:
  goal: "Monitor Next.js API routes for errors and slow responses; alert on error-rate spikes and p95 latency increases"
  title: "Checkout Health Monitor"   # optional
```

### Handle planner questions
The call returns the planner conversation. If the planner asked something (e.g. "Which database should I
monitor?"):
1. Answer on the user's behalf using what you know from the codebase / context (or ask the user if genuinely
   unknown).
2. Reply with `send_agent_message` using the plan `session` from the tool output.
3. The tool waits for the planner to finish and returns the updated conversation.

### Confirm
Once the agent is active, share its name and what it's configured to monitor.

### Example goals
- "Monitor Next.js API routes for errors and slow responses"
- "Track database query latency and alert if p99 exceeds 500ms"
- "Watch for deployment failures and notify on Slack"
- "Monitor authentication endpoints for unusual patterns"
- "Track error rates across all services and create incidents for spikes"

## Path B: manual configuration

Use the generic CRUD tools when you need explicit control over the agent and its triggers.

**Always run `schema` first** — field names below are illustrative and may drift:
```
schema with collection: "agents"
schema with collection: "triggers"
```

### Agent fields
- **name** — resource name, `agents/{agent-id}`
- **title** — human-readable title
- **description** — what the agent does
- **prompt** — the initial prompt guiding behavior
- **connections** — enabled tool connections
- **state** — e.g. `AGENT_STATE_ON`, `AGENT_STATE_OFF`

```
create with resource: "agents"
  title: "Checkout Health Monitor"
  description: "Daily health analysis of the checkout service"
  prompt: "You are a daily health check agent..."
  state: "AGENT_STATE_ON"
```

### Triggers are separate resources
Triggers invoke agents; they are not embedded in the agent. Fields:
- **name** — `triggers/{trigger-id}`
- **display_name** — required
- **description**
- **agent** — target, `agents/{agent-id}` (required)
- **enabled** — boolean
- **configuration** — one of:

Cron (periodic):
```
configuration:
  cron:
    schedule: "0 9 * * *"          # standard 5-field cron
    timezone: "America/Los_Angeles" # IANA timezone (default UTC)
```
Cron examples: `0 9 * * *` daily at 9am · `*/15 * * * *` every 15 min · `0 0 * * 1` Mondays at midnight.

Manual (on-demand only):
```
configuration:
  manual: {}
```

Create the trigger:
```
create with resource: "triggers"
  display_name: "Daily Checkout Health Check"
  description: "Runs checkout health analysis every morning"
  agent: "agents/{agent-id}"
  enabled: true
  configuration:
    cron:
      schedule: "0 9 * * *"
      timezone: "America/Los_Angeles"
```

## Writing good agent prompts

- **Specific** — define exactly what to do.
- **Scoped** — limit responsibilities; say what the agent should NOT do.
- **Actionable** — concrete steps.

Example:
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

- **Daily health monitor** — cron trigger; query metrics, compare to baseline, report anomalies.
- **On-demand investigator** — manual trigger; deep-dive analysis and root-cause on demand.
- **Periodic report generator** — cron trigger; aggregate data, generate insights for stakeholders.

## Best practices

1. Start simple — one focused agent that does one thing well.
2. Test with a manual trigger before enabling a cron schedule.
3. Set boundaries in the prompt (what NOT to do).
4. Don't run agents more frequently than needed.
5. Review agent sessions and outcomes regularly (`list`/`read_agent_messages`).
6. Iterate on the prompt based on performance.

## Related

- Run and steer an existing agent's session: `firetiger-monitor-deploy`.
- Manual investigations without an agent: `firetiger-investigate`.
