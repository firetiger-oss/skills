---
name: firetiger-monitor-deploy
description: "Monitor a PR or deployment with Firetiger and interact with the monitoring agent. Use when the user wants to watch a deploy, monitor a PR, set up the @firetiger comment flow, register deployments from CI/CD, or check what a monitoring agent found. Covers the monitor_pr MCP tool, the @firetiger GitHub comment flow with auto-monitoring at fixed checkpoints, the deployments registration API (get_deploy_credentials), and agent sessions (send_agent_message / read_agent_messages)."
user_invocable: true
user_invocable_description: "Monitor a PR or deployment and review what Firetiger found"
---

# Firetiger Monitor Deploy

You help the user monitor a deployment with Firetiger and interact with the agent that watches it. When a
change ships, Firetiger builds a targeted monitoring plan from the diff, verifies each release against
telemetry, and reports issues back on the PR and as Known Issues in Firetiger.

There are two ways to start monitoring — pick based on where the user is working.

## A. The `monitor_pr` MCP tool (from your coding session)

Use the Firetiger MCP tool **`monitor_pr`** when the user hands you a PR URL directly.

```
monitor_pr with:
  pr_url: "https://github.com/org/repo/pull/123"
  initial_message: "Watch checkout error rate and DB latency; this changes the payment flow"   # optional
```

The agent analyzes the PR, creates a monitoring plan, and watches for problems after it deploys. `initial_message`
steers the monitoring focus — populate it from the diff (`gh pr diff`) and anything the user cares about.

## B. The `@firetiger` GitHub comment flow

Once the GitHub integration is connected, anyone can enable monitoring by commenting `@firetiger` on a PR —
no coding session required. This is the auto-monitoring path.

### Process
1. **Check the GitHub connection.** Confirm a GitHub connection exists:
   ```
   list with resource: "connections" and filter: connection_type = "GITHUB"
   ```
   If none exists, connect GitHub first (`schema` then `create` on the `connections` collection; OAuth opens
   a browser). The `firetiger-setup` skill walks through connecting integrations.
2. **Identify the PR.**
   - Use a PR number/URL the user gave you, or
   - Find the PR for the current branch: `gh pr view --json number,title,url`, or
   - Ask which PR to monitor.
3. **Gather context.** Read the diff to understand what changed: `gh pr diff`. Ask the user for specific
   concerns, or propose focus areas based on the changes.
4. **Post the comment** with the gh CLI:
   ```bash
   gh pr comment <PR_NUMBER> --body "@firetiger <monitoring context>"
   ```
5. **Confirm.** Firetiger will react with 👀 to acknowledge, post a monitoring plan as a PR comment, and after
   merge + deploy run automated checks at **10 min, 30 min, 1 h, 2 h, 24 h, and 72 h**, reporting regressions
   on the PR and as Known Issues.

### Example comments
Simple (let Firetiger infer focus from the diff):
```
@firetiger
```
With context:
```
@firetiger please monitor this deployment — it changes the payment flow, watch for errors or latency spikes in checkout
```
Specific focus:
```
@firetiger monitor for:
- Error rate increases in /api/orders
- Latency regression in database queries
- Any 5xx responses from the new endpoint
```

## Registering deployments from CI/CD (deployments API)

For monitors to verify *each* release, Firetiger needs to know when a deploy happens. Call the MCP tool
**`get_deploy_credentials`** to get the deployment registration API endpoint plus username and password. Wire a
step into the CI/CD pipeline that POSTs a deployment event (commit SHA, environment, version) to that endpoint
using HTTP Basic auth. Firetiger then anchors its checkpoint schedule to the actual deploy time instead of
guessing. Never commit these credentials — inject them as pipeline secrets.

## Interacting with the monitoring agent

Monitoring runs as a Firetiger agent with sessions. Use these MCP tools to review or steer it.

**Find the agent and its plan:**
```
list with resource: "agents"
get with name: "agents/{agent-id}"
list with resource: "monitoring-plans"
```

**Read what the agent found** (its reasoning and actions for a run):
```
read_agent_messages with session: "agents/{agent-id}/sessions/{session-id}"
```

**Steer or ask the agent a question** (synchronous — waits for the reply):
```
send_agent_message with session: "agents/{agent-id}/sessions/{session-id}"
  message: "Focus on the 503s from the new /api/orders endpoint and compare error rate to the previous version"
```

**Start a fresh session** with an existing agent when you want a new line of inquiry:
```
create with resource: "agents/{agent-id}/sessions"
```

Tips for effective agent interaction: be specific, include time ranges, name services/endpoints, ask
follow-ups to drill in, and request concrete actions (open an investigation, notify a channel).

## Related

- Deep-dive a specific issue the monitor surfaced: `firetiger-investigate`.
- Create a standing monitoring agent from a goal: `firetiger-create-agent`.
- End-to-end onboarding (connect GitHub, instrument, create agent): `firetiger-setup`.
