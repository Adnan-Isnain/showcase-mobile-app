#!/usr/bin/env bash
set -euo pipefail

FROM="" ; TO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM="$2"; shift 2 ;;
    --to)   TO="$2";   shift 2 ;;
    *) echo "Unknown arg $1"; exit 1 ;;
  esac
done

[[ -z "$FROM" || -z "$TO" ]] && { echo "Usage: $0 --from :moduleA --to :moduleB"; exit 1; }

FROM_PATH=$(echo "$FROM" | sed 's/^://; s/:/\//g')
GRADLE_FILE="${FROM_PATH}/build.gradle.kts"
[[ -f "$GRADLE_FILE" ]] || { echo "Cannot find ${GRADLE_FILE}"; exit 1; }

# Backup for safety
BAK="$(mktemp)"
cp -p "$GRADLE_FILE" "$BAK"

# Remove any line that is exactly the implementation(project(":x")) (ignoring leading/trailing spaces)
tmpf="$(mktemp)"
awk -v to="implementation(project(\\\":${TO#:}\\\"))" '
  BEGIN{removed=0}
  {
    line=$0
    norm=line
    sub(/^[[:space:]]+/,"",norm)
    sub(/[[:space:]]+$/,"",norm)
    if (norm == to) { removed++; next }
    print line
  }
  END{
    if (removed==0) {
      # no-op; still ok
    }
  }
' "$GRADLE_FILE" > "$tmpf" || { cp -p "$BAK" "$GRADLE_FILE"; rm -f "$tmpf" "$BAK"; exit 1; }

mv "$tmpf" "$GRADLE_FILE"

# If it still exists anywhere, inform but keep file (we already cleaned exact matches)
if grep -q "implementation(project(\"${TO}\")" "$GRADLE_FILE"; then
  echo "⚠️  Dependency string still exists (possibly different formatting or inside another block)."
  echo "    Searched for exact line: implementation(project(\"${TO}\"))"
else
  echo "Unlinked: ${FROM} -X-> ${TO}"
fi

rm -f "$BAK"
