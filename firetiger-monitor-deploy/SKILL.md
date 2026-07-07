---
name: firetiger-monitor-deploy
description: >
  Use when monitoring a PR or deployment with Firetiger — watching a deploy, setting
  up the @firetiger comment flow, registering deployments from CI/CD, or reviewing
  what a monitoring agent found. Always use this skill for deploy monitoring — it
  carries the critical gotchas (monitor_pr needs the full PR URL, the @firetiger
  comment requires a connected GitHub integration, deployments must be POSTed with
  Basic auth so checkpoints anchor to real deploy times) that make monitoring fire
  on the right release.
license: Apache-2.0
user_invocable: true
user_invocable_description: "Monitor a PR or deployment and review what Firetiger found"
metadata:
  author: firetiger
  version: "1.0.0"
  homepage: https://firetiger.com
  source: https://github.com/firetiger-oss/skills
---

# Firetiger Monitor Deploy

When a change ships, Firetiger builds a targeted monitoring plan from the diff, verifies each release against
telemetry, and reports issues back on the PR and as Known Issues. There are two ways to start — pick by where
the user is working.

## Quick Start

**From your coding session** — you have the PR URL:
```
monitor_pr with:
  pr_url: "https://github.com/org/repo/pull/123"
  initial_message: "Watch checkout error rate and DB latency; this changes the payment flow"   # optional
```

**From GitHub** — comment on the PR (requires a connected GitHub integration):
```bash
gh pr comment <PR_NUMBER> --body "@firetiger watch for errors and latency spikes in checkout"
```

After either, Firetiger reacts with 👀, posts a monitoring plan as a PR comment, and after merge + deploy runs
automated checks at **10 min, 30 min, 1 h, 2 h, 24 h, and 72 h**.

## A. The `monitor_pr` MCP tool

Use **`monitor_pr`** when the user hands you a PR URL directly. The agent analyzes the PR, creates a monitoring
plan, and watches for problems after it deploys. Populate `initial_message` from the diff (`gh pr diff`) and
anything the user cares about — it steers the monitoring focus.

## B. The `@firetiger` GitHub comment flow (auto-monitoring)

Once the GitHub integration is connected, anyone can enable monitoring by commenting `@firetiger` on a PR — no
coding session required.

1. **Check the GitHub connection:**
   ```
   list with resource: "connections" and filter: connection_type = "GITHUB"
   ```
   If none exists, connect GitHub first (`schema` then `create` on `connections`; OAuth opens a browser).
   `firetiger-setup` walks through connecting integrations.
2. **Identify the PR** — a URL/number the user gave you, the current branch's PR
   (`gh pr view --json number,title,url`), or ask.
3. **Gather context** — `gh pr diff` to see what changed; ask for specific concerns or propose focus areas.
4. **Post the comment:**
   ```bash
   gh pr comment <PR_NUMBER> --body "@firetiger <monitoring context>"
   ```

### Example comments

```
@firetiger
```
```
@firetiger please monitor this deployment — it changes the payment flow, watch for errors or latency spikes in checkout
```
```
@firetiger monitor for:
- Error rate increases in /api/orders
- Latency regression in database queries
- Any 5xx responses from the new endpoint
```

## Registering deployments from CI/CD (deployments API)

For monitors to verify *each* release, Firetiger needs to know when a deploy happens. Call
**`get_deploy_credentials`** → the deployment registration API endpoint + username/password. Wire a CI/CD step
that POSTs a deployment event (commit SHA, environment, version) to that endpoint with HTTP Basic auth.
Firetiger then anchors its checkpoint schedule to the actual deploy time instead of guessing. Inject the
credentials as pipeline secrets — never commit them.

## Interacting with the monitoring agent

Monitoring runs as a Firetiger agent with sessions.

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

**Start a fresh session** with an existing agent for a new line of inquiry:
```
create with resource: "agents/{agent-id}/sessions"
```

Be specific, include time ranges, name services/endpoints, ask follow-ups, and request concrete actions (open
an investigation, notify a channel).

## Common Mistakes

| # | Mistake | Fix |
|---|---------|-----|
| 1 | **Passing a partial PR ref to `monitor_pr`** | `pr_url` must be the full URL: `https://github.com/org/repo/pull/123`. |
| 2 | **`@firetiger` comment with no GitHub connection** | Connect the GitHub integration first, or the comment is ignored. |
| 3 | **Expecting checks immediately** | Checkpoints run at 10m/30m/1h/2h/24h/72h *after* merge + deploy, not on comment. |
| 4 | **Skipping deployment registration** | Without `get_deploy_credentials` events, checkpoints can't anchor to the real deploy — register from CI/CD. |
| 5 | **Bearer auth on the deployments API** | It's HTTP Basic auth (username/password from `get_deploy_credentials`). |
| 6 | **Empty `initial_message`** | Seed it from the diff — a focused hint produces a far better monitoring plan. |
| 7 | **Committing deploy credentials** | Inject them as CI secrets. |

## Related

- Deep-dive an issue the monitor surfaced: `firetiger-investigate`.
- Create a standing monitoring agent from a goal: `firetiger-create-agent`.
- End-to-end onboarding (connect GitHub, instrument, agent): `firetiger-setup`.
