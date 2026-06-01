# Architecture

`kmp-forge` projects use a **hybrid** architecture: feature modules hold only presentation; shared modules hold all domain logic, data sources, and UI primitives.

## Module map

```
:composeApp              app entry point per platform; wires Koin + composes nav graph
:ui                      AppTheme, design tokens (AppColors/AppType/AppSpacing/AppDimens), reusable Composables
:domain                  use cases, domain entities, repository interfaces, DispatcherProvider, DomainError sealed base
:data                    repository implementations, data sources (network, db, prefs), DTOs, mappers
:feature-<name>          Compose UI + ViewModel + state + nav destination for one feature
build-logic/             Gradle convention plugins (KmpLibrary, ComposeApp)
```

## Dependency direction

```
:composeApp ──▶ :feature-*    ──▶ :ui
                            └─▶ :domain
:feature-*  ──▶ :ui
            └─▶ :domain
:data       ──▶ :domain         (implements interfaces declared in :domain)
:domain     ──▶ (nothing internal — pure Kotlin + Coroutines + kotlinx-datetime + kotlinx-serialization + kotlin-result)
```

Rules:
- `:domain` depends on nothing internal. No Compose, no Android, no Coil, no Ktor.
- `:data` depends only on `:domain` (interfaces) + KMP libs it needs (Ktor, SQLDelight, DataStore).
- `:feature-*` depends on `:domain` (use cases) and `:ui` (theme + primitives). Never depends on `:data` directly — repos are injected via Koin against `:domain` interfaces.
- Features never depend on other features.

## What goes where

### `:domain`
- Use cases as `class GetUserUseCase(private val repo: UserRepository, private val dispatchers: DispatcherProvider) { suspend operator fun invoke(id: UserId): Result<User, DomainError> }`
- Domain entities (`User`, `Order`, value classes)
- Repository **interfaces** (`UserRepository`)
- `DomainError` sealed types per use case or per domain area
- `DispatcherProvider` interface
- Pure Kotlin only.

`Result<T, DomainError>` is [kotlin-result](https://github.com/michaelbull/kotlin-result)'s two-param `Result<V, E>` — Gradle coordinate `com.michael-bull.kotlin-result:kotlin-result`, Kotlin import package `com.github.michaelbull.result.*` (`Ok`/`Err`/`onSuccess`/`onFailure`/`fold`/`andThen`/…). It's declared `api` in `:domain` so the type flows transitively to `:data` and `:feature-*`. **Not** `kotlin.Result` (stdlib, single-param, `Throwable`-only). See ADR `0005-result-domain-error` in your project's `docs/DECISIONS/`.

### `:data`
- Repository **implementations** (`UserRepositoryImpl`)
- Data sources: `UserRemoteDataSource` (Ktor), `UserLocalDataSource` (DataStore/SQLDelight)
- DTOs (`UserDto`) + mappers (`UserDto.toDomain()`)
- Koin module exposing implementations bound to `:domain` interfaces.

**Single-type rule** — one repository or data source per domain type. `UserRepository` handles only `User` operations. `OrderRepository` handles only `Order`. Never a single `AppRepository` aggregating multiple types — it inevitably grows into a god object. If two types are conceptually one (e.g. `User` and `UserProfile` are the same aggregate), model them as a single domain type, not split repos.

For offline-first multi-source data (remote + cache + db) consider Store ([stack.md § Store](stack.md#store-mobilenativefoundationstore)) per type.

### `:ui`
- `AppTheme {}` wrapper around `MaterialTheme`
- Design tokens: `AppColors`, `AppType`, `AppSpacing`, `AppDimens` as Kotlin objects
- Reusable Composables (buttons, cards, dialogs) — strictly stateless, hoisted-state pattern
- Compose Multiplatform Resources (`Res.string`, `Res.drawable`)

### `:feature-<name>`
- One `*Screen.kt` per screen — stateless, takes state + lambdas
- One `*ViewModel.kt` per screen — `class FooViewModel(private val useCase: ...) : ViewModel(), ContainerHost<FooState, Nothing>`
- One `*State.kt` with `data class FooState(...)` (or `sealed interface FooState` for mutually-exclusive page-level sub-states)
- One `*Route.kt` — `@Serializable data class FooRoute(...) : NavKey`
- One `*Module.kt` — Koin module exposing the ViewModel via `viewModelOf(::FooViewModel)`
- `commonTest/FooViewModelTest.kt` with `ContainerHost.test()`
- Feature-owned analytics: any analytics events specific to this feature live in the feature module (e.g. `FooAnalytics.kt` with named event constants + a thin wrapper around an injected analytics client). Cross-feature analytics interfaces live in `:domain` or a shared `:analytics` module if it grows. Don't centralize all events in `:composeApp`.
- Feature-owned navigation contribution: the feature exposes its `FooRoute` for the app to compose into `NavDisplay`; the feature does not own the back stack itself.

### `:composeApp`
- Per-platform entry point (`MainActivity` on Android, `MainViewController` on iOS, `main()` on desktop/web)
- `App.kt` in `commonMain` — composes `AppTheme {}` + nav back stack
- `startKoin` bootstrap pulling in `domainModule + dataModule + uiModule + every featureModule`
- Crash reporter / Sentry init (when opted in) before `App()`

## When to extract a new shared module

Defaults are enough for projects up to ~10 features. Extract when:

- **`:designsystem`** splits off `:ui` when design tokens grow beyond ~5 files or you start versioning the design system independently.
- **`:auth`** splits off `:domain` + `:data` when auth state needs its own lifecycle distinct from feature ViewModels (e.g. global token refresh, session listeners).
- **`:network`** splits off `:data` when network configuration (Ktor client + interceptors + Sentry hooks + retry policy) grows beyond a single file.
- **`:persistence`** splits off `:data` when you have multiple SQLDelight databases or share a single database across many repos.

Add via `/kmp-forge-add-module <name>`. New modules follow the same dependency rules (pure-Kotlin or Compose-aware as appropriate).

## ViewModel + Orbit pattern (state-only)

```kotlin
data class GalleryState(
    val loading: Boolean = false,
    val photos: List<Photo> = emptyList(),
    val error: DomainError? = null,

    // Consumable event slots — set inside intent {}, cleared by paired onXxxConsumed().
    val pendingNavigation: PhotoDetailRoute? = null,
    val pendingMessage: String? = null,
)

class GalleryViewModel(
    private val getPhotos: GetPhotosUseCase,
) : ViewModel(), ContainerHost<GalleryState, Nothing> {

    override val container = container<GalleryState, Nothing>(GalleryState())

    fun load() = intent {
        reduce { state.copy(loading = true) }
        getPhotos()
            .onSuccess { photos -> reduce { state.copy(loading = false, photos = photos) } }
            .onFailure { error -> reduce { state.copy(loading = false, error = error) } }
    }

    fun openPhoto(id: PhotoId) = intent {
        reduce { state.copy(pendingNavigation = PhotoDetailRoute(id)) }
    }

    fun onNavigationConsumed() = intent {
        reduce { state.copy(pendingNavigation = null) }
    }
}
```

```kotlin
val state by viewModel.collectAsState()
LaunchedEffect(state.pendingNavigation) {
    state.pendingNavigation?.let { route ->
        backStack.add(route)
        viewModel.onNavigationConsumed()
    }
}
```

Rules:
- ViewModel never references `Dispatchers.IO` directly — use `dispatchers.io` from `DispatcherProvider` (injected into use cases, not ViewModels directly).
- Use case returns `Result<T, DomainError>`. ViewModel uses `onSuccess` / `onFailure` and updates state.
- **No `postSideEffect`**. ContainerHost's effect type is `Nothing`. One-shot events (navigation, toasts, snackbars) live as **consumable state slots** (`pendingNavigation: Route?`, `pendingMessage: String?`). UI observes them with `LaunchedEffect(...)`, consumes, then calls a paired `onXxxConsumed()` intent to clear them. Reason: everything is state — easier to test, easier to inspect, easier to reason about restoration across config changes / process death.

### Sub-states via sealed interface

When a flat data class overcomplicates state management — typically when sub-states are mutually exclusive at the page level (e.g. `Loading | Loaded | Error`) — promote to a sealed interface:

```kotlin
sealed interface GalleryState {
    data object Loading : GalleryState
    data class Loaded(val photos: List<Photo>, val pendingNavigation: Route? = null) : GalleryState
    data class Error(val cause: DomainError) : GalleryState
}
```

UI matches on the sealed branch with a `when`. Default to flat data class — only promote when the flat shape grows boolean spaghetti (`if (loading && !error && photos.isEmpty()) ...`).

## Hybrid architecture rationale

Pure feature-first (every feature has its own `:presentation`, `:domain`, `:data`) creates module sprawl in small projects: a 5-feature app gets 15 modules. Pure layer-first (top-level `:presentation`, `:domain`, `:data` containing all features) makes "feature" a non-boundary — deleting a feature touches every layer.

Hybrid keeps the dominant code volume (UI + state) encapsulated per feature while keeping business logic and data centralized where cross-feature sharing is natural. Trade-off: a feature's domain logic is not private — it lives in the shared `:domain` module. Use package boundaries within `:domain` to keep features readable (`com.app.domain.gallery.*`).
