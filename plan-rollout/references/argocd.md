# ArgoCD (deploy detection)

## Detection

The repo uses ArgoCD when an `argocd/`, `gitops/`, or `*-applicationset.yaml` directory exists, or when the `argocd` CLI is configured (`argocd context`, `argocd app list`).

ArgoCD's deploy model is *pull-based*: the controller syncs a desired state (a git revision) into a cluster. "Deploy detected" means the cluster's running revision now equals (or is an ancestor of) the merge SHA.

## Single-app deploy detection

```
argocd app get <app-name> -o json \
  | jq '{ syncStatus: .status.sync.status, revision: .status.sync.revision, healthStatus: .status.health.status }'
```

Expected match:
- `syncStatus == "Synced"`
- `revision == <merge_sha>` *or* `revision` is a descendant of `<merge_sha>` (the merge_sha is in the deployed code's ancestry).
- `healthStatus == "Healthy"`

## Ancestry check (canary-safe)

ArgoCD may sync to a *later* commit than the merge SHA if other PRs land between merge and sync. Use `git merge-base --is-ancestor <merge_sha> <revision> && echo yes` against a local checkout to verify ancestry.

This matches the closed-source product's `service/monitoring_plans/activator.go` logic. Do not skip the ancestry check — it's the difference between catching the deploy and missing it.

## Multi-cluster ApplicationSet

When the repo uses `ApplicationSet` to fan out the same app across clusters or tenants:

```yaml
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            tier: prod
  template:
    metadata:
      name: '{{name}}-my-svc'
```

Each generated `Application` has its own sync state. Enumerate them:

```
argocd app list --selector 'app.kubernetes.io/instance=my-svc' -o json \
  | jq '.[] | { name: .metadata.name, syncStatus: .status.sync.status, revision: .status.sync.revision }'
```

In the plan, list each generated app as a separate environment with its own deploy-detection block. Names usually include the cluster or region (`my-svc-prod-us-east-1`, `my-svc-prod-eu-west-1`).

## Sync waves

If the app uses sync waves (`argocd.argoproj.io/sync-wave: "N"`), partial syncs can show as `Synced` while later waves are still running. Add a `--health` check to make sure pods are actually `Healthy` before recording deploy_time.

## Common pitfalls

- **`Synced` doesn't mean `Healthy`.** Always check both.
- **Auto-sync vs manual sync.** Manual-sync apps don't update on PR merge — the user has to click sync. The plan should note this and the user should expect to trigger sync manually.
- **Resource hooks.** PreSync/PostSync hooks can extend the apparent deploy duration. Wait for `Healthy`, not just `Synced`.
- **Cross-cluster credentials.** `argocd app list` works only against clusters the local CLI is logged into. Multi-cluster monitoring may need `argocd login` per cluster, or read-only via the ArgoCD API server with a token.
