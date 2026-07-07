# Firetiger Agent Skills

Agent skills that teach coding agents how to use [Firetiger](https://firetiger.com) — the AI-powered
observability platform. Written in the [Agent Skills](https://agentskills.io) format (one folder per skill,
a `SKILL.md` with YAML frontmatter, and `references/` for progressive disclosure).

This repository is the **single canonical source** for "how to use Firetiger" skills; the
[cursor-plugin](https://github.com/firetiger-oss/cursor-plugin) and
[claude-plugin](https://github.com/firetiger-oss/claude-plugin) vendor their skill content from
here via an automated, version-pinned sync — see [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md). Skills
are authored **only** here; never edit them in a plugin repo.

Each skill teaches an agent *when* and *how* to accomplish a Firetiger task, referencing the **Firetiger MCP
server** tools (`https://api.cloud.firetiger.com/mcp/v1`) and the **`@firetiger` GitHub flow** as the
mechanism.

## Install

```sh
npx skills add firetiger-oss/skills
```

Then connect the Firetiger MCP server so the skills can call its tools:

```json
{
  "mcpServers": {
    "firetiger": { "type": "http", "url": "https://api.cloud.firetiger.com/mcp/v1" }
  }
}
```

The first tool call opens a browser to sign in / create a Firetiger account.

## Skills

| Skill | What it does |
|-------|--------------|
| [`firetiger`](firetiger/SKILL.md) | Router — classifies a Firetiger request and delegates to the right skill below. |
| [`firetiger-setup`](firetiger-setup/SKILL.md) | End-to-end onboarding: authenticate, detect the stack, set up telemetry (OTEL SDK or platform drains), connect integrations, register deployments, create a monitoring agent. |
| [`firetiger-instrument`](firetiger-instrument/SKILL.md) | Add OpenTelemetry instrumentation (Node.js, Next.js, Python, Go, Rust) with the exporter pointed at Firetiger. |
| [`firetiger-query`](firetiger-query/SKILL.md) | Query traces, logs, and metrics with DuckDB SQL via the `query` tool — table naming, schemas, and ready-to-run examples. |
| [`firetiger-investigate`](firetiger-investigate/SKILL.md) | Run an investigation to diagnose an incident and track findings against the `investigations` collection. |
| [`firetiger-monitor-deploy`](firetiger-monitor-deploy/SKILL.md) | Monitor a PR/deploy via `monitor_pr`, the `@firetiger` comment flow (auto-monitoring at fixed checkpoints), and the deployments registration API; interact with the monitoring agent. |
| [`firetiger-create-agent`](firetiger-create-agent/SKILL.md) | Create a monitoring agent from a natural-language goal (`create_agent_with_goal`) or configure agents and triggers manually. |

Each skill's `SKILL.md` is a concise entry point; longer detail (per-language instrumentation, query schema
and examples, platform drain recipes) lives in that skill's `references/` directory and is loaded on demand.

## Distribution

Author a skill here → tag a release (`vX.Y.Z`) → CI opens a PR in each plugin repo with the refreshed
skills → merge to update that plugin. The vendored copies are stamped with the source tag and guarded
against drift. The website `.well-known/agent-skills` index and skills.sh read this repo directly and
need no sync. Full flow, local testing, and the one-time token setup: **[docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)**.

## The Firetiger MCP server

Connect it at `https://api.cloud.firetiger.com/mcp/v1` (OAuth 2.0 bearer — the first tool call opens a browser
to sign in). The skills drive Firetiger through its tools:

- **Credentials** — `get_ingest_credentials` (OTLP ingest), `get_deploy_credentials` (deployment registration API).
- **Query** — `query` (DuckDB SQL over Iceberg telemetry tables).
- **Deploy monitoring** — `monitor_pr` (watch a GitHub PR's deployment).
- **Agents** — `create_agent_with_goal`, `send_agent_message`, `read_agent_messages`.
- **Billing / connect** — `get_subscription_status`, `get_checkout_url`, `onboard_github` / `onboard_slack` /
  `onboard_linear` (gated by deployment config).
- **Resources** — `schema` / `list` / `get` / `create` / `update` / `delete` over the collections a client
  agent works with: `agents` and `sessions` (create and run agents), `triggers` and `scheduled-agent-runs`
  (automate them), `investigations` (AI diagnosis sessions), `issues` (Known Issues, `FT-{n}` call signs),
  `monitoring-plans` (deploy monitoring, read/delete), and `connections` (integrations).
- **Navigation** — `resolve_url` (resolve a Firetiger UI URL to an API resource).

## Prerequisites

- A Firetiger account (created on first sign-in via the MCP server).
- The Firetiger MCP server connected at `https://api.cloud.firetiger.com/mcp/v1`.

## Contributing

Issues and pull requests welcome. If a skill mis-triggers (fires when it shouldn't, or fails to fire when it
should), open an issue with the prompt that surprised you. If this is useful, please ⭐ the repo.

## License

See [LICENSE](LICENSE).
