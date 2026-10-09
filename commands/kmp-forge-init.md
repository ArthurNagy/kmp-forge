---
description: Scaffold a new Kotlin Multiplatform + Compose Multiplatform project via kmp.jetbrains.com and apply the kmp-forge opinion overlay.
---

# /kmp-forge-init

End-to-end scaffold for a new KMP+Compose project on the kmp-forge locked stack.

## Layout (kmp.new output → kmp-forge overlay)

kmp.jetbrains.com generates a **`:shared`** Kotlin Multiplatform library (Compose UI with a
sample `App()` composable) plus thin per-platform app modules **`:androidApp`** /
**`:desktopApp`** / **`:webApp`**, and, when iOS is selected, an Xcode **`iosApp/`** project
consuming the `Shared` framework. Every entry point just renders `App()`. The wizard does **not**
generate any DI or navigation — the overlay supplies them: it adds the locked-stack shared modules
**`:ui` · `:domain` · `:data`** (and later `:feature-*`), installs `build-logic/`, and replaces the
sample `App.kt` with the kmp-forge **composition root** from `overlay/shared/` (`App.kt` starts
Koin, `AppModules.kt` lists the Koin modules, `AppNavigation.kt` owns the Nav 3 back stack,
`Home.kt` is a placeholder start destination). `:shared` is the app's composition root; the app
modules are just platform entry points.

> Earlier kmp.new revisions emitted a single `:composeApp`; the current wizard splits it into
> `:shared` + per-platform app modules. The overlay + build-logic target the current shape:
> Kotlin 2.4 / AGP ≥ 9.4.1 (`com.android.kotlin.multiplatform.library`) / Compose MP 1.12 / Gradle ≥ 9.8.1
> (kmp.new still ships older AGP/Gradle pins — step 5's `pin-toolchain` raises them),
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
7. **Spec workflow**: **OpenSpec (Recommended)** — spec-driven changes (`/opsx:propose` →
   `/opsx:apply`) with kmp-forge's project rules, the `spec-link` CI check, and the path the
   autonomous build loop runs on / **Plain docs** — `docs/MVP_SPEC.md` + ADRs only (OpenSpec can be
   added later). Either way, GitHub issues labeled `ready` are the backlog.

If the user already provided some of these in their initial message, skip those questions.

### 1b. OpenSpec CLI (OpenSpec chosen)

kmp-forge's project rules (`openspec/config.yaml` with `context` / `rules` / `operations`) need
**OpenSpec ≥ 1.14** (Node ≥ 20.19 for the npm install):

```bash
v="$(openspec --version 2>/dev/null || true)"
if [[ -n "$v" && "$(printf '%s\n' 1.14.0 "$v" | sort -V | head -1)" == 1.14.0 ]]; then
    echo "✓ openspec $v"
else
    echo "✗ openspec >= 1.14 needed (found: ${v:-none})"
fi
```

If it is missing or older, ask via `AskUserQuestion` whether to install/upgrade it now —
`brew install openspec` / `brew upgrade openspec` (Homebrew), or
`npm install -g @fission-ai/openspec@latest` — or to continue with **Plain docs**. Never install
without that answer.

### 2. Download the project from kmp.jetbrains.com

The wizard's form is a plain GET to its generator endpoint, so the plugin downloads the project
directly — no browser step. Every target uses Compose Multiplatform UI and tests are included:

```bash
TARGET="$HOME/Development/Personal projects/<APP_NAME>"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/kmp-new.sh" download \
  "<APP_NAME>" "<BASE_PACKAGE>" "<PLATFORMS_CSV>" "$TARGET"
```

`<PLATFORMS_CSV>` is the selection from step 1 (`ios,desktop,web`; android is implied). The
wizard **no longer offers libraries** — Ktor / SQLDelight (and every locked-stack lib) are wired
by this command in steps 5–6, never in the wizard.

If `$TARGET` already exists and is **not empty** (e.g. it holds `docs/` + a project `CLAUDE.md`),
download into an empty sibling instead (`"$TARGET.kmpnew"`), then move its contents in without
clobbering (`cp -Rn "$TARGET.kmpnew/." "$TARGET/" && rm -rf "$TARGET.kmpnew"`), back up the
existing `CLAUDE.md` — the overlay renders its own — and merge the two afterward.

### 3. Fallback: manual download

Only if step 2 exits with code 2 (generator unreachable or changed). Print the wizard URL with the
targets pre-selected — the page reads them from URL parameters; project **name and ID are not URL
parameters**, so tell the user to type `<APP_NAME>` and `<BASE_PACKAGE>` into the form:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/kmp-new.sh" url "<PLATFORMS_CSV>"
```

Wait for the user to confirm the download, locate the zip (`ls -t ~/Downloads/<APP_NAME>.zip
2>/dev/null | head -1`), confirm the path, then unzip into a fresh temp dir and lift the single
top-level folder's contents (dotfiles included) into `$TARGET`:

```bash
tmp="$(mktemp -d)"
unzip -q "<zip-path>" -d "$tmp"
inner="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"
mkdir -p "$TARGET"
(shopt -s dotglob && mv "$inner"/* "$TARGET/")
rm -rf "$tmp"
```

### 4. Export overlay variables

**Shell state does not persist between Bash tool calls.** Write the variables to an env file once
and `source` it at the top of every later Bash block (steps 5–8), so no step ever renders with an
empty `BASE_PACKAGE` or runs `cd ""`:

```bash
export TARGET="$HOME/Development/Personal projects/<APP_NAME>"
export APP_NAME="<PascalCase name>"
# Compose resources generate :shared's Res class into "<lowercase root project name>.shared.generated.resources";
# kmp.new sets rootProject.name = APP_NAME, so Home.kt imports it via this variable.
export APP_NAME_LOWER="$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')"
export APP_TAGLINE='<one-liner or empty>'
export BASE_PACKAGE="<reverse-domain>"
export BASE_PACKAGE_PATH="$(echo "$BASE_PACKAGE" | tr . /)"
export SCAFFOLD_DATE="$(date -u +%Y-%m-%d)"
export PLATFORM_LIST='<markdown bullet list from selected platforms>'
export BUILD_COMMANDS='<per-platform ./gradlew … fenced code block>'   # single quotes: backticks stay literal
export MODULE_LIST="- :shared · :androidApp · :desktopApp · :ui · :domain · :data · :testing"
export FEATURE_LIST="_(none yet — add via /kmp-forge-add-feature)_"
export OPTIONAL_LIBS="<csv of opted-in libs, or '(none)'>"
export FIGMA_URL="(none)"
export PROJECT_OVERRIDES=""
export TIMELINE=""
export USE_OPENSPEC="<yes|no — from step 1 question 7>"
# The CLAUDE.md "Work & spec workflow" section. Single quotes keep the backticks literal.
if [[ "$USE_OPENSPEC" == yes ]]; then
export SPEC_WORKFLOW='Work starts as a GitHub issue (forms in `.github/ISSUE_TEMPLATE/`). Open issues labeled `ready`
are the backlog, ordered `priority:high` → unlabeled → `priority:low`. **Only a human applies
`ready`**: Claude may file and refine issues (`/kmp-forge-refine`) but never approves them.

Behavior changes go through OpenSpec: `/opsx:propose` (naming the issue: `Issue: #<n>`) →
optionally the `kmp-spec-critic` agent → `/opsx:apply` → a PR whose body says `Fixes #<n>` →
`/opsx:archive` once merged. `openspec/specs/` records what the app does today;
`openspec/config.yaml` holds the spec rules for this project. Direct edits are for non-behavioral
work only (docs, chores, behavior-neutral refactors). The `spec-link` CI check fails a `feat:` PR
that changes production code without an OpenSpec change; the `no-spec` label is the deliberate
escape hatch.'
else
export SPEC_WORKFLOW='Plain docs (OpenSpec not installed): product scope in `docs/MVP_SPEC.md`, decisions in
`docs/DECISIONS/`. Work is tracked as GitHub issues; open issues labeled `ready` are the backlog,
and only a human applies `ready`. Opt into spec-driven changes later (`openspec init --tools claude`
plus the kmp-forge rules): see product-workflow.md § OpenSpec.'
fi
# Non-Android KMP targets for the overlay modules. These MUST match the targets :shared declares,
# so :shared can depend on them. The Android target is added per-module by the AGP KMP plugin, so
# it is NOT listed here. Always include jvm (desktop + host tests); add iOS / web from the
# selection — web means BOTH js and wasmJs (kmp.new's :shared declares both):
#   android+desktop          → jvm
#   android+ios              → iosArm64,iosSimulatorArm64,jvm
#   android+ios+desktop+web  → iosArm64,iosSimulatorArm64,jvm,js,wasmJs
export KMP_TARGETS="<computed from selected platforms>"

# Persist for later Bash calls (typeset -p quotes every value safely, in bash and zsh alike).
typeset -p TARGET APP_NAME APP_NAME_LOWER APP_TAGLINE BASE_PACKAGE BASE_PACKAGE_PATH \
    SCAFFOLD_DATE PLATFORM_LIST BUILD_COMMANDS MODULE_LIST FEATURE_LIST OPTIONAL_LIBS \
    FIGMA_URL PROJECT_OVERRIDES TIMELINE KMP_TARGETS USE_OPENSPEC SPEC_WORKFLOW \
    > "${TMPDIR:-/tmp}/kmp-forge-init.env"
```

Every later Bash block starts with:

```bash
source "${TMPDIR:-/tmp}/kmp-forge-init.env"
: "${TARGET:?}" "${APP_NAME:?}" "${BASE_PACKAGE:?}" "${BASE_PACKAGE_PATH:?}" "${KMP_TARGETS:?}"
```

(`apply-overlay.sh render-module` also refuses to run with an empty `BASE_PACKAGE`.)

### 5. Apply overlay

Run the sub-commands in sequence (one Bash call; start it with the `source` line from step 4):

```bash
source "${TMPDIR:-/tmp}/kmp-forge-init.env"
: "${TARGET:?}" "${APP_NAME:?}" "${BASE_PACKAGE:?}" "${BASE_PACKAGE_PATH:?}" "${KMP_TARGETS:?}"
OVERLAY="${CLAUDE_PLUGIN_ROOT}/overlay"

# Root files (CLAUDE.md, .gitignore, .editorconfig, detekt.yml, cliff.toml)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render "$OVERLAY/root" "$TARGET"

# CI workflows (.github/workflows/pr.yml, release.yml, spec-link.yml — the latter skips itself
# in projects without openspec/)
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

# OpenSpec (if chosen): openspec/{specs,changes}/ + the /opsx:* commands and skills under .claude/,
# then kmp-forge's project rules replace the generated openspec/config.yaml stub.
if [[ "$USE_OPENSPEC" == yes ]]; then
    openspec init --tools claude --no-animation "$TARGET"
    bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render "$OVERLAY/openspec" "$TARGET/openspec"
    ls "$TARGET/.claude/commands/opsx/propose.md" "$TARGET/.claude/commands/opsx/apply.md" >/dev/null \
        || echo "✗ /opsx:* commands missing — openspec init did not set up Claude Code"
fi

# Modules (:ui, :domain, :data) + :testing (shared test doubles — TestDispatcherProvider; only
# ever a commonTest dependency)
for module in ui domain data testing; do
    bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render-module \
        "$module" "$OVERLAY/modules/$module" "$TARGET/$module" "$BASE_PACKAGE_PATH"
done

# Composition root into :shared (App.kt, AppModules.kt, AppNavigation.kt, Home.kt +
# composeResources/values/strings.xml). The empty module name puts the files directly in the
# base package, next to kmp.new's App.kt — which this intentionally REPLACES (the wizard's
# sample screen; every platform entry point keeps calling App()).
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render-module \
    "" "$OVERLAY/shared" "$TARGET/shared" "$BASE_PACKAGE_PATH"

# build-logic (always — per locked decision)
mkdir -p "$TARGET/build-logic"
cp -R "$OVERLAY/build-logic/." "$TARGET/build-logic/"

# Patch settings.gradle.kts to include the new modules
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-settings "$TARGET" "ui,domain,data,testing"

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

# Root build.gradle.kts: use the Edit tool to add, as the first line inside kmp.new's
# `plugins { … }` block:
#   id("kmp-forge.root")
# The root convention (build-logic/…/kmp-forge.root.gradle.kts) owns the Kover gate — it
# aggregates every module that applies kmp-forge.kmp.library (except :testing) and fails
# `koverVerify` below 75% line coverage — and it loads build-logic (with the Spotless/Detekt/Kover
# plugins it bundles) once, in the root classloader. Without that each module loads its own copy
# and Spotless 8's shared build service fails configuration ("Cannot set the value of task
# ':ui:spotlessKotlin' property 'taskService'").

# Merge libs.versions.toml additions
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-libs \
    "$TARGET" "$OVERLAY/gradle/libs.versions.toml.additions.tmpl"

# Toolchain floor: AGP >= 9.4.1 and Gradle >= 9.8.1 (kmp.new still ships older pins; never
# downgrades). --ios / --web also raise the build heaps (kmp.new's defaults run out on a clean
# build with the locked stack): --ios → org.gradle.jvmargs -Xmx6144M (Kotlin/Native links the
# frameworks in the Gradle daemon); --web → also kotlin.daemon.jvmargs -Xmx6144M (the js/wasmJs
# Compose executables compile in the Kotlin daemon).
IOS_FLAG=""; WEB_FLAG=""
[[ "$KMP_TARGETS" == *ios* ]] && IOS_FLAG="--ios"
[[ "$KMP_TARGETS" == *wasmJs* ]] && WEB_FLAG="--web"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" pin-toolchain "$TARGET" \
    ${IOS_FLAG:+"$IOS_FLAG"} ${WEB_FLAG:+"$WEB_FLAG"}

# Pin the overlay modules' non-Android targets to match :shared (Gradle property read by the
# build-logic convention). Without this they default to iosArm64,iosSimulatorArm64,jvm.
printf '\nkmpForge.targets=%s\n' "$KMP_TARGETS" >> "$TARGET/gradle.properties"
```

**Web selected?** DataStore has no `js` variant yet (1.2.x ships wasmJs only; js first appears in
1.3.0 pre-releases), and the overlay's `:data` declares it in `commonMain`. With the Edit tool,
remove `implementation(libs.androidx.datastore.core)` and
`implementation(libs.androidx.datastore.preferences.core)` from `data/build.gradle.kts`'
`commonMain.dependencies` (nothing in the overlay uses them yet). For preferences on web, add a
`webMain` implementation (e.g. `localStorage`) behind a `:domain` interface — see docs/stack.md.

Then wire **`:shared`** (the composition root) with the Edit tool, in `shared/build.gradle.kts`:

1. `plugins { … }` — add `alias(libs.plugins.kotlinx.serialization)` (the Nav 3 routes are `@Serializable`).
2. `kotlin { sourceSets { commonMain.dependencies { … } } }` — add:

```kotlin
implementation(project(":ui"))
implementation(project(":domain"))
implementation(project(":data"))
// composition root (App.kt / AppModules.kt / AppNavigation.kt):
implementation(libs.koin.core)
implementation(libs.koin.compose)
implementation(libs.koin.compose.viewmodel)
implementation(libs.androidx.navigation3.ui)   // JetBrains Nav 3 port — re-exports navigation3-runtime
implementation(libs.androidx.lifecycle.viewmodel.navigation3)
implementation(libs.kotlinx.serialization.json)
```

Use `project(":x")`, not `projects.x`: type-safe project accessors need
`enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")`, which current kmp.new output no longer sets.

(`:feature-*` modules are added later by `/kmp-forge-add-feature`, which wires each into
`:shared`'s deps plus the `// kmp-forge:` markers in `AppModules.kt` and `AppNavigation.kt`.)
`apply-overlay.sh patch-settings` already guarantees a trailing newline before appending
`include(...)` lines, so the kmp.new `settings.gradle.kts` (which ships without one) won't get a
concatenated `include`.

### 6. Optional libraries

kmp.new no longer has a library picker, so kmp-forge wires the opt-ins itself, into `:data` (the
only module allowed to talk to the network / disk). The catalog entries already exist (step 5's
`patch-libs`). Use the Edit tool on `data/build.gradle.kts`; add source-set blocks only for the
targets the project has (`jvmMain` always; `iosMain` with iOS; `webMain` with web).

- **Ktor** (HTTP client):
  ```bash
  source "${TMPDIR:-/tmp}/kmp-forge-init.env"; : "${TARGET:?}" "${BASE_PACKAGE_PATH:?}"
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render-module \
      data "${CLAUDE_PLUGIN_ROOT}/overlay/optional/ktor" "$TARGET/data" "$BASE_PACKAGE_PATH"
  ```
  ```kotlin
  // data/build.gradle.kts → kotlin { sourceSets { … } }
  commonMain.dependencies {
      implementation(libs.ktor.client.core)
      implementation(libs.ktor.client.content.negotiation)
      implementation(libs.ktor.serialization.kotlinx.json)
  }
  androidMain.dependencies { implementation(libs.ktor.client.okhttp) }
  jvmMain.dependencies { implementation(libs.ktor.client.okhttp) }
  iosMain.dependencies { implementation(libs.ktor.client.darwin) }   // iOS only
  webMain.dependencies { implementation(libs.ktor.client.js) }       // web only
  ```
  and in `dataModule.kt`, bind the client inside `module { … }`: `single { createHttpClient() }`.
- **SQLDelight** (relational DB):
  ```kotlin
  // data/build.gradle.kts
  plugins { …; alias(libs.plugins.sqldelight) }
  kotlin { sourceSets {
      commonMain.dependencies {
          implementation(libs.sqldelight.runtime)
          implementation(libs.sqldelight.coroutines)
      }
      androidMain.dependencies { implementation(libs.sqldelight.android.driver) }
      jvmMain.dependencies { implementation(libs.sqldelight.sqlite.driver) }
      iosMain.dependencies { implementation(libs.sqldelight.native.driver) }   // iOS only
  } }
  sqldelight {
      databases {
          create("AppDatabase") {
              packageName.set("<BASE_PACKAGE>.data.db")
          }
      }
  }
  ```
  Schema files go in `data/src/commonMain/sqldelight/<base-pkg-path>/data/db/*.sq`. The platform
  `SqlDriver` factory (Android needs a `Context`) is app code — see docs/stack.md § SQLDelight.
  **Web:** SQLDelight's web driver needs a worker plus `sql.js` npm packages; it is not wired
  automatically — tell the user and point at the SQLDelight web-worker-driver docs.
- **Sentry / Firebase App Distribution / gradle-play-publisher**: not wired automatically yet —
  print which were selected and point to docs/observability.md (Sentry: `SENTRY_DSN` secret, the
  `:shared` composition root owns the init) and docs/release.md § Store tier.

### 7. License

If user picked Apache-2.0, replace the `LICENSE` text (currently MIT from kmp.new's default if any) accordingly. If Proprietary, write a short proprietary notice.

### 8. Git init + first commit + optional GitHub repo

If user opted in to git init:

```bash
source "${TMPDIR:-/tmp}/kmp-forge-init.env"
cd "${TARGET:?}" || exit 1
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
# Workflow labels the backlog relies on (ready, in-progress, epic, priority:high|low, no-spec, chore, adr)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/issues.sh" labels
```

If `gh` is not authenticated, surface `gh auth login` instructions to the user instead of failing. Never push to a public repo by default — visibility flips require explicit user opt-in.

If user declines: print the manual commands for them to run later (`gh repo create ... --private --source=. --remote=origin && git push -u origin main`, then `bash <plugin>/scripts/issues.sh labels` from the project root).

### 9. Report next steps

Print a checklist of what the user should do next:

```
✓ Project scaffolded at <path>
✓ Modules: :shared · :androidApp · :desktopApp · :ui · :domain · :data · :testing + build-logic/
✓ Composition root: shared/…/App.kt (Koin) + AppNavigation.kt (Nav 3) + AppModules.kt
✓ CI workflows: .github/workflows/pr.yml + release.yml + spec-link.yml
✓ Product docs: docs/MVP_SPEC.md + docs/DECISIONS/{0001..0006}.md
✓ Spec workflow: <OpenSpec (openspec/config.yaml with kmp-forge rules, /opsx:* commands) | plain docs>
✓ Issue labels: <created | run issues.sh labels after pushing>
✓ CLAUDE.md generated

Next:
  1. cd "<path>" && ./gradlew build              # verify build
  2. Open in Android Studio / IntelliJ
  3. Push to GitHub:
       gh repo create <name> --private --source=. --remote=origin
       git push -u origin main
  4. Enable branch protection on main (see docs/git-conventions.md)
  5. Run /kmp-forge-spec to fill out docs/MVP_SPEC.md
  6. Run /kmp-forge-refine --gaps to draft the first backlog issues from the spec, then
     approve the ones to build yourself: gh issue edit <n…> --add-label ready
  7. Run /kmp-forge-add-feature <name> to add your first feature module

Opt-in libraries you selected: <list>
  Wiring them up: see https://github.com/arthurnagy/kmp-forge/blob/main/docs/stack.md#opt-in-libraries
```

## Notes

- The plugin does NOT push to GitHub. The user opts into that themselves.
- The plugin does NOT enable branch protection. Same reason.
- Always quote paths with spaces (`"$TARGET"`) — the user's Personal projects directory has a space.
- `openspec init` writes `.claude/commands/opsx/*` and `.claude/skills/openspec-*` into the project —
  they are committed with it, like any project-level Claude Code command.
- If `apply-overlay.sh` errors, surface the error verbatim and stop — do NOT try to clean up partially-applied overlay (let the user inspect).
