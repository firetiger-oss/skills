# rollout decision tree

## Contents
- The four invocation forms
- The three phases
- Routing matrix
- Worked examples
- Edge cases

## The four invocation forms

| Form | Args | Use when |
|------|------|----------|
| `/rollout` | none | In-session work; current branch / open PR. Most common. |
| `/rollout to <env>` | `to <env>` | Same as above, env-targeted. |
| `/rollout PR <num>` | `PR <num>` | Out-of-session via `gh CLI`; no local checkout needed. |
| `/rollout PR <num> to <env>` | both | Out-of-session, env-targeted. |

Argument patterns the parser accepts: `PR <num>`, `pr <num>`, `#<num>` for the PR; `to <env>` for the target. Any other tokens → ask the user to clarify.

## The three phases

Internal distinctions the orchestrator computes after parsing the invocation:

| Phase | Trigger | Behaviour |
|-------|---------|-----------|
| **pre-merge** | PR is OPEN | Plan from current diff → consent gate → `gh pr merge` → wait/trigger deploy → monitor. |
| **merged-not-deployed** | PR is MERGED, deploy hasn't caught up yet | Plan with `--merge-sha` → wait/trigger deploy → monitor. No merge step. |
| **deployed** | PR is MERGED, deploy already shipped | Plan with `--merge-sha` → skip merge + trigger → monitor (catch-up mode). |

## Routing matrix

```
                 ┌──────────────────────┐
                 │  Parse invocation   │
                 └──────────┬───────────┘
                            │
                ┌───────────┴───────────┐
              No PR arg            PR <num>
              (current branch)     (gh pr view)
                │                       │
                ▼                       ▼
         git status +              state == OPEN ?
         gh pr status                 │       │
            │                       yes      no (MERGED)
            ▼                       │        │
       open PR  →  pre-merge        ▼        ▼
       merged   →  merged-          pre-     merged-
                   not-deployed     merge    not-deployed
                                              │
                                              ▼
                                       deploy already
                                       caught up?
                                          │      │
                                        yes      no
                                          ▼      ▼
                                    deployed  merged-
                                    (catch-   not-
                                    up)       deployed
```

Then the orchestrator runs phases 3–5 of the workflow uniformly: plan (with `--merge-sha` if not pre-merge), merge + deploy (with consent gates if pre-merge), monitor.

## Worked examples per form

**`/rollout`** (in-session, open PR on the current branch):
- *"Ship this."*
- *"Roll this out."*
- *"Deploy this PR and watch it."*

**`/rollout to staging`** (in-session, env-targeted):
- *"Roll this out to staging."*
- *"Ship to staging only — prod can wait."*
- *"Deploy this to staging and monitor it."*

**`/rollout PR 1234`** (out-of-session, no local checkout):
- *"Watch PR #1234's rollout — I'm not on that machine."*
- *"Help me deploy and monitor github.com/.../pull/1234."*
- *"Roll out PR 1234 from my laptop while I'm here."*

**`/rollout PR 1234 to production`** (out-of-session, env-targeted):
- *"Promote PR 1234 to production and watch it."*
- *"Roll out PR 1234 to prod-eu only."*

## Edge cases

- **Dirty working tree, no PR** — phase = ambiguous. Ask: *"You have uncommitted changes and no open PR. Are we shipping this branch (commit + push first?), reviving an existing PR (which one?), or watching a deploy that's already out (which commit?)."*
- **PR already closed without merge** — refuse: *"PR #<num> was closed without merging. There's nothing to roll out."*
- **PR merged but deploy never observed within 30 min** — phase = merged-not-deployed; monitor-rollout's existing 30-min `WARNING` flow handles it. Ask the user whether to keep polling or abort.
- **Multi-PR coordinated rollout** — the orchestrator targets one PR per invocation. For multi-PR, the user runs `/rollout PR <num>` per change (sequential, not parallel — see `limitations.md`).
- **`to <env>` doesn't match any enumerated env** — ask once: *"`<env>` isn't in the deploy system's env list (`<list>`). Did you mean one of those, or proceed anyway?"*
- **Open PR + `to <env>` (env-targeted pre-merge)** — plan + merge proceed normally, but monitor scopes to `<env>` only. The merge itself is org-wide; the monitoring window is env-scoped.
- **Hotfix that's already merged + deploying** — phase = merged-not-deployed; the rollout_skill's existing `--merge-sha` flow handles it. Skip +24h / +72h checkpoints unless the hotfix touches infra (the user can override the schedule when invoking).
- **Change is documentation-only** — neither plan-rollout nor monitor-rollout is warranted. Tell the user no rollout monitoring is needed (no production behaviour change).
