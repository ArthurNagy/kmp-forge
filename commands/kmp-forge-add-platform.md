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

Read `build-logic/src/main/kotlin/convention/KmpLibraryConventionPlugin.kt` or `shared/build.gradle.kts` to detect which targets are declared (`:shared` is the KMP library that holds the Compose UI + composition host and produces the iOS framework). Android and desktop already ship as the thin `:androidApp` and `:desktopApp` modules that depend on `:shared`. If the requested platform is already present, surface a no-op message and exit.

### 2. Update convention plugin target list

The default convention plugin reads `kmpForge.targets` project property. Two options:

- **Easiest**: set the project property in `gradle.properties`:
  ```properties
  kmpForge.targets=android,iosArm64,iosSimulatorArm64,jvm,js,wasmJs
  ```
- **Or**: edit `KmpLibraryConventionPlugin.kt` to default to the new target set.

### 3. For `desktop`:

Desktop ships as a thin `:desktopApp` JVM application that depends on `:shared` (which holds `App()`). If `:desktopApp` doesn't exist yet, scaffold it and add it to `settings.gradle.kts`.

- Add the Desktop entry point to `:desktopApp`:
  - `desktopApp/src/jvmMain/kotlin/.../main.kt` — `fun main() = application { Window(...) { App() } }` (calling `App()` from `:shared`)
- Ensure `:desktopApp` depends on `:shared` and add the Compose Desktop plugin block to `desktopApp/build.gradle.kts`:
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

Web (js + wasmJs) targets are added to `:shared` — the Compose UI library that owns `App()`.

- Add the `js` + `wasmJs` browser targets to `shared/build.gradle.kts` (and to the convention plugin's target list per step 2).
- Add JS + Wasm entry points to `:shared`:
  - `shared/src/jsMain/kotlin/main.kt` and `shared/src/wasmJsMain/kotlin/main.kt`
- Both invoke `ComposeViewport(document.body!!) { App() }`.
- Update CLAUDE.md.

### 5. For `ios`:

- Add iOS targets to convention plugin (`iosArm64`, `iosSimulatorArm64`).
- Verify `shared/build.gradle.kts` exports the framework with baseName `Shared` (the `:shared` library produces the iOS framework that `iosApp/` consumes):
  ```kotlin
  iosTargets.forEach {
      it.binaries.framework { baseName = "Shared"; isStatic = true }
  }
  ```
- Scaffold `iosApp/` (Xcode project skeleton consuming the `Shared` framework) — copy from `overlay/modules/iosApp/` (TBD: ship this in v0.2 — for v0.1.0, instruct user to follow https://github.com/arthurnagy/kmp-forge/blob/main/docs/ios-troubleshooting.md and use JetBrains' [KMP Wizard](https://kmp.jetbrains.com/) just for the iOS scaffold).
- Add `build-ios` job to `.github/workflows/pr.yml` and `release.yml` (already gated by `${{ vars.IOS_ENABLED == 'true' }}` — the user must set the `IOS_ENABLED` repo variable to `true`).
- Update CLAUDE.md.

### 6. Verify the build

`./gradlew build` from project root.

### 7. Report

What changed, what the user still needs to do (CI variable, App Store registration, etc).
