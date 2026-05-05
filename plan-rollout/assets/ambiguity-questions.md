# Canonical wording for clarifying questions

Use these phrasings when the plan workflow hits an ambiguity in **interactive mode**. The wording matters: too vague and the user gives a non-answer, too specific and the user feels interrogated.

## Auto-mode behaviour

When the system signal indicates auto mode is active (a `system-reminder` mentions auto mode, or the agent is operating headless), do **NOT** ask these questions. Use the tier-defaults and log each skipped question as an explicit assumption in the rendered plan section, e.g.:

```
**Assumptions (auto mode):**
- Telemetry source: defaulted to Datadog (priority #1, MCP available)
- "Good" requests: 2xx only (auth-required 401s excluded)
- Feature flag rollout: assumed fully on (no flag found in diff)
- Rollback procedure: revert PR + redeploy via deploy.yml (inferred from CI config)
- Monitoring window: tier-default (medium = +10m,+30m,+1h,+2h)
```

The user reviews the rendered plan before invoking monitor-rollout — they retain veto and edit power on every assumption. Auto mode is the explicit instruction to proceed without blocking; respect it.

## Telemetry tool

Only ask if the priority order from `probe_telemetry_tools.sh` was inconclusive (e.g. several tools tied as "MCP available").

> "I see {Datadog} and {Honeycomb} are both available locally. Which one is canonical for {service}? I'll use that as the primary source for the indicators."

If the tools are very different in usage frequency, you can lead with a guess:

> "I'll default to Datadog for the indicators on {service} unless you'd rather I use Honeycomb. Just confirm or redirect."

## What counts as a "good" request

For ratio indicators where the success/failure cut is non-obvious.

> "For the {service} success-rate SLI, what counts as a 'good' request? Just 2xx, or 2xx+3xx? Should auth-required 401s count against the ratio or be excluded?"

## Feature flag rollout fraction

If the diff touches a flag-gated path.

> "This change is wired through feature flag `{flag-name}`. What's the rollout state — fully on, fraction-of-traffic, or off-by-default? I want the indicators to make sense for the actual exposed surface."

## Rollback procedure

Only ask if you genuinely couldn't infer one.

> "I don't see an obvious rollback path for this change. What's the on-call procedure if {service} regresses after this deploy? One line is fine."

## Monitoring window

Only ask if you want to override the tier default.

> "Default monitoring window for a {tier}-risk change is `{schedule}`. Do you want to extend it (e.g. for a slow rollout) or trim it (e.g. for a hotfix that has a fast rollback)?"

## Environment list

If `enumerate_envs.sh` returned a list you're not sure about.

> "Based on your deploy config, this change will land in {env list}. Confirm or amend — I want to make sure I'm not missing a region or tenant."

If the script returned nothing useful:

> "I couldn't auto-detect the deploy targets for this change. Which environments should I plan to monitor? Common shapes: just prod / staging+prod / multi-region (us-east, eu-west, etc.) / per-tenant fan-out."

## Business-outcome indicator

If you couldn't infer one from the diff.

> "Beyond the golden signals, is there a business-outcome metric this change is supposed to move? E.g. checkout success rate, signups/min, search clickthrough? Skipping if there isn't an obvious one."

## How to use these

- Ask one question at a time when possible. Bundling 4 questions into one prompt produces shallow answers.
- Quote back the answer in the next workflow step so the user sees you took it seriously.
- After step 10 of the workflow, do not ask further clarifying questions — finalise the plan.
