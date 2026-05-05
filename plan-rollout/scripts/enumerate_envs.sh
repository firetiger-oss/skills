#!/usr/bin/env bash
# Enumerate target environments by inspecting deploy config in the cwd.
#
# Usage: enumerate_envs.sh [path]   (default: current directory)
#
# Inspects:
#   - .github/workflows/*.y*ml for matrix.env / per-env workflows
#   - argocd/, gitops/, *applicationset.yaml for ApplicationSet generators
#   - vercel.json, .vercel/ for preview/prod targets
#   - terraform/stacks/*, deployments/* for per-stack tfvars
#   - helm/values-*.yaml, helmfile.yaml for per-environment values
#   - netlify.toml (Netlify git-integration)
#   - render.yaml (Render auto-deploy)
#   - wrangler.toml with [pages] section (Cloudflare Pages)
#   - fly.toml (Fly.io)
#   - Heuristic: package.json with Next/Astro/Remix/Nuxt/SvelteKit + no GH Actions deploy + no IaC dir
#     → likely Vercel/Netlify git-integration
#
# Output: one env name per line on stdout.
# Stderr: emits `no-deploy-config-detected` when zero stdout entries are produced,
# so the agent knows to ask the user explicitly.
set -u

ROOT="${1:-.}"

# Collect all detected envs, then de-dupe and emit at end. Using a temp file to
# avoid subshell-loop variable scoping headaches.
TMP_OUT=$(mktemp)
trap 'rm -f "$TMP_OUT"' EXIT

emit() {
    echo "$1" >> "$TMP_OUT"
}

# GitHub Actions matrix
if compgen -G "$ROOT/.github/workflows/*.yml" >/dev/null 2>&1 || compgen -G "$ROOT/.github/workflows/*.yaml" >/dev/null 2>&1; then
    grep -hA 20 -E '^\s*matrix:' "$ROOT/.github/workflows/"*.y*ml 2>/dev/null \
        | grep -E '^\s+env:' -A 5 \
        | grep -E '^\s+-\s' \
        | sed -E 's/^\s+-\s+//; s/[",]//g' \
        | while read -r e; do
            [ -n "$e" ] && emit "gh-matrix:$e"
          done
    for wf in "$ROOT/.github/workflows/"*.y*ml; do
        [ -f "$wf" ] || continue
        name=$(basename "$wf" | sed -E 's/\.(yml|yaml)$//')
        case "$name" in
            deploy-*) emit "gh-workflow:${name#deploy-}" ;;
        esac
    done
fi

# ArgoCD ApplicationSet
for f in "$ROOT"/argocd/**/*.y*ml "$ROOT"/gitops/**/*.y*ml "$ROOT"/**/*applicationset.y*ml; do
    [ -f "$f" ] || continue
    grep -E 'name:\s' "$f" 2>/dev/null | head -5 | sed -E 's/.*name:\s*//; s/[",]//g' | while read -r n; do
        [ -n "$n" ] && emit "argocd:$n"
    done
done

# Vercel (explicit config)
if [ -f "$ROOT/vercel.json" ] || [ -d "$ROOT/.vercel" ]; then
    emit "vercel:production"
    emit "vercel:preview"
fi

# Netlify (git-integration via netlify.toml)
if [ -f "$ROOT/netlify.toml" ]; then
    emit "netlify:production"
    emit "netlify:deploy-preview"
fi

# Cloudflare Pages (wrangler.toml with a [pages] section)
if [ -f "$ROOT/wrangler.toml" ] && grep -qE '^\s*\[pages\]' "$ROOT/wrangler.toml" 2>/dev/null; then
    name=$(grep -E '^\s*name\s*=' "$ROOT/wrangler.toml" 2>/dev/null | head -1 | sed -E 's/.*=\s*"?([^"]+)"?/\1/' | tr -d ' ')
    emit "cloudflare-pages:${name:-unknown}"
fi

# Render
if [ -f "$ROOT/render.yaml" ]; then
    grep -E '^\s*-\s*type:' "$ROOT/render.yaml" 2>/dev/null > /dev/null && \
        grep -E '^\s*name:' "$ROOT/render.yaml" 2>/dev/null | sed -E 's/.*name:\s*//; s/[",]//g' | while read -r n; do
            [ -n "$n" ] && emit "render:$n"
        done
fi

# Fly.io
if [ -f "$ROOT/fly.toml" ]; then
    name=$(grep -E '^\s*app\s*=' "$ROOT/fly.toml" 2>/dev/null | head -1 | sed -E 's/.*=\s*"?([^"]+)"?/\1/' | tr -d ' ')
    emit "fly:${name:-unknown}"
fi

# Terraform stacks (firetiger-style: terraform/{aws,gcp}/deployment/stacks/<name>/)
for d in "$ROOT"/terraform/*/deployment/stacks/* "$ROOT"/terraform/stacks/*; do
    [ -d "$d" ] || continue
    emit "terraform:$(basename "$d")"
done

# Helmfile / helm per-env values files
for f in "$ROOT"/helm/values-*.yaml "$ROOT"/helmfile/*.yaml; do
    [ -f "$f" ] || continue
    name=$(basename "$f" | sed -E 's/^values-//; s/\.ya?ml$//')
    emit "helm:$name"
done

# Heuristic: if nothing detected so far AND package.json exists with a known
# JS-meta-framework AND no GH Actions deploy job AND no IaC dir, the repo is
# probably hosted via a git-integration deploy (Vercel/Netlify GitHub app, etc).
# This is a hint, not a definitive answer — the agent should confirm with user.
if [ ! -s "$TMP_OUT" ] && [ -f "$ROOT/package.json" ]; then
    if grep -qE '"(next|astro|@remix-run/[^"]+|nuxt|@sveltejs/kit)"\s*:' "$ROOT/package.json" 2>/dev/null; then
        has_gh_deploy=0
        if compgen -G "$ROOT/.github/workflows/deploy*.y*ml" >/dev/null 2>&1; then
            has_gh_deploy=1
        fi
        has_iac=0
        for d in "$ROOT/terraform" "$ROOT/argocd" "$ROOT/helm" "$ROOT/k8s"; do
            [ -d "$d" ] && has_iac=1
        done
        if [ "$has_gh_deploy" = "0" ] && [ "$has_iac" = "0" ]; then
            emit "git-integration:likely-vercel-or-netlify"
        fi
    fi
fi

# De-dupe + emit
if [ -s "$TMP_OUT" ]; then
    sort -u "$TMP_OUT"
else
    echo "no-deploy-config-detected" >&2
fi
