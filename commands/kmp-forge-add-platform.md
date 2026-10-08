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

Read `gradle.properties` → `kmpForge.targets` (the non-Android targets every overlay module
builds — read by `build-logic/src/main/kotlin/kmp-forge.kmp.library.gradle.kts`) and
`shared/build.gradle.kts` (`iosArm64()`/`jvm()`/`js { }`/`wasmJs { }`). Android always exists. If
the requested platform is already present, surface a no-op message and exit.

### 2. Get a reference project from kmp.new

The wizard's generator can be called directly, so instead of hand-writing app modules, download
a throwaway project with the **same name and package** plus the new platform, and copy that
platform's pieces from it (`<CURRENT_PLATFORMS>` = what the project has today, e.g. `ios`):

```bash
REF="$(mktemp -d)/ref"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/kmp-new.sh" download \
  "<APP_NAME>" "<BASE_PACKAGE>" "<CURRENT_PLATFORMS>,<platform>" "$REF"
```

(`APP_NAME` = `rootProject.name` in `settings.gradle.kts`; `BASE_PACKAGE` from CLAUDE.md. If the
download fails with exit 2, `kmp-new.sh url …` prints the wizard URL for a manual download.)

### 3. Update the target lists

- `gradle.properties` → `kmpForge.targets` (comma-separated, non-Android only):
  `iosArm64,iosSimulatorArm64` for ios, `jvm` for desktop (always present already — host tests),
  `js,wasmJs` for web (kmp.new's `:shared` declares **both**).
- `shared/build.gradle.kts` → copy the new target block(s) from `$REF/shared/build.gradle.kts`
  (`iosArm64()`/`iosSimulatorArm64()` + `binaries.framework { baseName = "Shared"; isStatic = true }`,
  `jvm()`, or `js { browser(); binaries.executable() }` + `wasmJs { … }` with its `@OptIn`) and any
  target-specific dependencies (`jsMain` → `libs.wrappers.browser`, …). Merge new catalog entries
  from `$REF/gradle/libs.versions.toml` that the reference uses but the project lacks.

### 4. Copy the platform's app module

| Platform | Copy from `$REF` | Also |
|---|---|---|
| `desktop` | `desktopApp/` | `include(":desktopApp")`; entry point `main()` renders `:shared`'s `App()` |
| `web` | `webApp/` | `include(":webApp")`; `webMain/kotlin/main.kt` → `ComposeViewport { App() }`; `apply-overlay.sh pin-toolchain . --web` (Kotlin daemon heap for the js/wasm executables) |
| `ios` | `iosApp/` (Xcode project consuming the `Shared` framework) + `shared/src/iosMain/…/MainViewController.kt` | `apply-overlay.sh pin-toolchain . --ios` (daemon heap for framework links) |

Use `apply-overlay.sh patch-settings` for the `include(...)` line. Never overwrite an existing
file — diff and merge instead.

**Web caveats** (also in docs/stack.md): DataStore has no `js` target yet — remove
`libs.androidx.datastore.*` from `data/build.gradle.kts`' `commonMain` (put preferences behind a
`:domain` interface with a `webMain` implementation); with Ktor, add
`webMain.dependencies { implementation(libs.ktor.client.js) }` to `:data`; SQLDelight on web needs
the web-worker driver and is not wired automatically.

**iOS extras:** add the iOS engine/driver to `:data` if the project uses Ktor
(`iosMain → libs.ktor.client.darwin`) or SQLDelight (`iosMain → libs.sqldelight.native.driver`).

### 5. CI

- `ios`: `.github/workflows/pr.yml` + `release.yml` already have jobs gated by
  `${{ vars.IOS_ENABLED == 'true' }}` — tell the user to set the `IOS_ENABLED` repository variable.
- `desktop`: `release.yml`'s desktop job is gated by `vars.DESKTOP_ENABLED`.

### 6. Verify the build

```bash
./gradlew build
```

### 7. Report

What changed (targets, copied module, catalog entries), CLAUDE.md `Platforms` / `Build & Run`
updates, and what the user still has to do (CI variable, signing / App Store registration, …).
Delete `$REF`.
