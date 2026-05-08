#!/usr/bin/env bash
# Probe whether the sub-skills required for the requested phase are installed,
# plus optionally check that gh CLI is available + authenticated.
#
# Usage: check_subskills.sh <plan|monitor|both> [--require-gh]
#
# Exit 0 if everything needed is installed; exit 1 with an install / auth hint
# on stdout if anything is missing. The umbrella skill prints stdout verbatim
# to the user when this script returns non-zero.
#
# We probe by checking the platform-standard skill directories rather than by
# trying to execute slash-commands — different agent platforms expose skills
# differently, but all of them install into a known on-disk path.
#
# --require-gh is required for PR-based invocations (/rollout PR <num>); for
# in-session invocations gh is preferred but not strictly necessary.

set -u

PHASE="${1:-both}"
shift || true

REQUIRE_GH=0
while [ $# -gt 0 ]; do
    case "$1" in
        --require-gh) REQUIRE_GH=1; shift ;;
        *) echo "check_subskills.sh: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

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
    plan)    needed=("plan-rollout") ;;
    monitor) needed=("monitor-rollout") ;;
    both)    needed=("plan-rollout" "monitor-rollout") ;;
    *)
        echo "check_subskills.sh: unknown phase '$PHASE' (expected plan|monitor|both)" >&2
        exit 2
        ;;
esac

missing=()
for skill in "${needed[@]}"; do
    if ! skill_installed "$skill"; then
        missing+=("$skill")
    fi
done

# gh CLI check (only when --require-gh was passed)
gh_problem=""
if [ "$REQUIRE_GH" = "1" ]; then
    if ! command -v gh >/dev/null 2>&1; then
        gh_problem="not-installed"
    elif ! gh auth status >/dev/null 2>&1; then
        gh_problem="not-authenticated"
    fi
fi

if [ ${#missing[@]} -eq 0 ] && [ -z "$gh_problem" ]; then
    exit 0
fi

# Some hint to print
if [ ${#missing[@]} -gt 0 ]; then
    echo "The rollout umbrella needs the following sub-skill(s), which are not installed:"
    echo
    for skill in "${missing[@]}"; do
        echo "  - $skill"
    done
    echo
    echo "Easiest fix — install the whole rollout family with one command:"
    echo
    echo "  npx skills add firetiger-oss/skills --all"
    echo
    echo "Or install only the missing piece:"
    for skill in "${missing[@]}"; do
        echo "  npx skills add firetiger-oss/skills --skill $skill"
    done
    echo
fi

if [ -n "$gh_problem" ]; then
    case "$gh_problem" in
        not-installed)
            echo "PR-based /rollout invocations require the GitHub CLI (gh)."
            echo "Install:"
            echo
            echo "  brew install gh                               # macOS"
            echo "  https://cli.github.com/                       # other platforms"
            echo
            ;;
        not-authenticated)
            echo "PR-based /rollout invocations require gh CLI authentication."
            echo "Run:"
            echo
            echo "  gh auth login"
            echo
            ;;
    esac
fi

echo "Resolve the above and re-invoke /rollout."
exit 1
