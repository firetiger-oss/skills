# rollout: the missing post-ship lifecycle phase

A small family of open-source coding-agent skills for **what happens after you click deploy.** Anchored on Google's SRE book; designed to compose with verb-first lifecycle skills like `/spec`, `/plan`, `/build`, `/test`, `/review`, `/ship` (see Addy Osmani's [Beyond Vibe Coding](https://addyosmani.com/blog/agent-skills/) for that taxonomy).

```
/spec → /plan → /build → /test → /review → /ship → /rollout
                                                    └── plan-rollout
                                                    └── monitor-rollout
```

`/rollout` is the umbrella entry point. The two specialised skills do the work:

| Skill | Phase | What it does |
|-------|-------|--------------|
| `plan-rollout` | before merge | Authors a multi-environment monitoring plan: enumerates target envs (staging + prod, multi-region, fan-out), picks SLIs from the four golden signals + the change's intended effect, queries 24-hour baselines, sets baseline-referenced thresholds, picks a checkpoint schedule sized to the risk tier. |
| `monitor-rollout` | after deploy | Runs that plan in the foreground of the same coding-agent session: polls each environment's deploy system, sleeps between checkpoints via the agent's wake-up scheduler, applies an evidence-discipline gate at every check (≥24h baseline + same-time-of-day prior + analytical reason + variance test), emits per-environment progress reports inline. On the first regression detected in any environment, hands off into plan mode so the same session pivots to fixing it. |

Single-issue mode by design: ship → monitor → fix → re-monitor, linear, one focus at a time. Multi-issue parallelism is intentionally out of scope — see [`limitations.md`](rollout/references/limitations.md).

Keywords: rollout, deploy monitor, deploy monitoring, post-deploy validation, change control, change monitoring, canary analysis, production rollout, rollout watcher, SRE, SLI, error budget, blast radius, golden signals, ci-cd, rollback, observability.

## Install

One command installs all three skills:

```sh
npx skills add firetiger-oss/skills --all
```

That's it. The umbrella `rollout` skill becomes available as `/rollout` and routes to the right sub-skill based on phase; the specialised skills (`/plan-rollout`, `/monitor-rollout`) work directly too.

### Variants

```sh
# Global install (across all your projects)
npx skills add firetiger-oss/skills --all -g

# Specific agents only (e.g. just Claude Code and Cursor)
npx skills add firetiger-oss/skills --all --agent claude-code cursor

# Just one phase (power users who only want planning, or only execution)
npx skills add firetiger-oss/skills --skill plan-rollout
npx skills add firetiger-oss/skills --skill monitor-rollout
```

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
ln -s ~/firetiger-skills/rollout            ~/.claude/skills/rollout
ln -s ~/firetiger-skills/plan-rollout       ~/.claude/skills/plan-rollout
ln -s ~/firetiger-skills/monitor-rollout    ~/.claude/skills/monitor-rollout
```

## Why this exists

Lifecycle-shaped agent skills cover everything up to the merge-and-deploy moment. Most stop there. The rollout window — the minutes-to-days during which a change is actively being validated against production traffic — is where a coding agent's judgment matters most: catching a regression early is cheaper than discovering it via a customer report; confirming the change actually moved the metric it was supposed to move is half the point of shipping.

`rollout` encodes the change-control judgment into a workflow the agent can follow:

- **Pick the right SLIs for *this* change.** Generic alerting catches regressions but can't attribute them to a specific deploy. The plan is anchored on the diff: what does this change touch, what is it supposed to move, what could it plausibly break?
- **Compare against a real baseline.** Don't write "alert if error rate is high." Query the last 24 hours, capture the value, express thresholds relative to it. The executor uses the baseline to apply same-time-of-day comparison and rule out daily / weekly / cron-driven patterns.
- **Don't over-report.** Bias toward false negatives over false positives. The four-check evidence-discipline gate exists to filter routine variance; if a verdict passes the gate, it's signal worth acting on.
- **Recommend a rollback path, in one line.** MTTR is the dominant lever in incident impact. The plan requires the rollback hint at write-time so the executor can quote it verbatim under pressure.

## Worked examples

The `examples/` directory contains five concrete monitoring plans:

- [`low-risk-bugfix.md`](examples/low-risk-bugfix.md) — single-environment, two early checkpoints.
- [`medium-risk-api-change.md`](examples/medium-risk-api-change.md) — staging + production.
- [`high-risk-db-migration.md`](examples/high-risk-db-migration.md) — staging + production with the full +24h and +72h checkpoints.
- [`high-risk-infra-change.md`](examples/high-risk-infra-change.md) — staging + production, infra-touching change.
- [`multi-region-rollout.md`](examples/multi-region-rollout.md) — four regions fanned out via an ArgoCD `ApplicationSet`.

These are the templates `plan-rollout` aims to produce.

## Methodology

Anchored on the Google SRE book. Each `references/sre-vocabulary.md` cites the chapters that ground the terms used:

| Concept | SRE book |
|---------|----------|
| Golden signals (latency, traffic, errors, saturation) | ch. 6 |
| SLI / SLO | ch. 4 |
| Error budget | ch. 3 |
| Blast radius / cascading failures | ch. 12 |
| Canary analysis | ch. 27 |
| Post-deploy validation | ch. 8 (release engineering) |
| MTTR | ch. 13 |

## Limits

The skills run locally and are stateless across sessions. Deliberate scope decisions and graduation hints live in [`references/limitations.md`](rollout/references/limitations.md) (one copy per skill, identical content). The short version: the skills don't persist plans across team members or outlive a coding-agent session, they handle one regression at a time, and they don't auto-rollback. If those limits matter for your team, a hosted version that runs the same methodology server-side is at [firetiger.com](https://firetiger.com).

## Contributing

Issues and pull requests welcome. If you find a skill mis-triggers (fires when it shouldn't, doesn't fire when it should), open an issue with the prompt that surprised you — the skill descriptions are tuned via [skill-creator](https://github.com/anthropic-experimental/skills) `run_loop`, and real triggering data is the most useful input.

If this is useful, please ⭐ the repo. Install velocity and stars feed into how `find-skills` and skills.sh surface this work to other teams.

## License

Apache 2.0. See [LICENSE](LICENSE).
