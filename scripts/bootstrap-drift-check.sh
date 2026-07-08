#!/usr/bin/env bash
#
# bootstrap-drift-check.sh — install the Firetiger skills drift-check workflow
# into a consumer plugin checkout (one-time, out of band).
#
# The recurring sync (sync-skills.sh + sync-skills.yml) intentionally does NOT
# push this file: writing under .github/workflows/ requires a token with
# `workflow` scope, and SKILLS_SYNC_TOKEN is kept minimal (contents +
# pull_requests only). So the drift workflow — static infrastructure that only
# needs to be added once — is bootstrapped here with a credential that HAS
# workflow scope (a maintainer's gh/PAT, or a GitHub App with Workflows: write),
# then committed and opened as a normal PR.
#
# Usage:
#   bootstrap-drift-check.sh --target <plugin-checkout>
#
# Then, in the checkout:
#   git checkout -b add-firetiger-skills-drift-check
#   git add .github/workflows/firetiger-skills-drift.yml
#   git commit -m "ci: add Firetiger skills drift check"
#   gh pr create --fill
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/consumer-drift-check.yml"

TARGET=""
die() { echo "bootstrap-drift-check.sh: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,25p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$TARGET" ] || die "missing --target <plugin-checkout>"
[ -d "$TARGET" ] || die "target is not a directory: $TARGET"
[ -f "$TEMPLATE" ] || die "template not found: $TEMPLATE"

OUT="$TARGET/.github/workflows/firetiger-skills-drift.yml"
mkdir -p "$(dirname "$OUT")"
cp "$TEMPLATE" "$OUT"
echo "Installed drift-check workflow -> ${OUT#"$TARGET"/}"
echo "Commit it and open a PR with a workflow-scoped credential."
