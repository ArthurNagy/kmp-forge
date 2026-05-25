# kmp-forge

A Claude Code plugin that scaffolds and guides Kotlin Multiplatform + Compose Multiplatform projects on a locked, opinionated stack.

## What it does

`kmp-forge` drives [kmp.jetbrains.com](https://kmp.jetbrains.com/) for the base project scaffold, then overlays consistent opinions across every new project: architecture, modules, CLAUDE.md, CI, git, product docs, observability, and release plumbing. JetBrains keeps the wizard current; `kmp-forge` keeps your opinions sharp.

## Install

```
/plugin marketplace add arthurnagy/claude-plugins
/plugin install kmp-forge@arthurnagy-claude-plugins
```

## Slash commands

- `/kmp-forge-init` — scaffold a new project via kmp.new + apply overlay
- `/kmp-forge-add-feature <name>` — add a `:feature-<name>` module (UI + ViewModel + state + Koin + Nav 3 destination + tests)
- `/kmp-forge-add-screen <feature> <screen>` — add an Orbit screen inside an existing feature
- `/kmp-forge-add-platform <desktop|web|ios>` — add a platform to an existing project
- `/kmp-forge-add-library <query>` — find a KMP library via klibs.io and add it to the version catalog
- `/kmp-forge-bump-stack` — refresh `libs.versions.toml` against the latest stable versions
- `/kmp-forge-spec` — author `MVP_SPEC.md` interactively or from a free-form dump
- `/kmp-forge-doctor` — check JDK, Xcode, Android SDK, Gradle wrapper versions

## Locked stack

| Concern | Choice |
|---|---|
| MVI | Orbit MVI |
| DI | Koin |
| Navigation | Navigation 3 (Compose Multiplatform) |
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
| Testing | kotlin.test + Orbit `ContainerHost.test()` + Turbine + Compose UI Test |
| Mocking | Fakes preferred; MockK only on JVM |
| CI | GitHub Actions |
| Distribution | GitHub Release artifacts default; Firebase App Distribution + gradle-play-publisher opt-in |
| Branching | Trunk-based, Conventional Commits |
| Changelog | git-cliff on tag |
| Architecture | Hybrid — features = presentation only; shared `:domain`, `:data`, `:ui` |
| Modules at scaffold | `:composeApp + :ui + :domain + :data + build-logic/` |

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
- [Secrets](docs/secrets.md)
- [i18n & a11y](docs/i18n-a11y.md)
- [iOS troubleshooting](docs/ios-troubleshooting.md)
- [Upgrade policy](docs/upgrade-policy.md)

## License

MIT — see [LICENSE](LICENSE).
