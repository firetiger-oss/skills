#!/usr/bin/env bash
#
# check-drift.sh — fail if a plugin's vendored skills have drifted from what the
# sync produced (i.e. someone edited the vendored copy downstream instead of
# editing the canonical skill upstream).
#
# It recomputes the content hash of <target>/skills and compares it to the hash
# recorded in the stamp (skills/.firetiger-skills-source). Because the stamp
# also records the source tag, a matching hash means the vendored skills are
# exactly what canonical@<tag> produced.
#
# Optionally, with --canonical <dir> pointing at a checkout of the canonical
# repo (typically at the stamped tag), it also verifies the stamp hash matches
# canonical@<tag>, catching a tampered/forged stamp.
#
# Usage:
#   check-drift.sh --target <plugin-dir> [--canonical <canonical-repo-dir>]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP_NAME=".firetiger-skills-source"

TARGET=""
CANONICAL=""

die() { echo "check-drift.sh: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target)    TARGET="${2:?}"; shift 2 ;;
    --canonical) CANONICAL="${2:?}"; shift 2 ;;
    -h|--help)   sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$TARGET" ] || die "missing --target <plugin-dir>"
SKILLS_DIR="$TARGET/skills"
STAMP="$SKILLS_DIR/$STAMP_NAME"
[ -d "$SKILLS_DIR" ] || die "no skills/ directory under $TARGET"
[ -f "$STAMP" ]      || die "no $STAMP_NAME stamp — was this synced with sync-skills.sh?"

# Parse KEY=VALUE lines from the stamp (ignoring comments).
stamp_val() { grep -E "^$1=" "$STAMP" | head -n1 | cut -d= -f2-; }
STAMPED_TAG="$(stamp_val tag)"
STAMPED_HASH="$(stamp_val hash)"
[ -n "$STAMPED_HASH" ] || die "stamp has no hash= line"

ACTUAL_HASH="$("$SCRIPT_DIR/skills-hash.sh" "$SKILLS_DIR")"

echo "Vendored skills stamped from tag: ${STAMPED_TAG:-<none>}"
echo "  stamped hash: $STAMPED_HASH"
echo "  actual  hash: $ACTUAL_HASH"

status=0
if [ "$ACTUAL_HASH" != "$STAMPED_HASH" ]; then
  echo "::error ::Vendored skills have DRIFTED from the stamped canonical tag." >&2
  echo "The skills under $SKILLS_DIR were edited downstream. Edit the canonical" >&2
  echo "skill in ${SOURCE_REPO:-firetiger-oss/skills} instead, then re-sync." >&2
  status=1
fi

if [ -n "$CANONICAL" ]; then
  CANON_HASH="$("$SCRIPT_DIR/skills-hash.sh" "$CANONICAL")"
  echo "  canonical hash (@${STAMPED_TAG}): $CANON_HASH"
  if [ "$CANON_HASH" != "$STAMPED_HASH" ]; then
    echo "::error ::Stamp hash does not match canonical@${STAMPED_TAG}." >&2
    echo "The stamp may be forged, or the tag was moved. Re-sync from a real tag." >&2
    status=1
  fi
fi

if [ "$status" -eq 0 ]; then
  echo "OK — vendored skills match canonical@${STAMPED_TAG}."
fi
exit "$status"
