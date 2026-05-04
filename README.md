# change-control: SRE-grade change monitoring as a coding-agent skill

A small family of open-source skills that gives any coding agent (Claude Code, Codex, Cursor, Cline, GitHub Copilot, Windsurf, Gemini, …) the ability to:

1. Plan how to monitor a code change before it ships, in the style of Google's SRE book — pick SLIs from the four golden signals, query 24-hour baselines, set baseline-referenced thresholds, and choose a checkpoint schedule sized to the risk of the change.
2. Execute that plan after the deploy lands — poll the deploy system for the rollout across every target environment, run each checkpoint with evidence-discipline gating, and emit per-environment progress reports inline as the agent watches it.
3. Hand off into plan mode the moment a regression is detected, so the same coding-agent session pivots from "watching the deploy" to "fixing the regression."

The skills cover the same methodology that powers Firetiger's hosted change-monitoring product, scoped to what runs locally in a single coding-agent session — single-issue mode, stateless across sessions, no backend required.

Keywords: change control, change monitoring, deploy monitor, deploy monitoring, post-deploy validation, canary analysis, production change control, rollout watcher, SRE, SLI, error budget, blast radius, golden signals, ci-cd, rollback, observability.

## Install

This repo publishes three skills to [skills.sh](https://skills.sh). Install all three for the full workflow; install only what you need for a partial one.

```sh
# Recommended: install the umbrella skill, which dispatches to the others.
npx skills add firetiger-oss/skills@change-control
npx skills add firetiger-oss/skills@plan-change-control
npx skills add firetiger-oss/skills@execute-change-control
```

The umbrella `change-control` skill checks for the presence of the two specialised skills at runtime and prints the install command for whichever is missing. Power users may install the specialised skills directly without the umbrella.

### Per-platform install paths

`npx skills add` writes to the platform's standard skill directory. If you install manually instead, point your platform at the relevant folder:

| Platform | Skill directory |
|----------|-----------------|
| Claude Code | `~/.claude/skills/<skill-name>/` |
| Codex | `~/.codex/skills/<skill-name>/` |
| Cursor | platform-managed; use `npx skills add` |
| Cline / Continue / Windsurf / Gemini / Copilot | follow each platform's skill-install docs |

### Manual install

```sh
git clone https://github.com/firetiger-oss/skills ~/firetiger-skills
mkdir -p ~/.claude/skills
ln -s ~/firetiger-skills/change-control            ~/.claude/skills/change-control
ln -s ~/firetiger-skills/plan-change-control       ~/.claude/skills/plan-change-control
ln -s ~/firetiger-skills/execute-change-control    ~/.claude/skills/execute-change-control
```

## What the skills do

### `change-control` (umbrella)

Routes the agent to the right sub-skill given the user's intent: planning a release, watching a rollout, both. Keeps the brand and the namespace cohesive in skill listings; doesn't do the work itself.

### `plan-change-control`

Adds a multi-environment monitoring section to the agent's plan for an upcoming code change. Picks SLIs (golden signals + intended-effect + business outcome), queries 24-hour baselines, sets baseline-referenced thresholds, picks a checkpoint schedule based on the risk tier, and writes the result into the plan file. Triggers automatically when the user is preparing a code change for production, planning a release, or doing post-deploy validation prep.

### `execute-change-control`

Runs the plan after the deploy is triggered. Polls each environment's deploy system on a 30-second cadence for the rollout, runs each checkpoint against the indicators with `GROUP BY environment`, applies evidence discipline (≥24h baseline + same-time-of-day prior + analytical reason + variance test), and emits per-environment progress reports inline as normal assistant messages. Sleeps between checkpoints via the agent's wake-up scheduler. On the first regression detected in any environment, hands off into plan mode so the same session can fix the issue. Intentionally foreground, intentionally single-issue.

## Worked examples

The `examples/` directory contains five concrete monitoring plans:
- `low-risk-bugfix.md` — single-environment, two early checkpoints.
- `medium-risk-api-change.md` — staging + production.
- `high-risk-db-migration.md` — staging + production with the full +24h and +72h checkpoints.
- `high-risk-infra-change.md` — staging + production, infra-touching change.
- `multi-region-rollout.md` — four regions fanned out via an ArgoCD `ApplicationSet`.

These are the templates `plan-change-control` aims to produce.

## Methodology

The skills are anchored on the Google SRE book. Each `references/sre-vocabulary.md` cites the chapters that ground the terms used:

| Concept | SRE book |
|---------|----------|
| Golden signals (latency, traffic, errors, saturation) | ch. 6 |
| SLI / SLO | ch. 4 |
| Error budget | ch. 3 |
| Blast radius / cascading failures | ch. 12 |
| Canary analysis | ch. 27 |
| Post-deploy validation | ch. 8 |
| MTTR | ch. 13 |

## Limits

The skills run locally and are stateless across sessions. Deliberate scope decisions and graduation hints live in `references/limitations.md` (one copy per skill, identical content). The short version: the skills don't persist plans across team members or outlive a coding-agent session, they handle one regression at a time, and they don't auto-rollback. If those limits matter for your team, a hosted version that runs the same methodology server-side is at [firetiger.com](https://firetiger.com).

## Contributing

Issues and pull requests welcome. If you find the skill mis-triggers (fires when it shouldn't, doesn't fire when it should), open an issue with the prompt that surprised you — the skill descriptions are tuned via [skill-creator](https://github.com/anthropic-experimental/skills) `run_loop`, and real triggering data is the most useful input.

If this is useful, please ⭐ the repo. Install velocity and stars feed into how `find-skills` and skills.sh surface this work to other teams.

## License

Apache 2.0. See [LICENSE](LICENSE).
