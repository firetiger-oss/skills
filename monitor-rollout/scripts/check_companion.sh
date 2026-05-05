#!/usr/bin/env bash
# Probe whether plan-rollout is installed (the executor's input contract).
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
    if [ -f "$root/plan-rollout/SKILL.md" ]; then
        exit 0
    fi
done

cat <<'EOF'
The companion skill plan-rollout is not installed.

monitor-rollout reads a monitoring plan produced by plan-rollout. Easiest
fix — install the whole rollout family with one command:

  npx skills add firetiger-oss/skills --all

Or install only the planner:

  npx skills add firetiger-oss/skills --skill plan-rollout

Then re-run plan-rollout on the diff first, save the resulting plan to a
file, and re-invoke /monitor-rollout <path-to-plan> against that file.
EOF
exit 1
