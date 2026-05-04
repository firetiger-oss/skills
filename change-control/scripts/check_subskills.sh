#!/usr/bin/env bash
# Probe whether the sub-skills required for the requested phase are installed.
#
# Usage: check_subskills.sh <plan|execute|both>
#
# Exit 0 if everything needed is installed; exit 1 with an install-hint on
# stdout if anything is missing. The umbrella skill prints stdout verbatim
# to the user when this script returns non-zero.
#
# We probe by checking the platform-standard skill directories rather than by
# trying to execute slash-commands — different agent platforms expose skills
# differently, but all of them install into a known on-disk path.

set -u

PHASE="${1:-both}"

# Skill directories per platform. We check all of them so this script works
# regardless of which agent the user is running. The list comes from
# README.md's per-platform table; keep them in sync when adding platforms.
CANDIDATE_ROOTS=(
    "$HOME/.claude/skills"
    "$HOME/.codex/skills"
    "$HOME/.cursor/skills"
)

skill_installed() {
    local name="$1"
    for root in "${CANDIDATE_ROOTS[@]}"; do
        if [ -f "$root/$name/SKILL.md" ]; then
            return 0
        fi
    done
    return 1
}

needed=()
case "$PHASE" in
    plan)    needed=("plan-change-control") ;;
    execute) needed=("execute-change-control") ;;
    both)    needed=("plan-change-control" "execute-change-control") ;;
    *)
        echo "check_subskills.sh: unknown phase '$PHASE' (expected plan|execute|both)" >&2
        exit 2
        ;;
esac

missing=()
for skill in "${needed[@]}"; do
    if ! skill_installed "$skill"; then
        missing+=("$skill")
    fi
done

if [ ${#missing[@]} -eq 0 ]; then
    exit 0
fi

echo "The change-control umbrella needs the following sub-skill(s), which are not installed:"
echo
for skill in "${missing[@]}"; do
    echo "  npx skills add firetiger-oss/skills@$skill"
done
echo
echo "Install the missing skill(s) and re-invoke change-control."
exit 1
