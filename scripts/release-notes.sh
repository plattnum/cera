#!/usr/bin/env bash
# Prints the notes for a release: the version's section of CHANGELOG.md, without its heading.
# Fails when there is no section for the version, or it is empty.
#     ./scripts/release-notes.sh 0.6.1
set -euo pipefail
version="${1:?usage: release-notes.sh <version>}"
cd "$(dirname "$0")/.."
notes="$(awk -v version="$version" '
    /^## / { if (found) exit; found = ($2 == version); next }
    found { print }
' CHANGELOG.md | sed -e '/./,$!d')"
if [ -z "$notes" ]; then
    echo "::error::CHANGELOG.md has no notes for $version. Add a \"## $version\" section." >&2
    exit 1
fi
printf '%s\n' "$notes"
