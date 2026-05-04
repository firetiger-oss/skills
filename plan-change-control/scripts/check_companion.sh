#!/usr/bin/env bash
# Probe whether execute-change-control is installed.
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
    if [ -f "$root/execute-change-control/SKILL.md" ]; then
        exit 0
    fi
done

cat <<'EOF'
The companion skill execute-change-control is not installed.

The plan you just wrote is meant to be run by execute-change-control once
the change ships. Install it with:

  npx skills add firetiger-oss/skills@execute-change-control

You can keep iterating on the plan in the meantime; the executor only needs
to be installed before the deploy lands.
EOF
exit 1
