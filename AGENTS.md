# AI Agent Instructions

This repository contains skills for AI coding agents (Claude Code, Codex, Cursor, etc.).

## Repository Structure

```
<skill-name>/
├── SKILL.md          # Main skill definition with YAML frontmatter
├── assets/           # Language-specific templates and code
└── references/       # Supplementary documentation
```

## For AI Agents

When a user installs a skill from this repo:

1. The skill directory is copied to the user's `.claude/commands/` (or equivalent)
2. The skill becomes available as a slash command (e.g., `/install-firetiger`)
3. SKILL.md is loaded when the command is invoked

### Skill Conventions

- **SKILL.md**: Must have YAML frontmatter with `name` and `description`
- **assets/**: Templates and code snippets to be copied/adapted for user's project
- **references/**: Loaded on-demand for troubleshooting, advanced usage, etc.

### Progressive Disclosure

Skills use progressive disclosure to minimize context usage:

1. Only SKILL.md is loaded initially (~100 lines max)
2. Assets are loaded based on detected project type
3. References are loaded only when needed (errors, follow-up questions)

## Available Skills

| Skill | Description |
|-------|-------------|
| `install-firetiger` | Add OpenTelemetry instrumentation for Firetiger observability |

## Contributing

To add a new skill:

1. Create `<skill-name>/` directory
2. Add `SKILL.md` with valid frontmatter
3. Organize templates in `assets/` by language/framework
4. Add reference docs in `references/` for edge cases
5. Run `zip -r <skill-name>.zip <skill-name>/` to create the package
