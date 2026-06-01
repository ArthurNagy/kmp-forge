# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`kmp-forge` is a **Claude Code plugin** — not a Kotlin project. It scaffolds and guides Kotlin Multiplatform + Compose Multiplatform projects on a locked, opinionated stack. The repo contains plugin components (commands, agents, skills), an overlay of templated project files, and bash scripts that render/patch a target project. There is no Kotlin source here — Kotlin only appears in `overlay/**/*.kt.tmpl` templates rendered into the user's scaffolded project.

Distribution: this repo is its own self-contained Claude Code marketplace (caveman-style — `.claude-plugin/marketplace.json` at the root with `source: "./"`). Installed by users as `/plugin marketplace add arthurnagy/kmp-forge` then `/plugin install kmp-forge@kmp-forge`. The historical `arthurnagy/claude-plugins` standalone marketplace repo is retired.

## Commands

Ad-hoc render/patch invocations for working on overlay templates and scripts:

```bash
# Render a single .tmpl in isolation (debug envsubst expansion)
APP_NAME=Foo BASE_PACKAGE=com.foo.app BASE_PACKAGE_PATH=com/foo/app \
  envsubst < overlay/root/CLAUDE.md.tmpl

# Render an entire directory tree into a scratch dir
APP_NAME=Foo BASE_PACKAGE=com.foo.app BASE_PACKAGE_PATH=com/foo/app \
  PLATFORM_LIST="- Android" BUILD_COMMANDS="" MODULE_LIST="" FEATURE_LIST="" \
  OPTIONAL_LIBS="" FIGMA_URL="" PROJECT_OVERRIDES="" TIMELINE="" \
  SCAFFOLD_DATE="$(date -u +%Y-%m-%d)" \
  bash scripts/apply-overlay.sh render overlay/root /tmp/kmp-forge-scratch

# Render a module skeleton (rewrites kotlin path to <base-pkg-path>/<module>/)
APP_NAME=Foo BASE_PACKAGE=com.foo.app BASE_PACKAGE_PATH=com/foo/app \
  bash scripts/apply-overlay.sh render-module domain overlay/modules/domain \
  /tmp/kmp-forge-scratch/domain com/foo/app

# Patch a project's libs.versions.toml with section-aware additions
bash scripts/apply-overlay.sh patch-libs /path/to/project \
  overlay/gradle/libs.versions.toml.additions.tmpl

# Query Maven Central / Google Maven for latest stable versions
bash scripts/fetch-latest-versions.sh toml   # or `json`

# Print kmp.new wizard instructions
bash scripts/kmp-new-url.sh Foo com.foo.app android,ios ktor,sqldelight
```

End-to-end validation of `/kmp-forge-init` requires a real kmp.jetbrains.com download — no test runner here.

## Local plugin install (live testing)

Marketplace install: `/plugin marketplace add arthurnagy/kmp-forge` then `/plugin install kmp-forge@kmp-forge`. For iterating on this repo before publishing, install from a local marketplace pointing at `$PWD` — see Claude Code plugin docs (`/help plugin`) for the current local-marketplace command; the cache lives at `~/.claude/plugins/`.

`.claude/settings.local.json` holds personal/CI permission allowlist (not shared). Currently allows read-only `rtk` calls — extend when a new repeatedly-used bash pattern appears.

## Repo layout (the big picture)

```
.claude-plugin/plugin.json   Plugin manifest (name, description, author, repo)
commands/                    Slash commands (kmp-forge-*.md) — entry points for users
agents/                      Subagents invoked by commands (kmp-feature-builder, kmp-reviewer)
skills/                      Workflow skills auto-triggered in scaffolded projects
                             (conventional-commits, git-cliff-changelog,
                              github-release-artifacts, mvp-spec-authoring, adr-authoring)
scripts/                     Bash renderers/patchers invoked by commands
  apply-overlay.sh             render | render-module | patch-settings | patch-libs
  kmp-new-url.sh               prints kmp.jetbrains.com wizard instructions
  fetch-latest-versions.sh     queries Maven Central / Google Maven for /kmp-forge-bump-stack
overlay/                     Templated files copied into scaffolded projects
  root/                        Top-level project files (CLAUDE.md.tmpl, .gitignore, detekt.yml, cliff.toml, .editorconfig)
  ci/                          GitHub Actions workflows (pr.yml.tmpl, release.yml.tmpl)
  git/                         PR/issue templates, .gitleaks.toml, pre-commit hook
  product/                     MVP_SPEC.md.tmpl + DECISIONS/ (ADR skeletons)
  modules/{ui,domain,data,feature}/   KMP module skeletons (`src/commonMain/kotlin/**/*.kt.tmpl`)
  build-logic/                 Gradle convention plugins (KmpLibrary, ComposeApp)
  gradle/libs.versions.toml.additions.tmpl   Section-aware additions merged into existing catalog
docs/                        Source-of-truth conventions linked from every scaffolded CLAUDE.md
                             (architecture, stack, testing, ci, git-conventions, release,
                              observability, product-workflow, secrets, i18n-a11y,
                              ios-troubleshooting, upgrade-policy)
```

## How a scaffold works (control flow)

`/kmp-forge-init` orchestrates:

1. `AskUserQuestion` gathers app name, base package, platforms, opt-in libs, license, git-init choice.
2. `scripts/kmp-new-url.sh` prints wizard instructions — JetBrains' kmp.new is a Next.js SPA with **no URL query-param support**, so we cannot pre-fill; the user fills it manually and downloads the zip.
3. Unzip into target dir. The user's machine path normally contains a space (`~/Development/Personal projects/<APP>`) — always quote paths.
4. Export overlay env vars (`APP_NAME`, `BASE_PACKAGE`, `BASE_PACKAGE_PATH`, `PLATFORM_LIST`, `BUILD_COMMANDS`, `MODULE_LIST`, `FEATURE_LIST`, `OPTIONAL_LIBS`, `SCAFFOLD_DATE`, etc.). These feed `envsubst` inside `apply-overlay.sh render`.
5. `apply-overlay.sh` sub-commands in sequence:
   - `render <src> <dest>` — walks src, runs `envsubst` on every `.tmpl` (strips suffix), copies non-tmpl as-is.
   - `render-module <module> <src> <dest> <base-pkg-path>` — same, but rewrites `src/commonMain/kotlin/X.kt` → `src/commonMain/kotlin/<base-pkg-path>/<module>/X.kt`.
   - `patch-settings <project> <module-csv>` — idempotently appends `include(":x")` to `settings.gradle.kts`.
   - `patch-libs <project> <additions-toml>` — Python-driven section-aware merge into `gradle/libs.versions.toml`: parses `[versions]/[libraries]/[plugins]`, appends only missing keys, preserves preamble + existing order.
6. Manual `Edit`-tool step inserts `includeBuild("build-logic")` inside the wizard-generated `pluginManagement { ... }` block (idempotent).
7. Optional `git init` + gitleaks pre-commit hook install + optional `gh repo create --private`.

`/kmp-forge-add-feature <name>` delegates to the `kmp-feature-builder` subagent: renders `overlay/modules/feature/` into `feature-<name>/`, renames `Feature*` → `<Name>*` files, wires a matching `:domain` use case if found via grep, edits `composeApp` `startKoin { modules(...) }` + adds the feature's `add<Name>Entries(...)` to `NavDisplay`'s `entryProvider { }` block, runs `./gradlew :feature-<name>:build` and reports.

`/kmp-forge-adopt` is `init`'s sibling for an **existing** project — no kmp.new download. It reuses the same `apply-overlay.sh` sub-commands but **non-destructively**: additive ops (`patch-libs`, `patch-settings`, new docs) run automatically; overwrite-danger files (`overlay/root` → CLAUDE.md, .gitignore, .editorconfig, detekt.yml, cliff.toml; CI) are rendered to a scratch dir and hand-merged via `git --no-index diff` + the Edit tool, never blind-copied. `render-module` is skipped when the project already has ui/domain/data layering (would duplicate). Phase B is a guided refactor: the `kmp-reviewer` agent audits the code, findings become a dependency-ordered work-list (DispatcherProvider → Result/DomainError → repos → Koin → Orbit state-only → Nav 3 entry-contributions → module deps → visibility/explicit-state → tests → a11y), refactored one layer at a time with `./gradlew spotlessCheck detekt build koverVerify` + reviewer re-run between layers.

## Locked-stack rules the agents/templates enforce in code

Full stack table lives in `README.md`. The rules below are the ones literally encoded across `agents/kmp-reviewer.md` (audit), `agents/kmp-feature-builder.md` (generation), `agents/kmp-migrator.md` (refactor existing code onto the rules), and `overlay/modules/feature/`. Change one → change all four (plus the canonical `docs/<area>.md`).

- **State-only events**: `ContainerHost<State, Nothing>`. `postSideEffect` forbidden. One-shot events (nav, toasts) → consumable state slots (`pendingNavigation: Route?`) cleared by `onXxxConsumed()` intents the UI calls after `LaunchedEffect`.
- **No raw dispatchers**: `Dispatchers.IO/Default/Main` forbidden in `:domain`/`:data`/`:feature-*`. Inject `DispatcherProvider`.
- **Result + sealed DomainError**: use cases return `Result<T, DomainError>` — kotlin-result's two-param `Result<V, E>` (Gradle `com.michael-bull.kotlin-result:kotlin-result`, import `com.github.michaelbull.result.*`), declared `api` in `:domain`. Not stdlib `kotlin.Result`. No throws, no `try/catch` in `intent {}`.
- **Typed nav + entry contributions**: Nav 3 routes are `@Serializable ... : NavKey` (no string keys). Features expose a public `EntryProviderBuilder<NavKey>.add<Name>Entries(...)` contributing `entry<Route> { Screen(...) }`; the app composes them in `NavDisplay(entryProvider = entryProvider { ... })` — never a `when` referencing screens. A feature never imports another feature's Route (outgoing nav as callbacks).
- **Restrictive visibility**: `private`/`internal` by default; `public` only for a module's real cross-module API. `:data` repo impls/data sources/DTOs/`RealDispatcherProvider` are `internal`. A `:feature-*`'s only public API is its `Route`, Koin `Module`, and `add<Name>Entries(...)`; `State`/`ViewModel`/`Screen` are `internal`. Use-case constructors stay public (feature tests build them with fakes).
- **No default values**: domain entities + presentation `State` have no constructor defaults; `State` carries a `companion object { val Initial }` (used by `container(...)` + tests). DTOs may keep wire-format defaults.
- **Koin constructor injection only**: `viewModelOf(::Foo)`, no `GlobalContext.get()`, no `KoinComponent` service locator.
- **One repo per domain type**: never `AppRepository` god object.
- **Fakes > mocks**: MockK allowed only in `jvmTest`/`androidTest`. `commonTest` uses fakes + `ContainerHost.test()`.
- **Module deps**: `:domain` pure Kotlin, no internal deps; `:feature-*` → `:domain` + `:ui`, never `:data`, never another feature.
- **CI gates**: `spotlessCheck detekt build koverVerify`. ktlint via Spotless; Kover target 75%.

## Plugin development workflow (this repo)

There is no build system here. Work is:

- **Edit a command** → `commands/<name>.md` (YAML frontmatter `description:`, body is the prompt).
- **Edit a subagent** → `agents/<name>.md` (YAML frontmatter `description:` + `tools:`, body is the system prompt).
- **Edit overlay templates** → `overlay/**/*.tmpl` (envsubst variables, e.g. `${APP_NAME}`). Non-tmpl files are copied as-is.
- **Edit a doc** → `docs/<topic>.md` (linked from every scaffolded CLAUDE.md).

### Testing a change

- **Templates**: render a single file with `APP_NAME=Foo BASE_PACKAGE=com.foo.app envsubst < overlay/.../foo.tmpl`. End-to-end against a real kmp.jetbrains.com download is the only way to fully validate `/kmp-forge-init` — the script is smoke-tested in `CHANGELOG.md`'s build notes, not via a test runner here.
- **Scripts**: `bash scripts/apply-overlay.sh render <src> <dest>` against a scratch directory. `patch-libs` invokes inline `python3` (3 only, not 2).
- **Plugin install for live testing**: `/plugin install kmp-forge@kmp-forge` (after pushing) or symlink locally — see Claude Code plugin docs.

### Required external tools at runtime

- `envsubst` (GNU gettext) — `brew install gettext && brew link --force gettext`.
- `python3` — for `apply-overlay.sh patch-libs`.
- `gh` — optional, for `/kmp-forge-init`'s GitHub repo creation step.
- The user's machine needs JDK, Android SDK, Xcode (mac+iOS), Gradle wrapper — `/kmp-forge-doctor` checks them.

## Conventions for editing this repo

- Conventional Commits (see `docs/git-conventions.md`). Releases tagged from `main`, changelog rendered by git-cliff (see `cliff.toml` analogue if added).
- When adding a new overlay variable, update both: (a) the `.tmpl` that uses it and (b) the `commands/kmp-forge-init.md` step 4 `export` block. Unset envsubst vars silently become empty strings — easy footgun.
- When changing a locked-stack rule, update **all four** in lockstep: `docs/<area>.md` (canonical), `agents/kmp-reviewer.md` (enforcement), `agents/kmp-feature-builder.md` (generation), `agents/kmp-migrator.md` (refactor recipe — detect/transform/verify for that rule), plus the relevant template under `overlay/modules/feature/` if shape changes. The v0.2 release in `CHANGELOG.md` is the example: state-only events touched 6 surfaces.
- Plugin docs (`docs/*.md`) are the source of truth — scaffolded `CLAUDE.md.tmpl` links to them on GitHub `main`, so docs ship with the plugin via the repo, not via copy.
- Paths in user-facing instructions must quote (`"$TARGET"`) — the user's Personal projects directory contains a space.
- Do NOT push to GitHub or enable branch protection from inside any command — the user opts into both manually.
