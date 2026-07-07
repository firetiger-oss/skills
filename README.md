# Firetiger Agent Skills

Agent skills that teach coding agents how to use [Firetiger](https://firetiger.com) — the AI-powered
observability platform. This repository is the **single canonical source** for "how to use Firetiger" skills;
the [cursor-plugin](https://github.com/firetiger-oss/cursor-plugin) and
[claude-plugin](https://github.com/firetiger-oss/claude-plugin) sync their skill content from here.

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

## Skills

| Skill | What it does |
|-------|--------------|
| [`firetiger`](firetiger/SKILL.md) | Router — classifies a Firetiger request and delegates to the right skill below. |
| [`firetiger-setup`](firetiger-setup/SKILL.md) | End-to-end onboarding: authenticate, detect the stack, set up telemetry, connect integrations, register deployments, create a monitoring agent. |
| [`firetiger-instrument`](firetiger-instrument/SKILL.md) | Add OpenTelemetry instrumentation (Node.js, Next.js, Python, Go, Rust) with the exporter pointed at Firetiger. |
| [`firetiger-query`](firetiger-query/SKILL.md) | Query traces, logs, and metrics with DuckDB SQL via the `query` tool — table naming, schemas, and ready-to-run examples. |
| [`firetiger-investigate`](firetiger-investigate/SKILL.md) | Run an investigation to diagnose an incident and track findings against the `investigations` collection. |
| [`firetiger-monitor-deploy`](firetiger-monitor-deploy/SKILL.md) | Monitor a PR/deploy via `monitor_pr`, the `@firetiger` comment flow (auto-monitoring at fixed checkpoints), and the deployments registration API; interact with the monitoring agent. |
| [`firetiger-create-agent`](firetiger-create-agent/SKILL.md) | Create a monitoring agent from a natural-language goal (`create_agent_with_goal`) or configure agents and triggers manually. |

## The Firetiger MCP server

The skills drive Firetiger through its MCP tools:

- **Credentials** — `get_ingest_credentials` (OTLP ingest), `get_deploy_credentials` (deployment registration API).
- **Query** — `query` (DuckDB SQL over Iceberg telemetry tables).
- **Deploy monitoring** — `monitor_pr` (watch a GitHub PR's deployment).
- **Agents** — `create_agent_with_goal`, `send_agent_message`, `read_agent_messages`.
- **Resources** — `schema` / `list` / `get` / `create` / `update` / `delete` over collections such as
  `agents`, `investigations`, `issues`, `connections`, `monitoring-plans`, `triggers`, and `runbooks`.
- **Navigation** — `resolve_url` (resolve a Firetiger UI URL to an API resource).

## Contributing

Issues and pull requests welcome. If a skill mis-triggers (fires when it shouldn't, or fails to fire when it
should), open an issue with the prompt that surprised you. If this is useful, please ⭐ the repo.

## License

See [LICENSE](LICENSE).
