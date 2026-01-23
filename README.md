# Firetiger Skills for AI Coding Agents

Production-ready skills for Claude Code, Codex, Cursor, and other AI coding agents.

## Installation

```bash
npx add-skill firetiger-oss/skills
```

Then select the skill(s) you want to install.

### Install a specific skill

```bash
npx add-skill firetiger-oss/skills/install-firetiger
```

## Available Skills

### install-firetiger

Add OpenTelemetry instrumentation to your application for Firetiger observability.

**Supported languages:** Node.js/TypeScript, Python, Go, Rust

**Usage:**
```
/install-firetiger
```

Or just ask naturally:
- "Add observability to my app"
- "Set up tracing for Firetiger"
- "Instrument my service with OpenTelemetry"

**Prerequisites:**
- Firetiger deployment with MCP server configured
- Run `set_firetiger_deployment <cloud> <deployment>` to authenticate

## Manual Installation

If `add-skill` isn't available, copy the skill directory manually:

```bash
# Clone the repo
git clone https://github.com/firetiger-oss/skills.git

# Copy to your project
cp -r skills/install-firetiger .claude/commands/
```

## License

MIT
