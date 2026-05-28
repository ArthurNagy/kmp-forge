# Changelog

All notable changes to `kmp-forge` will be documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Self-contained marketplace** — collapsed the standalone `arthurnagy/claude-plugins` marketplace repo into this repo. `.claude-plugin/marketplace.json` now lives at the repo root with `source: "./"` (caveman-style). Install path is now `/plugin marketplace add arthurnagy/kmp-forge` + `/plugin install kmp-forge@kmp-forge`. Reason: the standalone marketplace was triggering an SSH clone of `arthurnagy/kmp-forge` regardless of source shape (`github`, `git`, `git-subdir` all failed in different ways); a single self-contained repo sidesteps the second-repo clone entirely.

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
