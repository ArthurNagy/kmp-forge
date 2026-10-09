# kmp-forge

A Claude Code plugin that scaffolds and guides Kotlin Multiplatform + Compose Multiplatform projects on a locked, opinionated stack.

## What it does

`kmp-forge` downloads the base project straight from [kmp.jetbrains.com](https://kmp.jetbrains.com/)'s generator (no browser step), raises it to the toolchain floor (AGP ≥ 9.4.1, Gradle ≥ 9.8.1), then overlays consistent opinions across every new project: architecture, modules, CLAUDE.md, CI, git, product docs, observability, and release plumbing. JetBrains keeps the wizard current; `kmp-forge` keeps your opinions sharp.

## Install

```
/plugin marketplace add arthurnagy/kmp-forge
/plugin install kmp-forge@kmp-forge
```

## Slash commands

- `/kmp-forge-init` — scaffold a new project via kmp.new + apply overlay
- `/kmp-forge-adopt` — adopt the locked stack into an existing KMP project (non-destructive overlay + reviewer-led refactor plan)
- `/kmp-forge-add-feature <name>` — add a `:feature-<name>` module (UI + ViewModel + state + Koin + Nav 3 destination + tests)
- `/kmp-forge-add-screen <feature> <screen>` — add an Orbit screen inside an existing feature
- `/kmp-forge-add-platform <desktop|web|ios>` — add a platform to an existing project
- `/kmp-forge-add-library <query>` — find a KMP library via klibs.io and add it to the version catalog
- `/kmp-forge-bump-stack` — refresh `libs.versions.toml` against the latest stable versions
- `/kmp-forge-spec` — author `MVP_SPEC.md` interactively or from a free-form dump
- `/kmp-forge-refine <idea | #issues | --gaps>` — product-owner pass: draft workable backlog issues (acceptance criteria, one-PR slices, epics split), file the ones you pick; you approve them with `ready`
- `/kmp-forge-doctor` — check JDK, Xcode, Android SDK, Android CLI, Gradle wrapper + AGP floor
- `/kmp-forge-add-autoloop` — install the autonomous build loop (OpenSpec workflow, GitHub-issue queue, merge-guard hook) into a project
- `/kmp-forge-next-increment` — run ONE autonomous increment on the next `ready` issue (propose → gate → implement → gate → merge); wrap with `/loop` to work the queue down

## Locked stack

| Concern | Choice |
|---|---|
| MVI | Orbit MVI |
| DI | Koin |
| Navigation | Navigation 3 — the JetBrains Compose Multiplatform port only |
| Image loading | Coil 3 |
| HTTP (opt-in) | Ktor Client |
| Persistence: prefs | DataStore (KMP) |
| Persistence: relational (opt-in) | SQLDelight |
| Serialization | KotlinX Serialization |
| Logging | Kermit |
| Date/time | kotlinx-datetime |
| Resources / i18n | Compose Multiplatform Resources |
| Crash reporting (default) | Platform out-of-box (Play Vitals, App Store Connect) |
| Crash reporting (opt-in) | Sentry across all platforms |
| Testing | kotlin.test + Orbit `testWithInternalState` + Turbine + Compose UI Test; shared doubles in `:testing` |
| Coverage | Kover, aggregated at the root, ≥ 75% gate (`koverVerify`) |
| Toolchain floor | AGP ≥ 9.4.1, Gradle ≥ 9.8.1 (Kotlin / Compose MP from kmp.new) |
| Mocking | Fakes preferred; MockK only on JVM |
| CI | GitHub Actions |
| Distribution | GitHub Release artifacts default; Firebase App Distribution + gradle-play-publisher opt-in |
| Work tracking | GitHub issues — `ready` (human-applied) = the backlog |
| Spec workflow | OpenSpec (default; plain docs opt-out) with kmp-forge rules in `openspec/config.yaml`; CI `spec-link` check |
| Branching | Trunk-based, Conventional Commits |
| Changelog | git-cliff on tag |
| Architecture | Hybrid — features = presentation only; shared `:domain`, `:data`, `:ui` |
| Modules at scaffold | `:shared` (composition root) `+ :androidApp + :desktopApp + :webApp + iosApp/ + :ui + :domain + :data + :testing + build-logic/` |
| Device checks | Google's Android CLI (`android emulator` / `run` / `layout` / `screen`) — emulator first; the `kmp-qa` agent runs a change's acceptance scenarios as journeys on an emulator or a connected phone |

## Documentation

The plugin's `docs/` directory holds the source-of-truth conventions every scaffolded project links to:

- [Architecture](docs/architecture.md)
- [Stack](docs/stack.md)
- [Testing](docs/testing.md)
- [CI](docs/ci.md)
- [Release](docs/release.md)
- [Observability](docs/observability.md)
- [Git conventions](docs/git-conventions.md)
- [Product workflow](docs/product-workflow.md)
- [Autonomous build loop](docs/autoloop.md)
- [Secrets](docs/secrets.md)
- [i18n & a11y](docs/i18n-a11y.md)
- [iOS troubleshooting](docs/ios-troubleshooting.md)
- [Upgrade policy](docs/upgrade-policy.md)

## License

MIT — see [LICENSE](LICENSE).
