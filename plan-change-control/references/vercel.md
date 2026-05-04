# Vercel (deploy detection)

## Detection

The repo uses Vercel when `vercel.json` or `.vercel/` exists, or when the project root has a Next.js / Nuxt / SvelteKit setup linked to Vercel. The `vercel` CLI is the primary tool; `VERCEL_TOKEN` enables non-interactive use.

## Vercel's deploy model

Every push triggers a *Preview* deployment. Merging to the production branch promotes a preview to *Production* (or triggers a fresh production deployment). The monitored "envs" are typically:
- `production` — the production deployment.
- One or more `preview` aliases (per-PR, per-branch).

Custom environments (Vercel's "Environments" feature, beyond preview/prod) are listed with their own names.

## Single-env deploy detection (production)

```
vercel ls --json --token=$VERCEL_TOKEN \
  | jq '[.[] | select(.target == "production") | { url, state, target, createdAt, meta: .meta.githubCommitSha }] | .[0]'
```

Expected match:
- `state == "READY"`
- `meta.githubCommitSha == <merge_sha>` (Vercel records the source commit in `meta`).

## Preview environment

```
vercel ls --json --token=$VERCEL_TOKEN \
  | jq '[.[] | select(.target == "preview" and (.meta.githubCommitRef == "<branch>")) | { url, state, target }] | .[0]'
```

## Custom environments

If the team uses Vercel's named environments (e.g. `staging`, `qa`):

```
vercel ls --json --token=$VERCEL_TOKEN --environment staging
```

## Edge functions and serverless build duration

Vercel deploys can take 1–5 minutes from `BUILDING` to `READY`. The poll cadence (30s) is appropriate.

## Common pitfalls

- **`url` vs `alias`.** Each deployment has a unique URL; the production *alias* (e.g. `myapp.com`) points at whichever deployment is currently promoted. Use `state` and `target` to identify, not URL.
- **Edge regions.** Vercel deploys to all configured edge regions simultaneously; there's no per-region deploy-time. If the plan needs per-region monitoring, treat it as one env at the deploy-detection level and split per-region only at the indicator level (see [multi-env.md](multi-env.md)).
- **Branch-based preview confusion.** A single PR may have multiple preview deployments (one per push). Filter on `meta.githubCommitSha` rather than the latest preview to ensure you're matching the merged commit.
