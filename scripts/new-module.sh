#!/usr/bin/env bash
set -euo pipefail
# -----------------------------------------------------------------------------
# KMP Module Scaffolder
# Author: (your name)
# Role: Senior Software Engineer
#
# What it does
# - Creates a new KMP feature/core module under <group>/<name>
# - Auto-detects base namespace from the repo (applicationId/namespace/manifest)
# - Generates clean-architecture folders (no sample files)
# - Registers include() in settings.gradle.kts
# - Links the new module into a target module (default :composeApp)
# - Fully transactional: rolls back files and includes if something fails
#
# Notes
# - BSD-safe (macOS): uses awk/sed variants compatible with BSD tools
# - TARGETS can be: all (default), android-only, ios-only
# - Compose is optional; falls back if plugin alias is not present
# -----------------------------------------------------------------------------

# ===== Args & defaults =====
GROUP="" ; NAME="" ; DEPS="" ; LINK_TO=""
TARGETS="" ; WITH_COMPOSE="true" ; TYPE="library" ; BASE_NS_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --group) GROUP="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --deps) DEPS="$2"; shift 2 ;;
    --link-to) LINK_TO="$2"; shift 2 ;;
    --targets) TARGETS="$2"; shift 2 ;;     # android-only | ios-only | all(default)
    --with-compose) WITH_COMPOSE="$2"; shift 2 ;;
    --type) TYPE="$2"; shift 2 ;;            # library | app
    --base-ns) BASE_NS_ARG="$2"; shift 2 ;;  # optional override of base namespace
    *) echo "Unknown arg $1"; exit 1 ;;
  esac
done

[[ -z "$GROUP" || -z "$NAME" ]] && { echo "Usage: $0 --group <features|core|...> --name <Name>"; exit 1; }

# ===== Helpers (BSD-safe) =====
lower_kebab(){ printf '%s' "$1" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]' | sed -E 's/[ _]+/-/g'; }
to_pascal(){ printf '%s' "$1" | sed -E 's/[-_ ]+/\n/g' | awk 'NF{ lw=tolower($0); printf("%s", toupper(substr(lw,1,1)) substr(lw,2)) } END{print ""}'; }
trim(){ awk '{$1=$1;print}'; }
version_of(){
  [[ -f gradle/libs.versions.toml ]] || { echo ""; return; }
  awk -v k="$1" '
    BEGIN{vsec=0}
    /^\[versions\]/{vsec=1; next}
    /^\[/ {if(vsec) exit}
    vsec==1 && $0 ~ ("^\\s*" k "\\s*=") { sub(/^[^=]*=/,""); gsub(/["[:space:]]/,""); print; exit }
  ' gradle/libs.versions.toml
}
has_plugin_alias(){ local k="$1"; [[ -f gradle/libs.versions.toml ]] && grep -E "^\s*${k}\s*=" gradle/libs.versions.toml >/dev/null 2>&1; }
has_lib(){ local d="$1"; [[ -f gradle/libs.versions.toml ]] && grep -E "^\s*${d//./-}\s*=" gradle/libs.versions.toml >/dev/null 2>&1; }

# ===== Rollback machinery =====
ROLLBACK_MSG="❌ Failed. Rolling back changes…"
MODULE_DIR_CREATED=""
SETTINGS_BAK=""
FROM_GRADLE_FILE=""
FROM_GRADLE_BAK=""

rollback() {
  echo "$ROLLBACK_MSG"
  if [[ -n "${SETTINGS_BAK}" && -f "${SETTINGS_BAK}" ]]; then
    cp -p "${SETTINGS_BAK}" settings.gradle.kts || true
    rm -f "${SETTINGS_BAK}" || true
    echo "↩︎ settings.gradle.kts restored"
  fi
  if [[ -n "${FROM_GRADLE_BAK}" && -f "${FROM_GRADLE_BAK}" && -n "${FROM_GRADLE_FILE}" ]]; then
    cp -p "${FROM_GRADLE_BAK}" "${FROM_GRADLE_FILE}" || true
    rm -f "${FROM_GRADLE_BAK}" || true
    echo "↩︎ ${FROM_GRADLE_FILE} restored"
  fi
  if [[ -n "${MODULE_DIR_CREATED}" && -d "${MODULE_DIR_CREATED}" ]]; then
    rm -rf "${MODULE_DIR_CREATED}" || true
    echo "🗑  ${MODULE_DIR_CREATED} removed"
  fi
  exit 1
}
trap rollback ERR INT

# ===== Autodetect app module =====
detect_app_module() {
  local m=""
  while IFS= read -r -d '' f; do
    if grep -q 'alias(libs.plugins.androidApplication)' "$f"; then m="$(dirname "$f")"; break; fi
  done < <(find . -maxdepth 2 -mindepth 2 -name build.gradle.kts -print0 2>/dev/null)
  [[ -z "$m" && -d "composeApp" && -f "composeApp/build.gradle.kts" ]] && m="composeApp"
  echo "${m#./}"
}
APP_MODULE="$(detect_app_module)"
[[ -z "$APP_MODULE" ]] && { echo "Cannot detect app module"; exit 1; }

# ===== Base namespace autodetect (BSD-safe, simple) =====
detect_base_ns() {
  # 1) CLI/ENV override
  if [[ -n "${BASE_NS_ARG:-}" ]]; then echo "$BASE_NS_ARG"; return; fi
  if [[ -n "${BASE_NS:-}"     ]]; then echo "$BASE_NS";     return; fi

  # 2) gradle.properties -> kmp.namespace
  if [[ -f gradle.properties ]]; then
    val=$(grep -E '^kmp\.namespace=' gradle.properties | cut -d'=' -f2- | awk '{$1=$1;print}' || true)
    if [[ -n "$val" ]]; then echo "$val"; return; fi
  fi

  # helper: get quoted value after key=
  _first_quoted_of_key() { # $1=key, $2=file
    awk -F'"' -v K="$1" '$0 ~ K"[[:space:]]*=" { print $2; exit }' "$2" 2>/dev/null
  }

  # 3) app module Gradle (prefer applicationId, else namespace)
  local appGradle="${APP_MODULE}/build.gradle.kts"
  if [[ -f "$appGradle" ]]; then
    aid=$(_first_quoted_of_key 'applicationId' "$appGradle"); if [[ -n "$aid" ]]; then echo "$aid"; return; fi
    ns=$(_first_quoted_of_key 'namespace' "$appGradle");      if [[ -n "$ns" ]]; then echo "$ns"; return; fi
  fi

  # 4) any build.gradle.kts (depth <= 4)
  while IFS= read -r -d '' f; do
    aid=$(_first_quoted_of_key 'applicationId' "$f"); if [[ -n "$aid" ]]; then echo "$aid"; return; fi
  done < <(find . -maxdepth 4 -name build.gradle.kts -print0 2>/dev/null)
  while IFS= read -r -d '' f; do
    ns=$(_first_quoted_of_key 'namespace' "$f"); if [[ -n "$ns" ]]; then echo "$ns"; return; fi
  done < <(find . -maxdepth 4 -name build.gradle.kts -print0 2>/dev/null)

  # 5) AndroidManifest (app module, then any)
  local manifest="${APP_MODULE}/src/androidMain/AndroidManifest.xml"
  if [[ -f "$manifest" ]]; then
    pkg=$(awk -F'"' '/package=/{ for(i=1;i<=NF;i++) if($(i-1) ~ /package=/){ print $i; exit } }' "$manifest")
    if [[ -n "$pkg" ]]; then echo "$pkg"; return; fi
  fi
  while IFS= read -r -d '' mf; do
    pkg=$(awk -F'"' '/package=/{ for(i=1;i<=NF;i++) if($(i-1) ~ /package=/){ print $i; exit } }' "$mf")
    if [[ -n "$pkg" ]]; then echo "$pkg"; return; fi
  done < <(find . -maxdepth 4 -name AndroidManifest.xml -print0 2>/dev/null)

  # 6) fallback
  echo "com.example.app"
}
BASE_NS="$(detect_base_ns)"

# ===== Naming =====
NAME_KBAB="$(lower_kebab "$NAME")"
CAP_NAME="$(to_pascal "$NAME")"
MODULE_DIR="${GROUP}/${NAME_KBAB}"
[[ -d "$MODULE_DIR" ]] && { echo "Module exists: $MODULE_DIR"; exit 1; }

# effective namespace & package path
EFFECTIVE_NS="${BASE_NS}.${GROUP}.${NAME_KBAB//-/.}"
PKG_PATH="$(printf '%s' "${BASE_NS}.${GROUP}.${NAME_KBAB//-/.}" | tr '.' '/')"

# targets
case "${TARGETS:-all}" in
  ""|all) TARGETS="android,ios" ;;
  android-only) TARGETS="android" ;;
  ios-only) TARGETS="ios" ;;
esac
HAS_ANDROID=0; HAS_IOS=0
case ",$TARGETS," in
  *,android,*) HAS_ANDROID=1 ;;
esac
case ",$TARGETS," in
  *,ios,*) HAS_IOS=1 ;;
esac

echo "==> Create :${GROUP}:${NAME_KBAB}"
echo "    base namespace: ${BASE_NS}"
echo "    effective ns  : ${EFFECTIVE_NS}"
echo "    app module    : :${APP_MODULE}"
echo "    targets       : ${TARGETS}"
echo "    compose       : ${WITH_COMPOSE}"
echo "    type          : ${TYPE}"

# ===== Create module root & .gitignore =====
mkdir -p "$MODULE_DIR"; MODULE_DIR_CREATED="$MODULE_DIR"
GITIGNORE_PATH="${MODULE_DIR}/.gitignore"
printf '%s\n' '/build' '/.gradle' '/local.properties' '/captures' '*.iml' '*.log' > "$GITIGNORE_PATH"
[[ -s "$GITIGNORE_PATH" ]]

# ===== Target code blocks =====
androidBlock=""
iosBlock=""
if [[ $HAS_ANDROID -eq 1 ]]; then
  androidBlock=$'    androidTarget {}\n'
fi
if [[ $HAS_IOS -eq 1 ]]; then
  iosBlock=$'    listOf(iosX64(), iosArm64(), iosSimulatorArm64()).forEach { it.binaries.framework { baseName = "feature"; isStatic = true } }\n'
fi

# ===== Deps (optional) =====
DEPS_BLOCK=""
if [[ -n "$DEPS" ]]; then
  IFS=',' read -ra ARR <<< "$DEPS"
  for d in "${ARR[@]}"; do d_trim=$(echo "$d" | awk '{$1=$1;print}'); [[ -n "$d_trim" ]] && DEPS_BLOCK+="                implementation(project(\"$d_trim\"))\n"; done
fi

# ===== Plugins =====
KMP_PLUG="alias(libs.plugins.kotlinMultiplatform)"; has_plugin_alias "kotlinMultiplatform" || KMP_PLUG='id("org.jetbrains.kotlin.multiplatform")'
if [[ "$TYPE" == "app" ]]; then
  ANDROID_PLUGIN="alias(libs.plugins.androidApplication)"; has_plugin_alias "androidApplication" || ANDROID_PLUGIN='id("com.android.application")'
else
  ANDROID_PLUGIN="alias(libs.plugins.androidLibrary)"; has_plugin_alias "androidLibrary" || ANDROID_PLUGIN='id("com.android.library")'
fi
COMPOSE_PLUG=""; COMPOSE_DEPS=""
if [[ "$WITH_COMPOSE" == "true" ]]; then
  if has_plugin_alias "composeMultiplatform"; then COMPOSE_PLUG=$'\n    alias(libs.plugins.composeMultiplatform)'; else COMPOSE_PLUG=$'\n    id("org.jetbrains.compose")'; fi
  COMPOSE_DEPS=$'                implementation(compose.runtime)\n                implementation(compose.foundation)\n                implementation(compose.material3)\n'
fi

# ===== Base libs (fallback-safe) =====
CORA_LIB="implementation(libs.kotlinx.coroutines.core)"; has_lib "kotlinx.coroutines.core" || { v="$(version_of coroutines)"; [[ -z "$v" ]] && v="1.8.1"; CORA_LIB="implementation(\"org.jetbrains.kotlinx:kotlinx-coroutines-core:${v}\")"; }
SER_LIB="implementation(libs.kotlinx.serialization.json)"; has_lib "kotlinx.serialization.json" || { v="$(version_of serialization)"; [[ -z "$v" ]] && v="1.6.3"; SER_LIB="implementation(\"org.jetbrains.kotlinx:kotlinx-serialization-json:${v}\")"; }

# ===== build.gradle.kts =====
# iOS source sets block (only when HAS_IOS=1)
IOS_SOURCESETS=""
if [[ $HAS_IOS -eq 1 ]]; then
  IOS_SOURCESETS="$(cat <<'EOS'
        // iOS hierarchical source sets (when using iosX64/iosArm64/iosSimulatorArm64)
        val iosMain by creating
        val iosTest by creating

        val iosX64Main by getting { dependsOn(iosMain) }
        val iosArm64Main by getting { dependsOn(iosMain) }
        val iosSimulatorArm64Main by getting { dependsOn(iosMain) }

        val iosX64Test by getting { dependsOn(iosTest) }
        val iosArm64Test by getting { dependsOn(iosTest) }
        val iosSimulatorArm64Test by getting { dependsOn(iosTest) }
EOS
)"
fi
cat > "${MODULE_DIR}/build.gradle.kts" <<EOF
plugins {
    ${KMP_PLUG}
    ${ANDROID_PLUGIN}${COMPOSE_PLUG}
}

kotlin {
$androidBlock$iosBlock
    sourceSets {
        val commonMain by getting {
            dependencies {
$DEPS_BLOCK$COMPOSE_DEPS
                $CORA_LIB
                $SER_LIB
            }
        }
        val commonTest by getting { dependencies { implementation(kotlin("test")) } }
$( [[ $HAS_ANDROID -eq 1 ]] && echo "        val androidMain by getting { dependencies { $( [[ "$WITH_COMPOSE" == "true" ]] && echo "implementation(compose.preview)" ) } }" )
$( [[ $HAS_ANDROID -eq 1 ]] && echo "        val androidUnitTest by getting" )
$( [[ $HAS_IOS -eq 1 ]] && echo "$IOS_SOURCESETS" )
    }
}

android {
    namespace = "${EFFECTIVE_NS}"
    compileSdk = libs.versions.android.compileSdk.get().toInt()
    defaultConfig { minSdk = libs.versions.android.minSdk.get().toInt() }
}
EOF

# ===== Skeleton folders (no sample files) =====
# common/ android/ ios/ + tests
mkdir -p "${MODULE_DIR}/src/commonMain/kotlin/${PKG_PATH}/domain" \
         "${MODULE_DIR}/src/commonMain/kotlin/${PKG_PATH}/data" \
         "${MODULE_DIR}/src/commonMain/kotlin/${PKG_PATH}/presentation" \
         "${MODULE_DIR}/src/commonMain/kotlin/${PKG_PATH}/di" \
         "${MODULE_DIR}/src/commonMain/kotlin/${PKG_PATH}/navigation" \
         "${MODULE_DIR}/src/commonTest/kotlin/${PKG_PATH}"

if [[ $HAS_ANDROID -eq 1 ]]; then
  mkdir -p "${MODULE_DIR}/src/androidMain"
  printf '<manifest package="%s"/>\n' "${EFFECTIVE_NS}" > "${MODULE_DIR}/src/androidMain/AndroidManifest.xml"
  mkdir -p "${MODULE_DIR}/src/androidMain/kotlin/${PKG_PATH}" \
           "${MODULE_DIR}/src/androidUnitTest/kotlin/${PKG_PATH}"
fi

if [[ $HAS_IOS -eq 1 ]]; then
  mkdir -p "${MODULE_DIR}/src/iosMain/kotlin/${PKG_PATH}" \
           "${MODULE_DIR}/src/iosTest/kotlin/${PKG_PATH}"
fi

# ===== Register include (backup) =====
SETTINGS="settings.gradle.kts"; [[ -f "$SETTINGS" ]] || : > "$SETTINGS"
SETTINGS_BAK="$(mktemp)"; cp -p "$SETTINGS" "$SETTINGS_BAK"
INCLUDE_LINE="include(\":${GROUP}:${NAME_KBAB}\")"
if ! grep -Fq "$INCLUDE_LINE" "$SETTINGS"; then printf '\n%s\n' "$INCLUDE_LINE" >> "$SETTINGS"; fi

# ===== Backup FROM gradle then link =====
if [[ -z "$LINK_TO" ]]; then LINK_TO=":${APP_MODULE}"; fi
FROM_PATH=$(echo "$LINK_TO" | sed 's/^://; s/:/\//g')
FROM_GRADLE_FILE="${FROM_PATH}/build.gradle.kts"
if [[ -f "$FROM_GRADLE_FILE" ]]; then FROM_GRADLE_BAK="$(mktemp)"; cp -p "$FROM_GRADLE_FILE" "$FROM_GRADLE_BAK"; fi

bash scripts/link-module.sh --from "$LINK_TO" --to ":${GROUP}:${NAME_KBAB}"

# success → clean backups
rm -f "${SETTINGS_BAK}" "${FROM_GRADLE_BAK}" 2>/dev/null || true
trap - ERR INT
echo "✅ Created :${GROUP}:${NAME_KBAB} (ns=${EFFECTIVE_NS}) and linked ${LINK_TO} -> :${GROUP}:${NAME_KBAB}"
