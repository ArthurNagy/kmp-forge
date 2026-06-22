# Changelog

All notable changes to `kmp-forge` will be documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed (BREAKING)
- **Target the current kmp.new output: Kotlin 2.4 / AGP 9 / Compose MP 1.11 / Gradle 9.1 and the `:shared` + app-module layout.** kmp.jetbrains.com now generates a `:shared` KMP library (the composition host — `App.kt`, `startKoin`, the Nav 3 back stack) plus thin `:androidApp`/`:desktopApp` (+ `iosApp/`) instead of a single `:composeApp`, and uses AGP 9's `com.android.kotlin.multiplatform.library` plugin. The overlay was reworked to match:
  - **Catalog** no longer re-pins the toolchain — build-logic plugin entries now reference kmp.new's own `kotlin`/`agp`/`composeMultiplatform`/`androidx-lifecycle`/`kotlinx-coroutines` keys, so the whole build shares one toolchain version (no "plugin loaded with different version" failure) and the overlay is drift-proof across future kmp.new bumps.
  - **build-logic is now a precompiled script plugin** (`build-logic/src/main/kotlin/kmp-forge.kmp.library.gradle.kts`) instead of a Kotlin class plugin: a class plugin can't compile against KGP 2.4 under Gradle 9.1's embedded Kotlin 2.2. The `ComposeApp` convention plugin (`kmp-forge.compose.app`) was removed — modules apply Compose via `alias(libs.plugins.composeMultiplatform/composeCompiler)` and the Android target via `alias(libs.plugins.androidMultiplatformLibrary)` + an `androidLibrary { namespace; compileSdk; minSdk; jvmTarget = 17 }` block.
  - **`:shared` is the composition root**; `:androidApp`/`:desktopApp`/`iosApp/` are thin entry points. Updated in lockstep: `docs/{architecture,stack,ci,secrets,observability,release,i18n-a11y,ios-troubleshooting}.md`, `kmp-{feature-builder,migrator,reviewer}`, `kmp-forge-{init,add-feature,add-screen,add-platform,doctor,adopt}`, ADRs 0002–0006, CI templates, `.gitignore`, `CLAUDE.md`, README, skills.

### Fixed
- **Kover** 0.9.1 → 0.9.8 — 0.9.1 rejected AGP 9's KMP library plugin (`Kover requires extension with name 'android'`).
- **`apply-overlay.sh patch-settings`** now ensures a trailing newline before appending `include(...)` lines (kmp.new's `settings.gradle.kts` ships without one, which produced `include(":shared")include(":ui")`).
- **`.editorconfig`** ktlint config for the locked stack: disabled `filename`, `multiline-expression-wrapping`, and `chain-method-continuation` (they fight idiomatic `val xModule = module {}` and the `libs.versions.x.get().toInt()` catalog idiom), and exempt `@Composable` from `function-naming`.
- **Detekt** now actually scans KMP `commonMain` (was `NO-SOURCE` / a vacuous gate) via `source.setFrom("src")` + the project `detekt.yml`; design-token files pass with `MagicNumber.ignorePropertyDeclaration` and `FunctionNaming.ignoreAnnotated: [Composable]`.
- **`:ui` module template** declares its `koin.core` dependency (`uiModule.kt` uses Koin).
- **Test tasks** set `failOnNoDiscoveredTests = false` so a utility-only `commonTest` (e.g. `TestDispatcherProvider`) doesn't fail the Gradle 9 build.
- **`navigation3-ui` now uses the JetBrains Compose Multiplatform port** — the locked stack pinned Google's `androidx.navigation3:navigation3-ui`, whose only KMP variants are `androidJvm`/`jvm`/`linux_x64`; sitting in `commonMain`, it cannot resolve for iOS/macOS/js/wasm targets, so any non-Android scaffold would fail to build. Switched the UI artifact to `org.jetbrains.androidx.navigation3:navigation3-ui` (full multiplatform) and dropped the pin `1.1.2 → 1.1.1` (the port's latest stable — `1.1.2` never existed for it). `navigation3-runtime` correctly stays on Google's `androidx.navigation3:navigation3-runtime`: that artifact *is* fully multiplatform and is exactly what the UI port depends on, so the shared `androidxNavigation3` ref still resolves both. `fetch-latest-versions.sh` now tracks the UI port on Maven Central (was Google Maven — the version-line mismatch behind the upstream bug report). Corrects the 0.3.1 note "`androidx.navigation3` correctly stays on Google Maven", which held only for the runtime, not the UI. Touched (lockstep): `overlay/gradle/libs.versions.toml.additions.tmpl`, `docs/stack.md`, ADR 0004, `scripts/fetch-latest-versions.sh`.

## [0.3.1] - 2026-06-05

### Fixed
- **`fetch-latest-versions.sh` returned stale/missing versions** (#7) — the script backing `/kmp-forge-bump-stack` queried the deprecated `search.maven.org/solrsearch` endpoint, whose lagging index returned versions *older* than the current pins across the maven-central stack (e.g. orbit 10 vs 11, ktor 3.2 vs 3.5, kotlin 2.2 vs 2.4), so a blind follow proposed downgrades; and it tagged `androidxLifecycle` (`org.jetbrains.androidx.lifecycle`, a JetBrains MPP port on Maven Central) as `google-maven`, which 404'd into a bogus WARN. Both repos now read the authoritative `maven-metadata.xml` via one shared `fetch_latest` helper, dropping the `python3` dependency. `androidx.navigation3` correctly stays on Google Maven.

## [0.3.0] - 2026-06-01

### Changed (BREAKING)
- **Restrictive visibility + explicit state + Nav 3 entry contributions** — the locked stack is now deliberately restrictive about visibility, and the generated `:feature-*` contract changed:
  - **Visibility:** `private`/`internal` by default; `public` only for a module's deliberate cross-module API. In `:data`, repository implementations, data sources, DTOs, and `RealDispatcherProvider` are `internal`. A `:feature-*`'s only public API is its `Route`, Koin `Module`, and `addXEntries(...)`; `State`/`ViewModel`/`Screen` are `internal`, `Content` is `private`. Use-case constructors stay public so feature tests build them with fakes.
  - **No default values** on domain entities or presentation `State`; `State` carries a `companion object { val Initial }` (single starting-state source for `container(...)` and tests). DTOs may keep wire-format defaults.
  - **Nav 3 entry contributions:** the app no longer references feature screens via `NavDisplay { when }`. Each feature exposes a public `EntryProviderBuilder<NavKey>.addXEntries(...)` that contributes `entry<Route> { Screen(...) }`, composed by the app in `NavDisplay(entryProvider = entryProvider { ... })`. Cross-feature navigation flows through callbacks (the app owns target routes), so a feature never imports another feature's `Route`.
  - Migrate existing projects via `/kmp-forge-adopt`'s new `visibility` layer + updated `nav` layer. Touched (lockstep): `docs/{architecture,stack,testing}.md`, `kmp-reviewer`, `kmp-feature-builder`, `kmp-migrator`, all feature/domain/data templates (+ new `FeatureNavEntry.kt.tmpl`), `kmp-forge-{adopt,add-feature,add-screen}`, ADR 0004, `CLAUDE.md`.
- **Error handling now uses [kotlin-result](https://github.com/michaelbull/kotlin-result)** — `Result<T, DomainError>` is its two-param `Result<V, E>` (`Ok`/`Err`), Gradle coordinate `com.michael-bull.kotlin-result:kotlin-result` (+ `kotlin-result-coroutines`), import package `com.github.michaelbull.result.*`, declared `api` in `:domain`. Resolves the prior contradiction where ADR 0005 said stdlib `Result<T>` (single-param, `Throwable`-only) while every signature used the two-param form. Feature-state `error` slot is now typed `DomainError?` (was `String?`). Touched: catalog additions, `:domain` build, feature State/ViewModel templates, ADR 0005, `docs/{architecture,stack,testing,product-workflow}.md`, `kmp-reviewer`, `kmp-feature-builder`, `kmp-migrator`, `CLAUDE.md`.

### Added
- **`/kmp-forge-adopt` command + `kmp-migrator` agent** — bring the locked stack to an *existing* KMP project (no kmp.new download). Phase A applies the overlay non-destructively (additive merges auto; overwrite-danger files diffed and hand-merged); Phase B is a dependency-ordered, `kmp-reviewer`-audited refactor delegated to the new `kmp-migrator` agent, one locked-stack layer per invocation (dispatchers, result, repos, koin, orbit, nav, module-deps, visibility, tests, a11y).

### Changed
- **Self-contained marketplace** — collapsed the standalone `arthurnagy/claude-plugins` marketplace repo into this repo. `.claude-plugin/marketplace.json` now lives at the repo root with `source: "./"` (caveman-style). Install path is now `/plugin marketplace add arthurnagy/kmp-forge` + `/plugin install kmp-forge@kmp-forge`. Reason: the standalone marketplace was triggering an SSH clone of `arthurnagy/kmp-forge` regardless of source shape (`github`, `git`, `git-subdir` all failed in different ways); a single self-contained repo sidesteps the second-repo clone entirely.

### Fixed
- **State-only-events doc drift** (#3) — stopped recommending `postSideEffect` in docs that lingered after the v0.2 state-only switch.
- **Component review findings** (#4) — resolved inconsistencies flagged by a Claude Code component review pass across commands and agents.

## [0.2.0] - 2026-05-25

Refinements pass after user's expanded notes.

### Changed (BREAKING)
- **State-only events** — `postSideEffect` removed from the locked stack. `ContainerHost` effect type is now `Nothing`. One-shot events (navigation, toasts, snackbars) modeled as **consumable state slots** on the state class, cleared by paired `onXxxConsumed()` intents the UI calls after rendering. Reason: everything is state — robust across config changes / process death, trivially testable. Affected: feature templates (State/ViewModel/Screen/Test), `docs/architecture.md`, `docs/stack.md`, ADR 0001, `kmp-reviewer`, `kmp-feature-builder`.

### Added
- **ktlint via Spotless** alongside detekt. Convention plugin applies Spotless to every shared module; ktlint version pinned in `libs.versions.toml`. CI runs `spotlessCheck`; `spotlessApply` for local auto-fix.
- **Kover coverage** with target 75%. Convention plugin applies Kover per module. CI runs `koverVerify` and uploads HTML + XML reports as a workflow artifact. Verify rule lives in root `build.gradle.kts`.
- **Store (MobileNativeFoundation/Store)** as opt-in library for offline-first multi-source repositories.
- **Single-type repository rule** documented in `docs/architecture.md` and enforced by `kmp-reviewer` (one `*Repository` per domain type — never an `AppRepository` god object).
- **Sealed-interface sub-states pattern** documented for mutually-exclusive page-level transitions (Loading/Loaded/Error); feature template comments show the shape.
- **Feature-owned analytics** noted in `docs/architecture.md` — analytics events specific to a feature live in the feature module, not centralized.
- **GitHub Issues + Projects (Kanban) workflow** documented in `docs/product-workflow.md` as the v0.1 product tracker. No Jira/Linear.
- **OpenSpec recommendation** in `docs/product-workflow.md` — skip for solo projects; revisit when 3+ contributors or autonomous-execution scenarios appear.
- **Private repo default** for `/kmp-forge-init`. Optional `gh repo create --private` step after `git init`, documented in `docs/git-conventions.md`.

### Notes
- `docs/ci.md` updated: PR workflow now runs `spotlessCheck detekt build koverVerify`. Runner matrix entry split. New "Code quality + coverage" section.
- `libs.versions.toml.additions.tmpl` gained: `spotless`, `ktlint`, `kover`, `store`, plus Spotless + Kover gradle-plugin libraries and plugin aliases.

## [0.1.0] - 2026-05-25

Initial release.

### Features
- `/kmp-forge-init` — end-to-end scaffold flow. Drives the JetBrains KMP Wizard at kmp.jetbrains.com via explicit step-by-step instructions (no URL params), then applies the overlay: CLAUDE.md, modules, CI, git, product docs, build-logic.
- `/kmp-forge-add-feature <name>` — generates a complete `:feature-<name>` module on the locked stack (Compose screen + Orbit ViewModel + state + Koin module + Nav 3 destination + commonTest skeleton), wired into composeApp Koin start + NavDisplay.
- `/kmp-forge-add-screen <feature> <screen>` — adds a screen inside an existing feature module.
- `/kmp-forge-add-platform <desktop|web|ios>` — extends an existing project to a new platform.
- `/kmp-forge-add-library <query>` — klibs.io lookup + `libs.versions.toml` insert.
- `/kmp-forge-bump-stack` — refreshes `libs.versions.toml` against latest stable versions of every locked-stack library.
- `/kmp-forge-spec [--from-dump]` — authors `docs/MVP_SPEC.md` (interactive interview or free-form paste).
- `/kmp-forge-doctor` — diagnostic for JDK / Xcode / Android SDK / Gradle / Kotlin / signing / git hooks.

### Agents
- `kmp-feature-builder` — multi-file feature scaffolder invoked by `/kmp-forge-add-feature`. Reads existing features for style reference, wires use cases from `:domain` when relevant, builds + reports.
- `kmp-reviewer` — diff/branch/file reviewer enforcing locked-stack conventions: Orbit MVI patterns, Koin DI, Nav 3 type-safe routes, Result+DomainError, DispatcherProvider injection, fakes-not-mocks in commonTest, a11y rules (contentDescription, touch target, no hardcoded sp), RTL convention (start/end not left/right), secrets in untracked files.

### Skills
- `conventional-commits` · `git-cliff-changelog` · `github-release-artifacts` · `mvp-spec-authoring` · `adr-authoring`

### Locked stack
- Kotlin Multiplatform + Compose Multiplatform · Orbit MVI · Koin · AndroidX Navigation 3 (1.1.2) · Coil 3 · Kermit · kotlinx-datetime · kotlinx-serialization · Compose Multiplatform Resources
- Opt-in: Ktor Client · SQLDelight · Sentry · Firebase App Distribution · gradle-play-publisher
- Excluded by default: image picker, fastlane, analytics, perf monitoring

### Architecture
- Hybrid: `:feature-<name>` = presentation only; shared `:domain` + `:data` + `:ui`; `build-logic/` convention plugins from day one.
- Error handling: `Result<T>` + sealed `DomainError` per use case. No exceptions across layer boundaries.
- Coroutines: `DispatcherProvider` interface injected; no raw `Dispatchers.*` references in `:domain`/`:data`/`:feature-*`.
- Testing: `kotlin.test` + Orbit `ContainerHost.test()` + Turbine for edge cases + Compose UI Test. Fakes preferred; MockK allowed only in `jvmTest`/`androidTest`.

### Plugin docs (12)
- `architecture.md` · `stack.md` · `testing.md` · `ci.md` · `git-conventions.md` · `release.md` · `observability.md` · `product-workflow.md` · `secrets.md` · `i18n-a11y.md` · `ios-troubleshooting.md` · `upgrade-policy.md`

### Distribution
- Public GitHub repo `arthurnagy/kmp-forge` + separate marketplace `arthurnagy/claude-plugins`.
- Install: `/plugin marketplace add arthurnagy/claude-plugins` then `/plugin install kmp-forge@arthurnagy-claude-plugins`.

### Build
- 79 files across 6 commits.
- All scripts smoke-tested locally; overlay rendering, settings.gradle.kts patching, and libs.versions.toml merging validated against a scratch project.

### Known limitations (carry into v0.2)
- iOS scaffolding via `/kmp-forge-add-platform ios` instructs user to use kmp.jetbrains.com for the iOS app skeleton; first-class overlay templates for `iosApp/` Xcode project deferred.
- Sentry, Firebase App Distribution, gradle-play-publisher opt-ins print wiring notes rather than auto-modifying `build.gradle.kts` + `release.yml`.
- klibs.io has no JSON API; `/kmp-forge-add-library` is best-effort HTML parsing with manual fallback.
- Stack-pattern skills (Orbit, Koin, Nav 3, Coil, etc) deferred — docs + agent prompts cover them inline for v0.1.0.
- Custom detekt ruleset for a11y enforcement deferred — `kmp-reviewer` agent enforces the same rules at PR-review time.

### Open user actions
- Push `arthurnagy/kmp-forge` and `arthurnagy/claude-plugins` to GitHub.
- Test `/kmp-forge-init` end-to-end against a real kmp.jetbrains.com download; surface bugs.
