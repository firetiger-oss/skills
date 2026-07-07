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

| Consumer | Layout produced by the sync |
|----------|------------------------------|
| [`cursor-plugin`](https://github.com/firetiger-oss/cursor-plugin) | `skills/<skill>/…` verbatim (its `.cursor-plugin/plugin.json` declares `"skills": "skills"`). |
| [`claude-plugin`](https://github.com/firetiger-oss/claude-plugin) | `skills/<skill>/…` verbatim **plus** thin `commands/<name>.md` slash-command wrappers that just invoke the matching skill. |

The command name for a skill drops the leading `firetiger-` (e.g.
`firetiger-query` → `/query`); the router skill `firetiger` keeps its name.
The command bodies are stubs — the real content lives only in `skills/`.

> The website's `.well-known/agent-skills` index and **skills.sh** read *this*
> repo directly (`npx skills add firetiger-oss/skills`) and need **no** sync.

## How it works

- **Vendored copy, not a submodule.** Plugin marketplaces and `skills.sh` don't
  init submodules, so the skill files must be physically present. The sync
  copies them in.
- **`scripts/sync-skills.sh`** copies the canonical skill folders (every
  top-level dir with a `SKILL.md`) into a target checkout, applies the per-host
  transform, installs a drift-check workflow, and writes a stamp
  (`skills/.firetiger-skills-source`) recording the source repo, tag, and a
  content hash.
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

## Running it locally

Test against local checkouts of the plugins before tagging:

```sh
make sync         CURSOR=../cursor-plugin CLAUDE=../claude-plugin TAG=v1.2.3
make sync-cursor  CURSOR=../cursor-plugin
make sync-claude  CLAUDE=../claude-plugin
```

Or call the script directly:

```sh
scripts/sync-skills.sh --host cursor --target ../cursor-plugin --tag v1.2.3
scripts/sync-skills.sh --host claude --target ../claude-plugin --tag v1.2.3
```

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

The sync **installs a drift-check workflow into each consumer**
(`.github/workflows/firetiger-skills-drift.yml`). On every push/PR touching
`skills/**` it checks out this repo at the stamped tag and runs `check-drift.sh`,
failing CI if the vendored skills were hand-edited. So drift can't silently
reappear.

Check locally:

```sh
make check-drift CURSOR=../cursor-plugin CLAUDE=../claude-plugin
```
