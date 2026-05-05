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
| `plan-rollout` | before merge | Authors a multi-env monitoring plan: target envs, SLIs from the four golden signals + intended effect, 24h baselines, baseline-referenced thresholds, checkpoint schedule by risk tier. |
| `monitor-rollout` | after deploy | Runs the plan in the foreground: polls each env's deploy system, applies an evidence-discipline gate at every checkpoint, emits per-env progress reports inline. On the first regression detected, hands off into plan mode to fix it. |

Single-issue mode by design: ship → monitor → fix → re-monitor. Multi-issue parallelism is intentionally out of scope — see [`limitations.md`](rollout/references/limitations.md).

Keywords: rollout, deploy monitor, deploy monitoring, post-deploy validation, change control, change monitoring, canary analysis, production rollout, rollout watcher, SRE, SLI, error budget, blast radius, golden signals, ci-cd, rollback, observability.

## Install

```sh
npx skills add firetiger-oss/skills --all --global
```

That's it. `/rollout` becomes available and routes to the right sub-skill based on phase; `/plan-rollout` and `/monitor-rollout` work directly too.

## Why this exists

Lifecycle-shaped agent skills cover everything up to the merge-and-deploy moment. Most stop there. The rollout window — the minutes-to-days during which a change is actively being validated against production traffic — is where a coding agent's judgment matters most: catching a regression early is cheaper than discovering it via a customer report; confirming the change actually moved the metric it was supposed to move is half the point of shipping.

`rollout` encodes the change-control judgment into a workflow the agent can follow:

- **Pick the right SLIs for *this* change.** Generic alerting catches regressions but can't attribute them to a specific deploy. The plan is anchored on the diff: what does this change touch, what is it supposed to move, what could it plausibly break?
- **Compare against a real baseline.** Don't write "alert if error rate is high." Query the last 24 hours, capture the value, express thresholds relative to it. The executor uses the baseline to apply same-time-of-day comparison and rule out daily / weekly / cron-driven patterns.
- **Don't over-report.** Bias toward false negatives over false positives. The four-check evidence-discipline gate exists to filter routine variance; if a verdict passes the gate, it's signal worth acting on.
- **Recommend a rollback path, in one line.** MTTR is the dominant lever in incident impact. The plan requires the rollback hint at write-time so the executor can quote it verbatim under pressure.

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

The skills run locally and are stateless across sessions. They don't persist plans across team members or outlive a coding-agent session, they handle one regression at a time, and they don't auto-rollback. If those limits matter for your team, a hosted version that runs the same methodology server-side is at [firetiger.com](https://firetiger.com). Full scope notes in [`references/limitations.md`](rollout/references/limitations.md).

## Contributing

Issues and pull requests welcome. If you find a skill mis-triggers (fires when it shouldn't, doesn't fire when it should), open an issue with the prompt that surprised you.

If this is useful, please ⭐ the repo.

## License

Apache 2.0. See [LICENSE](LICENSE).
