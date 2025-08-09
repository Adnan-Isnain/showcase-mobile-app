# Module Management Scripts (Kotlin Multiplatform)

This folder contains scripts to scaffold and manage **Kotlin Multiplatform (KMP)** modules with minimal manual edits.  
They integrate with the Makefile targets (`new`, `link`, `unlink`) and are **rollback-safe**.

---

## Scripts Overview

### 1) scripts/new-module.sh
Creates a new KMP module under `<GROUP>/<NAME>` with **Clean Architecture** folders and optional Compose support.  
It then registers the module in `settings.gradle.kts` and links it to a consumer module.

Key points:
- Auto-detect base namespace from `build.gradle.kts`, `gradle.properties`, or AndroidManifest.
- Targets: `android-only`, `ios-only`, or both.
- Generates a module `.gitignore` and a KMP `build.gradle.kts`.
- Creates folders only (no sample Kotlin files).

Usage:

    make new GROUP=features NAME=Auth

Common options (override via Make vars or pass as flags in the script if needed):
- `GROUP`  (e.g., features, core, data)
- `NAME`   (e.g., Auth, Payments)
- `DEPS`   comma-separated Gradle paths, e.g. `:core:navigation,:core:config`
- `LINK_TO` module to link from (default: auto-detected app module like `:composeApp`)
- `TARGETS` one of `android-only`, `ios-only`, `all` (default)
- `WITH_COMPOSE` true|false (default: true)
- `TYPE` library|app (default: library)

---

### 2) scripts/link-module.sh
Makes one Gradle module depend on another by injecting the line below inside the consumer’s  
`commonMain { dependencies { ... } }` block. Idempotent (skips if already linked).

    implementation(project(":to"))

Usage:

    make link FROM=:features:auth TO=:core:navigation

---

### 3) scripts/unlink-module.sh
Removes a previously added dependency line from the consumer’s Gradle file.  
Safe to run multiple times (no-op if not present).

Usage:

    make unlink FROM=:features:auth TO=:core:navigation

---

## Makefile Commands

Create a new module:

    make new GROUP=features NAME=Auth

Create Android-only:

    make new GROUP=core NAME=Logger TARGETS=android-only WITH_COMPOSE=false

Create iOS-only:

    make new GROUP=features NAME=Profile TARGETS=ios-only

Link an existing module:

    make link FROM=:features:profile TO=:core:navigation

Unlink a dependency:

    make unlink FROM=:features:profile TO=:core:navigation

Overridable Make variables:
- `GROUP`, `NAME`, `DEPS`, `LINK_TO`, `TARGETS`, `WITH_COMPOSE`, `TYPE`

---

## Generated Folder Structure (new-module.sh)

    <group>/<name>/
      .gitignore
      build.gradle.kts
      src/
        commonMain/kotlin/<base_ns>/<group>/<name>/{domain,data,presentation,di,navigation}/
        commonTest/kotlin/<base_ns>/<group>/<name>/
        androidMain/AndroidManifest.xml
        androidMain/kotlin/<base_ns>/<group>/<name>/
        androidUnitTest/kotlin/<base_ns>/<group>/<name>/
        iosMain/kotlin/<base_ns>/<group>/<name>/        (if iOS target enabled)
        iosTest/kotlin/<base_ns>/<group>/<name>/        (if iOS target enabled)

Notes:
- `<base_ns>` is auto-detected (e.g., `com.adnanisnain.showcase`). Final namespace is `<base_ns>.<group>.<name>`.

---

## Troubleshooting

1) Namespace falls back to `com.example.app`  
   Ensure the app module defines at least one of:

       android {
           namespace = "com.yourcompany.app"
           defaultConfig { applicationId = "com.yourcompany.app" }
       }

   Or set in `gradle.properties`:

       kmp.namespace=com.yourcompany.app

   Or override when calling:

       BASE_NS=com.yourcompany.app make new GROUP=features NAME=Auth

2) `KotlinSourceSet with name 'androidTest' not found`  
   KMP uses `androidUnitTest`. Prefer:

       val androidUnitTest by getting

3) `KotlinSourceSet with name 'iosMain' not found`  
   If using explicit targets `iosX64/iosArm64/iosSimulatorArm64`, you must create hierarchical sets and wire them:

       val iosMain by creating
       val iosTest by creating
       val iosX64Main by getting { dependsOn(iosMain) }
       val iosArm64Main by getting { dependsOn(iosMain) }
       val iosSimulatorArm64Main by getting { dependsOn(iosMain) }
       val iosX64Test by getting { dependsOn(iosTest) }
       val iosArm64Test by getting { dependsOn(iosTest) }
       val iosSimulatorArm64Test by getting { dependsOn(iosTest) }

   The scaffolder already generates this when iOS is enabled.

4) iOS deployment target warning (e.g., SDK 18.0 vs target 18.2)  
   Align your deployment target with the installed Xcode SDK in your app module, or update Xcode.

---

## Behavior & Safety

- **Transactional**: on failure, scripts restore `settings.gradle.kts`, restore the consumer module’s `build.gradle.kts`, and remove the new module directory.  
- **macOS/Linux friendly**: uses BSD-safe `awk/sed`.  
- **Hands-off**: no manual edits required after running the Make targets for standard scenarios.
