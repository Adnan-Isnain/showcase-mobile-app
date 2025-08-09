# 📱 Kotlin Multiplatform Showcase App

This is a **Kotlin Multiplatform (KMP)** project targeting **Android** and **iOS**, using **Compose Multiplatform** for shared UI.

---

## 📂 Project Structure

- **[`/composeApp`](./composeApp/src)**  
  Shared code for all Compose Multiplatform applications.  
  - `commonMain/` → Code shared across all targets (Android, iOS, etc.).  
  - `androidMain/`, `iosMain/`, etc. → Platform-specific implementations.  
    - Example: Use `iosMain` for Apple’s CoreCrypto APIs or Swift interop.  
    - Example: Use `androidMain` for Android-specific APIs.  

- **[`/iosApp`](./iosApp/iosApp)**  
  Native iOS application entry point.  
  - Required even if UI is fully shared via Compose Multiplatform.  
  - Add SwiftUI or platform-specific code here.

- **`/features`, `/core`, `/data`, ...**  
  Modularized KMP source sets generated with the provided tooling (`make new`, `make link`, etc.).  
  See [`scripts/`](./scripts) for details.

---

## 🛠 Development Workflow

This repository is designed for **feature-based modularization**:
- Use `make new` to scaffold a new KMP module.
- Use `make link` / `make unlink` to manage dependencies between modules.
- Shared namespace is auto-detected from `gradle.properties` or `build.gradle.kts`.

---

## 📚 Learn More

- [Kotlin Multiplatform Docs](https://www.jetbrains.com/help/kotlin-multiplatform-dev/get-started.html)  
- [Compose Multiplatform Docs](https://www.jetbrains.com/lp/compose-multiplatform/)  

---
