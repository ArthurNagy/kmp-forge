---
description: Scaffold a new Kotlin Multiplatform + Compose Multiplatform project via kmp.jetbrains.com and apply the kmp-forge opinion overlay.
---

# /kmp-forge-init

End-to-end scaffold for a new KMP+Compose project on the kmp-forge locked stack.

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

Ask for the downloaded zip path (or auto-detect the most recent `kmp-*.zip` under `~/Downloads/`):

```bash
ls -t ~/Downloads/kmp-*.zip 2>/dev/null | head -1
```

Confirm path with user. Then unzip into the target directory (typically `~/Development/Personal projects/<APP_NAME>`):

```bash
TARGET_DIR="$HOME/Development/Personal projects/<APP_NAME>"
unzip -q "<zip-path>" -d "$TARGET_DIR.tmp" \
  && mv "$TARGET_DIR.tmp"/* "$TARGET_DIR/" \
  && rmdir "$TARGET_DIR.tmp"
```

If the zip's root folder name differs from `<APP_NAME>`, normalize the directory.

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
export MODULE_LIST="- :composeApp · :ui · :domain · :data"
export FEATURE_LIST="_(none yet — add via /kmp-forge-add-feature)_"
export OPTIONAL_LIBS="<csv of opted-in libs, or '(none)'>"
export FIGMA_URL="(none)"
export PROJECT_OVERRIDES=""
export TIMELINE=""
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
```

### 6. Optional-lib post-overlay tweaks

- **Sentry**: not enabled → skip. If enabled, add `sentryDsn` slot to `AppBuildConfig` generation in `composeApp/build.gradle.kts`, document the `SENTRY_DSN` secret in `docs/observability.md`. (v0.1.0: just print a note for the user to wire manually; full integration arrives in v0.2.)
- **Firebase App Distribution**: append the firebase-android / firebase-ios jobs to `.github/workflows/release.yml` from `overlay/ci/firebase-jobs.yml.snippet` (v0.2 — for v0.1.0 just print a note).
- **gradle-play-publisher**: append `id("com.github.triplet.play") version "3.10.1"` to `composeApp/build.gradle.kts` plugins block + a Play upload step in release.yml. (v0.2 — for v0.1.0 print a note pointing to `docs/release.md` § Store tier.)

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
✓ Modules: :composeApp · :ui · :domain · :data + build-logic/
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
