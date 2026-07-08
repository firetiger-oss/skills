# Skill distribution

Skills are **authored once here** and vendored into the two consumer plugin
repos by an automated, version-pinned sync. Never re-author a skill downstream —
edit it in this repo, tag, and let CI open the update PRs.

```
  author skill here  ──►  git tag vX.Y.Z  ──►  CI opens/updates a PR in each
  (top-level folders)      (push the tag)       plugin repo with refreshed skills
                                                 │
                                                 └─►  you merge each PR (deliberate,
                                                      version-pinned update)
```

## Who consumes what

Both consumers are **skills-only** and use the identical `skills/` layout, so the
sync is the same for both — no per-host transform.

| Consumer | Layout produced by the sync |
|----------|------------------------------|
| [`cursor-plugin`](https://github.com/firetiger-oss/cursor-plugin) | `skills/<skill>/…` verbatim (its `.cursor-plugin/plugin.json` declares `"skills": "skills"`). |
| [`claude-plugin`](https://github.com/firetiger-oss/claude-plugin) | `skills/<skill>/…` verbatim (Claude Code auto-discovers a plugin's `skills/` directory). |

There are **no command wrappers**. `claude-plugin` previously shipped
`commands/*.md`; that layout is retired — see [claude-plugin migration](#claude-plugin-migration-one-time).

> The website's `.well-known/agent-skills` index and **skills.sh** read *this*
> repo directly (`npx skills add firetiger-oss/skills`) and need **no** sync.

## How it works

- **Vendored copy, not a submodule.** Plugin marketplaces and `skills.sh` don't
  init submodules, so the skill files must be physically present. The sync
  copies them in.
- **`scripts/sync-skills.sh`** copies the canonical skill folders (every
  top-level dir with a `SKILL.md`) into a target checkout's `skills/` and writes
  a stamp (`skills/.firetiger-skills-source`) recording the source repo, tag, and
  a content hash. It is identical for both
  consumers; the only extra is claude-plugin's one-time `--migrate-skills-only`
  step (below).
- **`.github/workflows/sync-skills.yml`** runs the script for each consumer on a
  version-tag push and opens/updates a PR via
  [`peter-evans/create-pull-request`](https://github.com/peter-evans/create-pull-request).
  Re-runs update the same `firetiger-skills-sync` branch → the same PR.
- **Version pinning.** Each PR records the source tag; consumers update only by
  merging. A consumer can stay on an older tag deliberately.

## Releasing an update

1. Edit the skill(s) in the top-level folders here. Open a normal PR, merge.
2. Tag the release and push it:
   ```sh
   git tag v1.2.3 && git push origin v1.2.3
   ```
3. The **Sync skills to plugins** workflow opens/updates a PR in each plugin
   repo, titled `Sync Firetiger skills from v1.2.3`.
4. Review and merge each plugin PR when you want that plugin to move.

You can also trigger it manually from the Actions tab (**Sync skills to
plugins** → *Run workflow*). It defaults to a **dry run** (diff only in the job
summary); set `dry_run=false` to actually open PRs from a chosen ref.

## One-time setup (manual)

Add a repo secret **`SKILLS_SYNC_TOKEN`** to this repo — a fine-grained PAT or
GitHub App token with **`contents: write`** + **`pull_requests: write`** on both
`firetiger-oss/cursor-plugin` and `firetiger-oss/claude-plugin`. Without it the
workflow still runs but stays dry (diff only) and skips PR creation.

> `cursor-plugin` CI rejects commit messages containing the word "Claude". The
> sync workflow's commit message and committer are deliberately free of it — keep
> them that way if you edit the workflow.

## claude-plugin migration (one-time)

`claude-plugin` used to expose skills as `commands/*.md`. The sync retires that
when called with `--migrate-skills-only` (the workflow passes it for
claude-plugin). On the **first** sync — detected by the presence of a
`commands/` directory — it additionally:

- deletes `commands/` (skills-only; no command wrappers),
- bumps the minor version in `.claude-plugin/plugin.json` (e.g. `0.1.0` → `0.2.0`),
- rewrites the README's *Repository Layout* bullet and *Skills* table for the
  skills-only layout.

Once `commands/` is gone, these steps are skipped — later syncs only refresh
`skills/`, so the version and README aren't touched again. Claude Code needs no
`skills` field in `plugin.json`; it auto-discovers `skills/<skill>/SKILL.md`.

## Running it locally

Test against local checkouts of the plugins before tagging:

```sh
make sync         CURSOR=../cursor-plugin CLAUDE=../claude-plugin TAG=v1.2.3
make sync-cursor  CURSOR=../cursor-plugin
make sync-claude  CLAUDE=../claude-plugin
```

Or call the script directly:

```sh
scripts/sync-skills.sh --target ../cursor-plugin --tag v1.2.3
scripts/sync-skills.sh --target ../claude-plugin --tag v1.2.3 --migrate-skills-only
```

### Dry run

Add `--dry-run` (or `-n`) to preview a sync: it mutates a throwaway copy of the
target and prints the diff, writing **nothing** to the real target.

```sh
make dry-run       CURSOR=../cursor-plugin CLAUDE=../claude-plugin TAG=v1.2.3
make dry-run-claude CLAUDE=../claude-plugin       # includes the commands/ retirement

scripts/sync-skills.sh --target ../claude-plugin --tag v1.2.3 --migrate-skills-only --dry-run
```

The CI workflow has its own dry run: trigger **Sync skills to plugins** →
*Run workflow* (defaults to `dry_run=true`), which prints the per-consumer diff
to the job summary without opening PRs.

## Drift protection

A vendored copy must never diverge from canonical without going through the
sync. Two guards:

- **`scripts/skills-hash.sh <root>`** — deterministic content hash over every
  skill directory (a dir with a `SKILL.md`), keyed by path relative to the skill
  root, so a canonical checkout and a vendored copy of the same skills hash
  identically. The stamp file is excluded.
- **`scripts/check-drift.sh --target <plugin> [--canonical <repo>]`** —
  recomputes the vendored hash and fails if it differs from the stamp (someone
  edited the vendored skills downstream). With `--canonical` it also verifies
  the stamp matches canonical@`tag`, catching a forged stamp or a moved tag.

Each consumer carries a **drift-check workflow**
(`.github/workflows/firetiger-skills-drift.yml`). On every push/PR touching
`skills/**` it checks out this repo at the stamped tag and runs `check-drift.sh`,
failing CI if the vendored skills were hand-edited. So drift can't silently
reappear.

### Bootstrapping the drift workflow (one-time, per consumer)

The recurring sync does **not** push this workflow file. Writing under
`.github/workflows/` needs a token with `workflow` scope, and `SKILLS_SYNC_TOKEN`
is kept minimal (contents + pull_requests). The drift workflow is static
infrastructure, so it's installed once, out of band, with a credential that has
`workflow` scope (a maintainer's `gh`/PAT, or a GitHub App with Workflows: write):

```sh
scripts/bootstrap-drift-check.sh --target ../cursor-plugin
# then, in the plugin checkout:
git checkout -b add-firetiger-skills-drift-check
git add .github/workflows/firetiger-skills-drift.yml
git commit -m "ci: add Firetiger skills drift check"
gh pr create --fill
```

Do this once per plugin; afterwards the sync only refreshes `skills/`.

Check drift locally without CI:

```sh
make check-drift CURSOR=../cursor-plugin CLAUDE=../claude-plugin
```
