#!/usr/bin/env bash
# Render a monitoring-plan section by filling in the template at
# assets/monitoring-plan-template.md with values from a JSON input on stdin.
#
# Usage:
#   cat plan.json | render_plan_section.sh [--out <path>] [--template <path>]
#
# Default behavior:
#   - Reads template from ../assets/monitoring-plan-template.md
#   - Writes rendered plan to .rollout/<branch>-monitoring-plan.md (relative to
#     the git root, derived from `git rev-parse --show-toplevel`).
#   - Prints the absolute path to the written file on stdout's last line so
#     the umbrella can thread it into the monitor-rollout invocation.
#
# Override --out <path> to write somewhere else (or "-" for stdout).
# Override --template <path> to use a different template.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../assets/monitoring-plan-template.md"
OUT_PATH=""

# --- arg parsing ---
while [ $# -gt 0 ]; do
    case "$1" in
        --out)
            OUT_PATH="$2"; shift 2
            ;;
        --template)
            TEMPLATE="$2"; shift 2
            ;;
        --help|-h)
            grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
            exit 0
            ;;
        *)
            echo "render_plan_section.sh: unknown arg '$1'" >&2
            exit 2
            ;;
    esac
done

if [ ! -f "$TEMPLATE" ]; then
    echo "render_plan_section.sh: template not found: $TEMPLATE" >&2
    exit 2
fi

INPUT="$(cat)"
if [ -z "$INPUT" ]; then
    echo "render_plan_section.sh: empty stdin (expected JSON with template fields)" >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "render_plan_section.sh: jq is required (install via 'brew install jq' or your package manager)" >&2
    exit 2
fi

# --- compute default OUT_PATH if not given ---
# Default convention: .rollout/<branch>-monitoring-plan.md relative to git root.
# Falls back to .rollout/monitoring-plan.md if not in a git repo.
if [ -z "$OUT_PATH" ]; then
    if git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
        # slugify branch (keep alphanum + hyphen, replace others with -)
        branch_slug=$(printf '%s' "$branch" | tr -c '[:alnum:]-' '-' | tr -s '-')
        OUT_PATH="$git_root/.rollout/${branch_slug}-monitoring-plan.md"
    else
        OUT_PATH="$(pwd)/.rollout/monitoring-plan.md"
    fi
fi

# --- field substitution ---
# Read each top-level JSON key into an env var of the same name (uppercased).
#
# Implementation note: we emit NUL-separated <key>\t<value>\0 records from jq
# and read them with `read -d ''` (NUL-as-delimiter, the bash idiom for NUL).
# The NUL byte is constructed via `[0] | implode` because literal NUL chars
# in jq source strings get filtered out in transit (shell quoting, file edit
# tools that disallow NULs, etc.); `[0] | implode` is pure ASCII source that
# constructs a 1-byte string with byte value 0 at runtime.
#
# An earlier version used newline-separated records with `read -d $'\0'`,
# which silently slurped the whole input on the first iteration because there
# was no NUL — only the first key/value got set and every subsequent
# ${PLAN_*} placeholder rendered as empty. NUL delimiters are the right shape
# for shell-piped JSON values that may themselves contain newlines.
while IFS=$'\t' read -r -d '' key value; do
    [ -z "$key" ] && continue
    var=$(printf '%s' "$key" | tr '[:lower:]-' '[:upper:]_')
    export "PLAN_$var=$value"
done < <(printf '%s' "$INPUT" | jq -j 'to_entries[] | "\(.key)\t\(.value)" + ([0] | implode)')

# --- render ---
render_to_stdout() {
    if command -v envsubst >/dev/null 2>&1; then
        envsubst < "$TEMPLATE"
    else
        out=$(cat "$TEMPLATE")
        while IFS='=' read -r name value; do
            case "$name" in
                PLAN_*)
                    out=$(printf '%s' "$out" | awk -v n="\${$name}" -v v="$value" '
                        { gsub(n, v); print }
                    ')
                    ;;
            esac
        done < <(env)
        printf '%s\n' "$out"
    fi
}

if [ "$OUT_PATH" = "-" ]; then
    render_to_stdout
else
    mkdir -p "$(dirname "$OUT_PATH")"
    render_to_stdout > "$OUT_PATH"
    # Last line of stdout is the absolute path — the umbrella greps this to
    # thread the plan into monitor-rollout.
    echo "$OUT_PATH"
fi
