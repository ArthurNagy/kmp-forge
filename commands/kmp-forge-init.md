---
description: Scaffold a new Kotlin Multiplatform + Compose Multiplatform project via kmp.jetbrains.com and apply the kmp-forge opinion overlay.
---

# /kmp-forge-init

End-to-end scaffold for a new KMP+Compose project on the kmp-forge locked stack.

## Layout (kmp.new output → kmp-forge overlay)

kmp.jetbrains.com generates a **`:shared`** Kotlin Multiplatform library (Compose UI + the
composition host — `App.kt`, `startKoin`, the Nav 3 back stack) plus thin per-platform app
modules **`:androidApp`** / **`:desktopApp`**, and, when iOS is selected, an Xcode **`iosApp/`**
project consuming the `Shared` framework. The overlay adds the locked-stack shared modules
**`:ui` · `:domain` · `:data`** (and later `:feature-*`), wires `:shared` to depend on them,
and installs `build-logic/`. `:shared` is the app's composition root; the app modules are just
platform entry points.

> Earlier kmp.new revisions emitted a single `:composeApp`; the current wizard splits it into
> `:shared` + per-platform app modules. The overlay + build-logic target the current shape:
> Kotlin 2.4 / AGP 9 (`com.android.kotlin.multiplatform.library`) / Compose MP 1.11 / Gradle 9.1,
> with build-logic as a **precompiled script plugin** (a Kotlin class plugin can't compile against
> KGP 2.4 under Gradle's embedded Kotlin 2.2).

## Flow

Execute these steps **in order**. Stop and ask if anything is unclear.

### 1. Gather project parameters

Use `AskUserQuestion` to collect the following. Do NOT skip any.

1. **App name** (e.g. `Framefit`, `Cadenza`, `MyApp`). PascalCase. No spaces.
2. **Base package** (e.g. `com.arthurnagy.myapp`). Reverse-domain. Lowercase.
3. **Platforms** (multi-select). Android is required; offer iOS, Desktop, Web.
4. **Optional libraries** (multi-select). Offer:
   - Ktor (HTTP client)
   - SQLDelight (relational DB)
   - Sentry (cross-platform crash reporting)
   - Firebase App Distribution (beta tier)
   - gradle-play-publisher (Play Store releases without fastlane)
5. **License**: MIT (default) / Apache-2.0 / Proprietary
6. **Initialize git + first commit**: yes (default) / no

If the user already provided some of these in their initial message, skip those questions.

### 2. Drive kmp.jetbrains.com

JetBrains' KMP wizard is a Next.js SPA without URL query-param support, so the plugin cannot pre-fill it. Print explicit instructions for the user by running:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/kmp-new-url.sh \
  "<APP_NAME>" "<BASE_PACKAGE>" "<PLATFORMS_CSV>" "<LIBS_CSV>"
```

Where `<LIBS_CSV>` includes only those libraries kmp.new offers (currently: `ktor`, `sqldelight`). Locked-stack libs (Orbit, Koin, Coil, Kermit, kotlinx-datetime, Navigation 3) are added by step 5's overlay — do NOT ask the user to pick them in the wizard.

Wait for the user to confirm download is complete.

### 3. Locate and unzip the download

Ask for the downloaded zip path (or auto-detect — the current wizard names it `<APP_NAME>.zip`; older builds used `kmp-*.zip`):

```bash
ls -t ~/Downloads/<APP_NAME>.zip ~/Downloads/kmp-*.zip 2>/dev/null | head -1
```

Confirm path with user. The zip contains a **single top-level folder** (the app name), so unzip
to a temp dir and lift that folder's contents into the target (handles dotfiles like `.idea`,
`.gitignore`):

```bash
TARGET_DIR="$HOME/Development/Personal projects/<APP_NAME>"
mkdir -p "$TARGET_DIR" "$TARGET_DIR.tmp"
unzip -q "<zip-path>" -d "$TARGET_DIR.tmp"
inner="$(find "$TARGET_DIR.tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"
shopt -s dotglob 2>/dev/null || setopt dotglob 2>/dev/null || true
mv "$inner"/* "$TARGET_DIR/"
rm -rf "$TARGET_DIR.tmp"
```

If scaffolding into an **existing** directory (e.g. one that already holds `docs/` + a
project `CLAUDE.md`), back up the existing `CLAUDE.md` first — the overlay renders its own —
and merge the two afterward rather than letting the overlay clobber it.

### 4. Export overlay variables

Compute and export all env vars `apply-overlay.sh` needs:

```bash
export APP_NAME="<PascalCase name>"
export APP_TAGLINE="<one-liner or empty>"
export BASE_PACKAGE="<reverse-domain>"
export BASE_PACKAGE_PATH="$(echo "$BASE_PACKAGE" | tr . /)"
export SCAFFOLD_DATE="$(date -u +%Y-%m-%d)"
export PLATFORM_LIST="$(... markdown bullet list from selected platforms ...)"
export BUILD_COMMANDS="$(... per-platform ./gradlew ... fenced code block ...)"
export MODULE_LIST="- :shared · :androidApp · :desktopApp · :ui · :domain · :data"
export FEATURE_LIST="_(none yet — add via /kmp-forge-add-feature)_"
export OPTIONAL_LIBS="<csv of opted-in libs, or '(none)'>"
export FIGMA_URL="(none)"
export PROJECT_OVERRIDES=""
export TIMELINE=""

# Non-Android KMP targets for the overlay modules (:ui/:domain/:data). These MUST match the
# targets :shared declares, so :shared can depend on them. The Android target is added per-module
# by the AGP KMP plugin, so it is NOT listed here. Always include jvm (desktop + host tests);
# add iOS / web from the platform selection. Examples:
#   android+desktop          → "jvm"
#   android+ios+desktop      → "iosArm64,iosSimulatorArm64,jvm"
#   android+ios+desktop+web  → "iosArm64,iosSimulatorArm64,jvm,wasmJs"
export KMP_TARGETS="<computed from selected platforms>"
```

### 5. Apply overlay

Run the four sub-commands in sequence:

```bash
OVERLAY="${CLAUDE_PLUGIN_ROOT}/overlay"
TARGET="<project-dir>"

# Root files (CLAUDE.md, .gitignore, .editorconfig, detekt.yml, cliff.toml)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render "$OVERLAY/root" "$TARGET"

# CI workflows (.github/workflows/pr.yml, release.yml)
mkdir -p "$TARGET/.github/workflows"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render "$OVERLAY/ci" "$TARGET/.github/workflows"

# Git templates (PR template, issue templates, gitleaks config, pre-commit hook)
mkdir -p "$TARGET/.github" "$TARGET/.github/ISSUE_TEMPLATE"
cp "$OVERLAY/git/pull_request_template.md" "$TARGET/.github/pull_request_template.md"
cp "$OVERLAY/git/ISSUE_TEMPLATE/"*.yml "$TARGET/.github/ISSUE_TEMPLATE/"
cp "$OVERLAY/git/.gitleaks.toml" "$TARGET/.gitleaks.toml"
cp "$OVERLAY/git/pre-commit-hook.sh" "$TARGET/.kmp-forge-pre-commit.sh"
chmod +x "$TARGET/.kmp-forge-pre-commit.sh"

# Product docs (MVP_SPEC.md, DECISIONS/)
mkdir -p "$TARGET/docs"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render "$OVERLAY/product" "$TARGET/docs"

# Modules (:ui, :domain, :data)
for module in ui domain data; do
    bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render-module \
        "$module" "$OVERLAY/modules/$module" "$TARGET/$module" "$BASE_PACKAGE_PATH"
done

# build-logic (always — per locked decision)
mkdir -p "$TARGET/build-logic"
cp -R "$OVERLAY/build-logic/." "$TARGET/build-logic/"

# Patch settings.gradle.kts to include the new modules
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-settings "$TARGET" "ui,domain,data"

# Patch settings.gradle.kts to includeBuild("build-logic").
# kmp.new ships a pluginManagement { ... } block; use the Edit tool to insert
# `includeBuild("build-logic")` as the first line inside that block. Idempotent —
# skip if already present.
#
# Example before:
#   pluginManagement {
#       repositories { ... }
#   }
# After:
#   pluginManagement {
#       includeBuild("build-logic")
#       repositories { ... }
#   }
#
# If pluginManagement block is absent (rare), prepend it at the top of the file:
#   pluginManagement { includeBuild("build-logic") }

# Merge libs.versions.toml additions
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-libs \
    "$TARGET" "$OVERLAY/gradle/libs.versions.toml.additions.tmpl"

# Pin the overlay modules' non-Android targets to match :shared (Gradle property read by the
# build-logic convention). Without this they default to iosArm64,iosSimulatorArm64,jvm.
printf '\nkmpForge.targets=%s\n' "$KMP_TARGETS" >> "$TARGET/gradle.properties"
```

Then wire **`:shared`** (the composition host) to the new modules. Use the Edit tool to add to
`shared/build.gradle.kts` inside `kotlin { sourceSets { commonMain.dependencies { … } } }`:

```kotlin
implementation(projects.ui)
implementation(projects.domain)
implementation(projects.data)
// composition deps :shared needs to host App.kt + startKoin + the Nav 3 back stack:
implementation(libs.koin.core)
implementation(libs.koin.compose)
implementation(libs.koin.compose.viewmodel)
implementation(libs.androidx.navigation3.runtime)
implementation(libs.androidx.navigation3.ui)
```

(`:feature-*` modules are added later by `/kmp-forge-add-feature`, which also wires each into
`:shared`'s deps and the `NavDisplay` entry list.) `apply-overlay.sh patch-settings` already
guarantees a trailing newline before appending `include(...)` lines, so the kmp.new
`settings.gradle.kts` (which ships without one) won't get a concatenated `include`.

### 6. Optional-lib post-overlay tweaks

- **Sentry**: not enabled → skip. If enabled, add the `sentryDsn` slot to `AppBuildConfig` generation in `shared/build.gradle.kts` (the composition host owns `AppBuildConfig`), document the `SENTRY_DSN` secret in `docs/observability.md`. (v0.1.0: just print a note for the user to wire manually; full integration arrives in v0.2.)
- **Firebase App Distribution**: append the firebase-android / firebase-ios jobs to `.github/workflows/release.yml` from `overlay/ci/firebase-jobs.yml.snippet` (v0.2 — for v0.1.0 just print a note).
- **gradle-play-publisher**: append `id("com.github.triplet.play") version "3.10.1"` to `androidApp/build.gradle.kts` plugins block (the Android application module) + a Play upload step in release.yml. (v0.2 — for v0.1.0 print a note pointing to `docs/release.md` § Store tier.)

For v0.1.0: just print which opt-in libs were selected and remind the user to follow the docs to wire them in.

### 7. License

If user picked Apache-2.0, replace the `LICENSE` text (currently MIT from kmp.new's default if any) accordingly. If Proprietary, write a short proprietary notice.

### 8. Git init + first commit + optional GitHub repo

If user opted in to git init:

```bash
cd "$TARGET"
git init -q -b main
# Install gitleaks pre-commit hook
mkdir -p .git/hooks
cp .kmp-forge-pre-commit.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
git add -A
git commit -q -m "chore: scaffold project via kmp-forge"
```

Then ask via `AskUserQuestion` whether to **create the GitHub repo now**. Default: yes, private. If yes:

```bash
gh repo create "<APP_NAME>" --private --source=. --remote=origin
git push -u origin main
```

If `gh` is not authenticated, surface `gh auth login` instructions to the user instead of failing. Never push to a public repo by default — visibility flips require explicit user opt-in.

If user declines: print the manual command for them to run later (`gh repo create ... --private --source=. --remote=origin && git push -u origin main`).

### 9. Report next steps

Print a checklist of what the user should do next:

```
✓ Project scaffolded at <path>
✓ Modules: :shared · :androidApp · :desktopApp · :ui · :domain · :data + build-logic/
✓ CI workflows: .github/workflows/pr.yml + release.yml
✓ Product docs: docs/MVP_SPEC.md + docs/DECISIONS/{0001..0006}.md
✓ CLAUDE.md generated

Next:
  1. cd "<path>" && ./gradlew build              # verify build
  2. Open in Android Studio / IntelliJ
  3. Push to GitHub:
       gh repo create <name> --private --source=. --remote=origin
       git push -u origin main
  4. Enable branch protection on main (see docs/git-conventions.md)
  5. Run /kmp-forge-spec to fill out docs/MVP_SPEC.md
  6. Run /kmp-forge-add-feature <name> to add your first feature module

Opt-in libraries you selected: <list>
  Wiring them up: see https://github.com/arthurnagy/kmp-forge/blob/main/docs/stack.md#opt-in-libraries
```

## Notes

- The plugin does NOT push to GitHub. The user opts into that themselves.
- The plugin does NOT enable branch protection. Same reason.
- Always quote paths with spaces (`"$TARGET"`) — the user's Personal projects directory has a space.
- If `apply-overlay.sh` errors, surface the error verbatim and stop — do NOT try to clean up partially-applied overlay (let the user inspect).
