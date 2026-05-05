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
#
# Output: one env name per line. Empty output = could not detect; the agent
# should fall back to the tier-default and ask the user.
set -u

ROOT="${1:-.}"

found=()

# GitHub Actions matrix
if compgen -G "$ROOT/.github/workflows/*.yml" >/dev/null 2>&1 || compgen -G "$ROOT/.github/workflows/*.yaml" >/dev/null 2>&1; then
    # Look for `matrix:\n      env:` patterns. Crude but works for the common shape.
    grep -hA 20 -E '^\s*matrix:' "$ROOT/.github/workflows/"*.y*ml 2>/dev/null \
        | grep -E '^\s+env:' -A 5 \
        | grep -E '^\s+-\s' \
        | sed -E 's/^\s+-\s+//; s/[",]//g' \
        | while read -r e; do
            [ -n "$e" ] && echo "gh-matrix:$e"
          done
    # Also pick up per-env workflow names
    for wf in "$ROOT/.github/workflows/"*.y*ml; do
        name=$(basename "$wf" | sed -E 's/\.(yml|yaml)$//')
        case "$name" in
            deploy-*) echo "gh-workflow:${name#deploy-}" ;;
        esac
    done
fi

# ArgoCD ApplicationSet
for f in "$ROOT"/argocd/**/*.y*ml "$ROOT"/gitops/**/*.y*ml "$ROOT"/**/*applicationset.y*ml; do
    [ -f "$f" ] || continue
    grep -E 'name:\s' "$f" 2>/dev/null | head -5 | sed -E 's/.*name:\s*//; s/[",]//g' | while read -r n; do
        [ -n "$n" ] && echo "argocd:$n"
    done
done

# Vercel
if [ -f "$ROOT/vercel.json" ] || [ -d "$ROOT/.vercel" ]; then
    echo "vercel:production"
    echo "vercel:preview"
fi

# Terraform stacks (firetiger-style: terraform/{aws,gcp}/deployment/stacks/<name>/)
for d in "$ROOT"/terraform/*/deployment/stacks/* "$ROOT"/terraform/stacks/*; do
    [ -d "$d" ] || continue
    echo "terraform:$(basename "$d")"
done

# Helmfile / helm per-env values files
for f in "$ROOT"/helm/values-*.yaml "$ROOT"/helmfile/*.yaml; do
    [ -f "$f" ] || continue
    name=$(basename "$f" | sed -E 's/^values-//; s/\.ya?ml$//')
    echo "helm:$name"
done

# Deduplicate
sort -u
