---
name: firetiger
description: "Router for Firetiger observability tasks. Use when the user mentions Firetiger, or wants to set up observability, instrument an app with OpenTelemetry, query traces/logs/metrics, investigate an incident, monitor a PR or deployment, or create a monitoring agent. Delegates to the right specialized firetiger-* skill."
user_invocable: true
user_invocable_description: "Firetiger observability toolkit — setup, instrumentation, queries, investigations, deploy monitoring, and agents"
---

# Firetiger

[Firetiger](https://firetiger.com) is an AI-powered observability platform. Telemetry (traces, logs, metrics)
lands in Apache Iceberg tables you query with SQL, and autonomous agents monitor your services, investigate
issues, and watch deployments.

You interact with Firetiger two ways:
- **The Firetiger MCP server** (`https://api.cloud.firetiger.com/mcp/v1`) — tools like `get_ingest_credentials`,
  `query`, `monitor_pr`, `create_agent_with_goal`, and CRUD (`schema`/`list`/`get`/`create`/`update`/`delete`)
  over collections (`agents`, `investigations`, `issues`, `connections`, `monitoring-plans`, `triggers`, …).
- **The `@firetiger` GitHub flow** — comment `@firetiger` on a pull request to have Firetiger monitor the
  deployment that PR produces.

This skill is a router. Identify what the user wants and invoke the matching specialized skill.

## Routing

| The user wants to… | Skill |
|---|---|
| Onboard a project end-to-end (detect stack, instrument, connect integrations, create a monitoring agent) | **`firetiger-setup`** |
| Add OpenTelemetry instrumentation to an app (Node/Next.js/Python/Go/Rust) | **`firetiger-instrument`** |
| Query traces, logs, or metrics with SQL; find errors, slow requests, latency | **`firetiger-query`** |
| Investigate an incident or diagnose an issue and track findings | **`firetiger-investigate`** |
| Monitor a PR/deployment (`@firetiger` comment, `monitor_pr`, deployments API) | **`firetiger-monitor-deploy`** |
| Create a monitoring agent from a goal, or configure agents/triggers | **`firetiger-create-agent`** |

**Trigger phrases**
- setup: "set up Firetiger", "onboard this project", "connect my app to Firetiger"
- instrument: "instrument my app", "add OpenTelemetry", "send traces to Firetiger"
- query: "find traces", "search logs", "show me errors", "query telemetry", "analyze latency"
- investigate: "investigate", "diagnose", "what's wrong with", "troubleshoot this incident"
- monitor-deploy: "monitor this PR", "watch this deploy", "@firetiger", "register deployments"
- create-agent: "create an agent", "monitor X automatically", "schedule an agent"

## Execution

1. Classify the request into one of the categories above.
2. Invoke the corresponding skill with the Skill tool (e.g. `firetiger-query`).
3. If a request spans categories (e.g. "set up Firetiger and then monitor my next PR"), handle them
   sequentially — usually `firetiger-setup` first, then the follow-up skill.
4. If the Firetiger MCP tools are not available, the target skill will guide the user through connecting the
   MCP server first.
