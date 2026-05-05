# Example: static-site deploy monitoring plan

> Source change: a Next.js marketing site (`firetiger.com`) updates its homepage hero section. Deploys via Vercel git-integration on every push to `main`. No GH Actions workflow, no IaC. Telemetry: HTTP probes only (no Datadog / Honeycomb / Prom available for this surface).

## Monitoring plan

**Risk tier:** low — content-only change, no behaviour or API change; rollback is fast (one revert + auto-redeploy).
**Intended effect:** the new hero copy renders on `https://firetiger.com/`; the build SHA visible in `/api/version` matches the merged commit.
**Blast radius (unintended):** the homepage's render path (CSS, fonts, image assets); CDN edge cache may serve stale content for ~5 minutes during propagation.
**Rollback:** `gh pr revert <pr-number>` on the merged PR; Vercel auto-redeploys on the revert push.

### Environments

#### production
Deploy detection:
```
bash poll_http.sh https://firetiger.com/api/version --match-body-contains "<merge_sha>"
```
Match: HTTP 200 AND response body contains the merged commit SHA (the `/api/version` endpoint returns `{"build_sha":"..."}`).

#### preview (optional — only if the team monitors preview deploys)
Deploy detection:
```
bash poll_vercel.sh <merge_sha> preview
```
Match: Vercel deployment with `target=preview` and `meta.githubCommitSha == <merge_sha>` reaches `state=READY`.

### Indicators

| Name | Kind | Source | Baseline (24h) | Threshold | Direction | Scope |
|------|------|--------|----------------|-----------|-----------|-------|
| home-page-status | gauge | `shell` `curl -sS -o /dev/null -w "%{http_code}\n" https://firetiger.com/` | 200 | != 200 sustained 60s | unintended-watch | shared |
| build-sha-served | gauge | `shell` `curl -fsS https://firetiger.com/api/version \| jq -r .build_sha` | (n/a — first deploy of this change) | == "<merge_sha>" by +5m post-deploy | intended-up | shared |
| home-page-content | gauge | `shell` `curl -fsS https://firetiger.com/ \| grep -c "new hero copy text"` | 0 (pre-deploy) | >= 1 by +5m post-deploy | intended-up | shared |
| edge-cache-cf-cache-status | gauge | `shell` `curl -sI https://firetiger.com/ \| grep -i "cf-cache-status"` | varies (HIT/MISS/EXPIRED rotates with CDN TTL) | "EXPIRED" then back to "HIT" within 5m of deploy | unintended-watch | shared |
| home-page-load-time | gauge | `shell` `curl -sS -o /dev/null -w "%{time_total}\n" https://firetiger.com/` | 0.4s p50 | > 1.5s sustained 5m | unintended-watch | shared |

All indicators use `kind: shell` because no metrics backend covers this surface. The `monitor-rollout` executor runs each command at every checkpoint and compares stdout against the threshold expression.

### Checkpoints

`+5m, +10m, +30m`

(Tier-low default would be `+10m, +30m`; we add `+5m` because the intended effect — new content visible at the edge — is expected within minutes and we want to confirm cache propagation early. Static sites have a tighter feedback loop than backend services.)

### Activation

After the change merges and Vercel begins building, run:

```
/monitor-rollout examples/static-site-deploy.md
```

in this same session to monitor it. The executor will poll `/api/version` every 30s for the merge SHA, then run the indicator commands at +5m, +10m, +30m.
