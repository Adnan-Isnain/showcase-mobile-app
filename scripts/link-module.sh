#!/usr/bin/env bash
set -euo pipefail
# -----------------------------------------------------------------------------
# Gradle Module Linker
# Author: (your name)
# Role: Senior Software Engineer
#
# Injects implementation(project(":to")) into the caller module's
# commonMain.dependencies { } block (JetBrains KMP layout).
# Idempotent: skips if link already exists.
# BSD-safe for macOS.
# -----------------------------------------------------------------------------

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

# Skip if already linked
grep -q "implementation(project(\"$TO\"))" "$GRADLE_FILE" && { echo "Already linked."; exit 0; }

# Inject into commonMain.dependencies { ... }
tmpf="$(mktemp)"
awk -v to="$TO" '
  BEGIN {in_kotlin=0; in_sets=0; cm=0}
  {
    print $0
    if ($0 ~ /kotlin[[:space:]]*\{/) in_kotlin=1
    if (in_kotlin==1 && $0 ~ /sourceSets[[:space:]]*\{/) in_sets=1
    if (in_sets==1 && $0 ~ /val[[:space:]]+commonMain[[:space:]]+by[[:space:]]+getting[[:space:]]*\{/) cm=1
    if (cm==1 && $0 ~ /dependencies[[:space:]]*\{/) {
      print "                implementation(project(\"" to "\"))"
      cm=2
    }
  }
' "$GRADLE_FILE" > "$tmpf"
mv "$tmpf" "$GRADLE_FILE"
echo "Linked: ${FROM} -> ${TO}"
