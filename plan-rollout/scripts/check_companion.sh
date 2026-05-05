#!/usr/bin/env bash
# Probe whether monitor-rollout is installed.
#
# Usage: check_companion.sh
#
# Exit 0 if installed; exit 1 with an install hint on stdout.
set -u

CANDIDATE_ROOTS=(
    "$HOME/.claude/skills"
    "$HOME/.codex/skills"
    "$HOME/.cursor/skills"
)

for root in "${CANDIDATE_ROOTS[@]}"; do
    if [ -f "$root/monitor-rollout/SKILL.md" ]; then
        exit 0
    fi
done

cat <<'EOF'
The companion skill monitor-rollout is not installed.

The plan you just wrote is meant to be run by monitor-rollout once
the change ships. Install it with:

  npx skills add firetiger-oss/skills@monitor-rollout

You can keep iterating on the plan in the meantime; the executor only needs
to be installed before the deploy lands.
EOF
exit 1
