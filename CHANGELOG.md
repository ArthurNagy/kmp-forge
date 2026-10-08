# Changelog

All notable changes to `kmp-forge` will be documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Autonomous build loop (opt-in), promoted from a battle-tested downstream project.** Three tiers: (1) `driving-ci-green` skill — the canonical watch-checks / read-failures / mirror-CI-locally recipe, active in every project; (2) `kmp-spec-critic` agent — adversarial PASS/REVISE/BLOCK review of an OpenSpec change proposal, usable fully supervised; (3) the full loop — `/kmp-forge-add-autoloop` installs OpenSpec (`openspec init --tools claude`), a backlog + `AUTOLOOP.md` runbook (with a machine-read `## Loop configuration` section), and a 4-mode (`off|log|enforce-ci|enforce`) `merge-guard.sh` PreToolUse hook; `/kmp-forge-next-increment` (wrapped by `/loop`) then runs pop-slice → docs PR → spec gate → code PR → code gate → auto-merge, merging only when CI is green AND the posted 🤖 gate verdict reads PASS. Worker agents `kmp-loop-proposer` / `kmp-loop-implementer` / `kmp-loop-code-reviewer` / `kmp-loop-fixer` keep all heavy context out of the orchestrator, making the loop compaction-proof and crash-resumable. Touched (lockstep): `commands/kmp-forge-add-autoloop.md`, `commands/kmp-forge-next-increment.md`, `agents/kmp-{spec-critic,loop-proposer,loop-implementer,loop-code-reviewer,loop-fixer}.md`, `skills/driving-ci-green/`, `overlay/autoloop/`, `docs/autoloop.md`, `docs/product-workflow.md` (OpenSpec: overkill → opt-in), `docs/ci.md`, `README.md`, `overlay/root/CLAUDE.md.tmpl`, `CLAUDE.md`.

- **`:shared` composition root** (`overlay/shared/`) — `/kmp-forge-init` now renders `App.kt` (`KoinApplication` + `AppTheme`), `AppModules.kt` (the Koin module list), `AppNavigation.kt` (Nav 3 back stack with a `SavedStateConfiguration` registering every route, per-entry ViewModel scoping) and a placeholder `HomeRoute`, replacing kmp.new's sample `App.kt`. Previously nothing created `startKoin`/`NavDisplay` (init.md wrongly said kmp.new did), so the layer modules were never loaded, every `/kmp-forge-add-feature` fell back to "apply manually", and a hand-wired screen crashed with "KoinApplication has not been started". `/kmp-forge-add-feature` / `/kmp-forge-add-screen` wire into the files' `// kmp-forge:` markers.

### Changed
- **Locked stack bumped to current stable** — Orbit 9.0.0 → 12.0.1 (9.x `orbit-viewmodel`/`orbit-compose` were Android-only AARs, so features couldn't compile off Android), Koin 4.0.4 → 4.2.2, Coil 3.1.0 → 3.6.3, Ktor 3.1.2 → 3.6.0, Kermit 2.0.5 → 2.2.0, kotlinx-datetime 0.6.2 → 0.8.0 (`Instant`/`Clock` now live in `kotlin.time`), kotlinx-serialization 1.8.1 → 1.11.0, Nav 3 UI 1.1.1 → 1.1.2 + runtime 1.1.7, DataStore 1.1.7 → 1.2.1, SQLDelight 2.1.0 → 2.4.1, Store 5.1.0-alpha05 → 5.1.0-beta01, Detekt 1.23.7 → 1.23.8, Spotless 7.0.2 → 8.10.3, ktlint 1.5.0 → 1.8.0, Kover 0.9.8 → 0.9.11. Orphaned `koinAndroidx` removed.
- **Orbit 12 API** — templates/docs/agents use `OrbitContainerHost<State, State, Nothing>` + `orbitContainer(...)` (the `ContainerHost` alias and `container(...)` factory are deprecated) and the `testWithInternalState { expectInternalState { … } }` harness (initial state auto-asserted; `test()`/`expectInitialState()`/`expectState` are deprecated). kotlin-result docs use `onOk`/`onErr` with explicit imports (2.x deprecates `onSuccess`/`onFailure`; ktlint rejects the wildcard import the docs prescribed).
- **Feature package segment drops dashes** (`photo-detail` → `…feature.photodetail`, Koin module `photoDetailModule`) — the old `photo_detail` failed ktlint `package-name` and detekt `PackageNaming`.
- Module templates use the wizard's `libs.compose.*` catalog entries and `kotlin { android { } }` instead of the deprecated `compose.*` accessors and `androidLibrary { }`.

### Fixed
- **Catalog additions referenced undeclared version keys** — `kotlinx-coroutines` (and `kotlin`/`agp`/`composeMultiplatform`/`androidx-lifecycle`) were assumed from kmp.new's catalog, but the wizard only emits `kotlinx-coroutines` when Desktop is selected, so an Android+iOS init failed every Gradle invocation with "version reference 'kotlinx.coroutines' doesn't exist". The additions now declare fallbacks for every key they reference; `patch-libs` skips keys the wizard already provides, so the toolchain stays single-sourced.
- **Type-safe project accessors** — module templates and init's `:shared` wiring used `projects.domain`, which current kmp.new no longer enables (`TYPESAFE_PROJECT_ACCESSORS`); every build script failed to compile. Now `project(":domain")`.
- **`Dispatchers.IO` in `:data` commonMain** didn't compile for iOS / shared metadata (and can't for web). `RealDispatcherProvider` now uses an `expect val platformIoDispatcher` with JVM/Android/Native/web actuals; `render-module` maps every source set, not just `commonMain`/`commonTest`.
- **Feature template on the pre-1.0 Nav 3 API** — `EntryProviderBuilder` + a top-level `entry` import → `EntryProviderScope<NavKey>` with the member `entry`. Docs/ADR/agents no longer teach `rememberNavBackStack(Route)` in common code (that overload is Android-only).
- **Feature screen didn't compile and its snackbar never showed** — `Text(state.error)` passed a `DomainError`; errors now map to a string resource. The screen hosts its `SnackbarHost` in a `Scaffold`, so `pendingMessage` is shown and cleared. All template text comes from the feature's own `composeResources/values/strings.xml`.
- **Generated features failed their own gates** — `render-module` created a literal `feature.gallery/` directory (now `feature/gallery/`), the second rename rewrote the directory segment, the TODO comment tripped detekt `ForbiddenComment`, unused params tripped `UnusedParameter`, kebab names produced invalid Kotlin, and the verify task `:feature-x:commonTest` doesn't exist (now `:feature-x:build :shared:build`). `/kmp-forge-add-feature` passes `claude_plugin_root` to the agent.
- **Release workflow never published** — `apply-overlay.sh` ran a bare `envsubst`, which blanked the workflow's own `$ANDROID_KEYSTORE_BASE64`/`$RUNNER_TEMP` (`echo "" | base64 -d > /release.keystore`). Rendering now substitutes only the overlay variables (`OVERLAY_VARS`). `release.yml` also grants `contents: write` to the release job, waits for the ios/desktop jobs, and signs the AAB/APK via AGP's injected signing properties.
- **Spotless 8 build-service clash** — init/adopt add `id("kmp-forge.kmp.library") apply false` to the root build so the convention (and its Spotless/Detekt/Kover) load in one classloader.
- **Feature strings missing on Android** — under the AGP KMP library plugin a module's `composeResources` are only packaged when `androidResources { enable = true }` is set; the feature template now sets it (verified in the APK's `assets/composeResources/`).
- **iOS framework link OOM** — with the locked stack on the classpath, Kotlin/Native's in-daemon link exhausted kmp.new's 4 GiB Gradle heap on a clean `./gradlew build`; init raises `org.gradle.jvmargs` to `-Xmx6144M` when iOS is selected.
- **ktlint vs. the Orbit idiom** — `.editorconfig` sets `ktlint_function_signature_body_expression_wrapping = default`, so `fun load() = intent { … }` stays on one line (ktlint_official's `multiline` default wrapped every intent). `/kmp-forge-add-feature` runs `spotlessApply` before building, because ktlint's import order depends on the base package.
- **i18n doc caused crashes on non-English devices** — it put the default strings only in `values-en/`; Compose MP falls back only to the unqualified `values/`. Docs, reviewer and templates now use `values/` as the default table.
- **`fetch-latest-versions.sh`** — its pre-release filter was case-sensitive (reported `2.5.0-Beta1`, `1.12.0-RC`, `0.8.0-0.6.x-compat` as stable), it took the last *deployed* version rather than the highest, it used `tac` (absent on stock macOS — every key came back "not found"), and it emitted toolchain keys no project has (`kotlinGradlePlugin`, …), so `/kmp-forge-bump-stack` never bumped the toolchain. It now version-sorts, accepts only numeric releases (or a pre-release line for pins on one), emits the project's real keys, adds spotless/ktlint/kover/kotlinResult/store, and derives the Nav 3 runtime from the UI port. build-logic reads ktlint's version from the catalog instead of hard-coding it.
- **`docs/ci.md` pr.yml drift** — the fenced sample now matches `overlay/ci/pr.yml.tmpl` (split steps, bare `jvmTest`, `vars.IOS_ENABLED`).

## [0.3.2] - 2026-06-22

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
