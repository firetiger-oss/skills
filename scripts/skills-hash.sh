#!/usr/bin/env bash
#
# skills-hash.sh — deterministic content hash of a set of canonical skills.
#
# A "skill" is any directory that contains a SKILL.md. The hash covers every
# file under every skill directory found beneath ROOT, keyed by the file's path
# *relative to the skill root* (so a canonical checkout and a vendored copy of
# the same skills produce the SAME hash):
#
#   canonical repo root:   firetiger-query/SKILL.md            -> firetiger-query/SKILL.md
#   vendored plugin skills: skills/firetiger-query/SKILL.md    -> firetiger-query/SKILL.md   (ROOT=skills)
#
# The sync stamp (.firetiger-skills-source) is excluded so the hash is stable
# across (re)stamping. Non-skill files at ROOT (README, LICENSE, scripts/, …)
# are ignored because they are not under a SKILL.md directory.
#
# Usage: skills-hash.sh <root-dir>
# Prints: a single sha256 hex digest.

set -euo pipefail

ROOT="${1:?usage: skills-hash.sh <root-dir>}"
STAMP_NAME=".firetiger-skills-source"

if [ ! -d "$ROOT" ]; then
  echo "skills-hash.sh: not a directory: $ROOT" >&2
  exit 1
fi

cd "$ROOT"

# sha256 helper that works on both macOS (shasum) and Linux CI.
sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    sha256sum | awk '{print $1}'
  fi
}

# Collect the skill directories (dir of each SKILL.md), then every file within
# them, excluding the stamp. Sort with a stable, locale-independent order.
{
  while IFS= read -r -d '' skillmd; do
    dir=$(dirname "$skillmd")
    find "$dir" -type f ! -name "$STAMP_NAME" -print0
  done < <(find . -type f -name SKILL.md -print0)
} | LC_ALL=C sort -z | {
  # For each file emit "sha256(content)  relative/path\n"; then hash the whole
  # manifest so both content and layout are covered.
  while IFS= read -r -d '' f; do
    rel="${f#./}"
    printf '%s  %s\n' "$(sha256 <"$f")" "$rel"
  done
} | sha256
