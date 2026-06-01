---
description: Add a platform (desktop, web, or ios) to an existing kmp-forge project.
argument-hint: <desktop|web|ios>
---

# /kmp-forge-add-platform

Adds a previously-disabled platform to an existing project.

## Arguments

- **`<platform>`**: one of `desktop`, `web`, `ios`

## Flow

### 1. Verify platform is not already enabled

Read `build-logic/src/main/kotlin/convention/KmpLibraryConventionPlugin.kt` or `composeApp/build.gradle.kts` to detect which targets are declared. If the requested platform is already present, surface a no-op message and exit.

### 2. Update convention plugin target list

The default convention plugin reads `kmpForge.targets` project property. Two options:

- **Easiest**: set the project property in `gradle.properties`:
  ```properties
  kmpForge.targets=android,iosArm64,iosSimulatorArm64,jvm,js,wasmJs
  ```
- **Or**: edit `KmpLibraryConventionPlugin.kt` to default to the new target set.

### 3. For `desktop`:

- Add Desktop entry point to `composeApp`:
  - `composeApp/src/jvmMain/kotlin/.../main.kt` — `fun main() = application { Window(...) }`
- Add Compose Desktop plugin block to `composeApp/build.gradle.kts`:
  ```kotlin
  compose.desktop {
      application {
          mainClass = "<BASE_PACKAGE>.MainKt"
          nativeDistributions {
              targetFormats(TargetFormat.Dmg, TargetFormat.Msi, TargetFormat.Deb)
              packageName = "<APP_NAME>"
          }
      }
  }
  ```
- Update CLAUDE.md `Platforms` and `Build & Run` sections.

### 4. For `web`:

- Add JS + Wasm entry points to `composeApp`:
  - `composeApp/src/jsMain/kotlin/main.kt` and `composeApp/src/wasmJsMain/kotlin/main.kt`
- Both invoke `ComposeViewport(document.body!!) { App() }`.
- Update CLAUDE.md.

### 5. For `ios`:

- Add iOS targets to convention plugin (`iosArm64`, `iosSimulatorArm64`).
- Verify `composeApp/build.gradle.kts` exports the framework:
  ```kotlin
  iosTargets.forEach {
      it.binaries.framework { baseName = "ComposeApp"; isStatic = true }
  }
  ```
- Scaffold `iosApp/` (Xcode project skeleton) — copy from `overlay/modules/iosApp/` (TBD: ship this in v0.2 — for v0.1.0, instruct user to follow https://github.com/arthurnagy/kmp-forge/blob/main/docs/ios-troubleshooting.md and use JetBrains' [KMP Wizard](https://kmp.jetbrains.com/) just for the iOS scaffold).
- Add `build-ios` job to `.github/workflows/pr.yml` and `release.yml` (already gated by `${{ vars.IOS_ENABLED == 'true' }}` — the user must set the `IOS_ENABLED` repo variable to `true`).
- Update CLAUDE.md.

### 6. Verify the build

`./gradlew build` from project root.

### 7. Report

What changed, what the user still needs to do (CI variable, App Store registration, etc).
