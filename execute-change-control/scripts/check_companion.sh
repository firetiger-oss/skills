#!/usr/bin/env bash
# Probe whether plan-change-control is installed (the executor's input contract).
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
    if [ -f "$root/plan-change-control/SKILL.md" ]; then
        exit 0
    fi
done

cat <<'EOF'
The companion skill plan-change-control is not installed.

execute-change-control reads a monitoring plan produced by plan-change-control.
Install it with:

  npx skills add firetiger-oss/skills@plan-change-control

Then re-run plan-change-control on the diff first, save the resulting plan to a
file, and re-invoke /execute-change-control <path-to-plan> against that file.
EOF
exit 1
