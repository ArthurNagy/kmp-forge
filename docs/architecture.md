# Architecture

`kmp-forge` projects use a **hybrid** architecture: feature modules hold only presentation; shared modules hold all domain logic, data sources, and UI primitives.

## Module map

```
:shared                  composition host — App.kt, startKoin bootstrap, Nav 3 back stack; emits the iOS `Shared` framework. Depends on :ui/:domain/:data/:feature-*
:androidApp              thin Android application — MainActivity, manifest, signing, AAB/APK; depends on :shared
:desktopApp              thin desktop JVM app — main(), native packaging (dmg/msi/deb); depends on :shared
iosApp/                  Xcode project consuming the Shared framework
:ui                      AppTheme, design tokens (AppColors/AppType/AppSpacing/AppDimens), reusable Composables
:domain                  use cases, domain entities, repository interfaces, DispatcherProvider, DomainError sealed base
:data                    repository implementations, data sources (network, db, prefs), DTOs, mappers
:feature-<name>          Compose UI + ViewModel + state + nav destination for one feature
build-logic/             the `kmp-forge.kmp.library` precompiled-script convention plugin
```

> kmp.new generates `:shared` + the thin `:androidApp`/`:desktopApp` (+ `iosApp/`) instead of
> the older single `:composeApp`. `:shared` is the composition root; the app modules are platform
> entry points over it.

## Dependency direction

```
:androidApp / :desktopApp ──▶ :shared    (thin platform entry points; iosApp/ consumes the Shared framework)
:shared     ──▶ :feature-*    ──▶ :ui
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
- Use cases as `class GetUserUseCase(private val repo: UserRepository, private val dispatchers: DispatcherProvider) { suspend operator fun invoke(id: UserId): Result<User, DomainError> }` — public class, public constructor (the type flows to `:feature-*`, and feature tests build it with a fake repo).
- Domain entities (`User`, `Order`, value classes) — **no default values**. Construct explicitly: `data class User(val id: UserId, val name: String, val email: String?)`, not `... = null`. Defaults hide intent at call sites and silently absorb newly-added fields; explicit construction forces every site to be revisited.
- Repository **interfaces** (`UserRepository`)
- `DomainError` sealed types per use case or per domain area
- `DispatcherProvider` interface
- Pure Kotlin only.

`Result<T, DomainError>` is [kotlin-result](https://github.com/michaelbull/kotlin-result)'s two-param `Result<V, E>` — Gradle coordinate `com.michael-bull.kotlin-result:kotlin-result`, Kotlin import package `com.github.michaelbull.result.*` (`Ok`/`Err`/`onSuccess`/`onFailure`/`fold`/`andThen`/…). It's declared `api` in `:domain` so the type flows transitively to `:data` and `:feature-*`. **Not** `kotlin.Result` (stdlib, single-param, `Throwable`-only). See ADR `0005-result-domain-error` in your project's `docs/DECISIONS/`.

### `:data`
- Repository **implementations** (`internal class UserRepositoryImpl`) — `internal`. Only `dataModule` (same module) references them; the rest of the app depends on the `:domain` interface, never the impl.
- Data sources: `internal class UserRemoteDataSource` (Ktor), `internal class UserLocalDataSource` (DataStore/SQLDelight) — `internal`, same reasoning.
- DTOs (`UserDto`) + mappers (`UserDto.toDomain()`) — `internal`. DTOs may keep default values where the wire format needs them (the no-default rule targets domain entities + State, not DTOs).
- Koin module exposing implementations bound to `:domain` interfaces. The module is public; binding an `internal` impl works because the binding lives in the same module.

**Single-type rule** — one repository or data source per domain type. `UserRepository` handles only `User` operations. `OrderRepository` handles only `Order`. Never a single `AppRepository` aggregating multiple types — it inevitably grows into a god object. If two types are conceptually one (e.g. `User` and `UserProfile` are the same aggregate), model them as a single domain type, not split repos.

For offline-first multi-source data (remote + cache + db) consider Store ([stack.md § Store](stack.md#store-mobilenativefoundationstore)) per type.

### `:ui`
- `AppTheme {}` wrapper around `MaterialTheme`
- Design tokens: `AppColors`, `AppType`, `AppSpacing`, `AppDimens` as Kotlin objects
- Reusable Composables (buttons, cards, dialogs) — strictly stateless, hoisted-state pattern
- Compose Multiplatform Resources (`Res.string`, `Res.drawable`)

### `:feature-<name>`

The feature's **public surface is exactly three things**: its `Route`, its Koin `Module`, and its `addFooEntries(...)` nav contribution. Everything else (`Screen`, `ViewModel`, `State`, `Content`) is `internal` to the module — the app composes the feature through the entry contribution, never by referencing the screen.

- One `*Screen.kt` per screen — `internal`, stateless, takes lambdas; resolves its ViewModel via `koinViewModel<FooViewModel>()` and hoists state to a `private *Content`.
- One `*ViewModel.kt` per screen — `internal class FooViewModel(private val useCase: ...) : ViewModel(), ContainerHost<FooState, Nothing>`
- One `*State.kt` — `internal data class FooState(...)` with **no default values** and a `companion object { val Initial = FooState(...) }` (the single starting-state source used by `container(...)` and tests). Or a `sealed interface FooState` for mutually-exclusive page-level sub-states (its initial state is an explicit object, e.g. `Loading`).
- One `*Route.kt` — `@Serializable data class FooRoute(...) : NavKey` — **public** (the app/back stack pushes it).
- One `*NavEntry.kt` — **public** `fun EntryProviderBuilder<NavKey>.addFooEntries(onNavigateBack: () -> Unit, ...)` containing `entry<FooRoute> { FooScreen(...) }`. The feature's only screen-facing public API.
- One `*Module.kt` — **public** Koin module exposing the ViewModel via `viewModelOf(::FooViewModel)` (resolves the `internal` VM; legal because it's the same module).
- `commonTest/FooViewModelTest.kt` with `ContainerHost.test()` and `FooState.Initial`.
- Feature-owned analytics: any analytics events specific to this feature live in the feature module (e.g. `FooAnalytics.kt` with named event constants + a thin wrapper around an injected analytics client). Cross-feature analytics interfaces live in `:domain` or a shared `:analytics` module if it grows. Don't centralize all events in `:shared`.
- Feature-owned navigation contribution: the feature exposes `addFooEntries(...)` (and its `FooRoute`) for the app to compose into `NavDisplay`'s `entryProvider { }`. Outgoing navigation is passed in as callbacks so the feature stays decoupled — the app owns the back stack and any target routes; a feature never imports another feature's Route.

### `:shared` (composition host) + `:androidApp` / `:desktopApp` / `iosApp`
- `App.kt` in `:shared/commonMain` — composes `AppTheme {}`, owns the back stack, and builds the nav graph by calling each feature's `addFooEntries(...)` inside `NavDisplay(entryProvider = entryProvider { ... })`. The app supplies cross-feature navigation as callbacks (e.g. `onOpenPhoto = { backStack.add(PhotoDetailRoute(it)) }`) — this is the one place that knows about more than one feature's routes.
- `startKoin` bootstrap in `:shared` pulling in `domainModule + dataModule + uiModule + every featureModule`; each platform entry point invokes it.
- `AppBuildConfig` (generated build config) + crash-reporter / Sentry init (when opted in, before `App()`) live in `:shared`.
- The per-platform **entry points are thin and live in the app modules**: `MainActivity` in `:androidApp`, `main()` in `:desktopApp`, `MainViewController` + the Xcode project in `iosApp/` — each just renders `:shared`'s `App()`.

## Visibility

Be deliberately restrictive: declare everything **`private`**, widen to **`internal`** when another file in the same module needs it, and reach for **`public`** (the Kotlin default) only for a module's intentional cross-module API. A `public` declaration with no consumer outside its module is a leak — tighten it. The payoff is that each module's real contract is small and obvious, and refactors inside a module never ripple outward.

Per-layer rules the agents and templates enforce:

| Layer | Public (cross-module API) | `internal` / `private` |
|---|---|---|
| `:domain` | Use case classes (+ public ctor — feature tests build them with fakes), entities, repository **interfaces**, `DomainError`, `DispatcherProvider` | helpers, mappers, impl details |
| `:data` | the Koin `dataModule` | repository **implementations**, data sources, DTOs, `RealDispatcherProvider` — all `internal` |
| `:feature-*` | `Route`, Koin `Module`, `addFooEntries(...)` | `Screen`/`ViewModel`/`State` are `internal`; `Content` is `private` |

Two companion rules that go hand-in-hand with visibility:

- **No default values on domain entities or presentation `State`.** Construct them explicitly. Defaults hide intent at call sites and silently swallow newly-added fields. Presentation `State` carries its starting value in a `companion object { val Initial = ... }` (one source of truth for `container(...)` and tests), not in constructor defaults. (DTOs in `:data` may keep defaults where the wire format needs them.)
- **Use-case constructors stay public** even though everything around them tightens — a `:feature-*` test must be able to build a real use case with a fake repository (`GetX(FakeRepo(), TestDispatcherProvider())`), which a cross-module `internal` constructor would forbid. In production a use case is still only constructed by `domainModule` via Koin.

## When to extract a new shared module

Defaults are enough for projects up to ~10 features. Extract when:

- **`:designsystem`** splits off `:ui` when design tokens grow beyond ~5 files or you start versioning the design system independently.
- **`:auth`** splits off `:domain` + `:data` when auth state needs its own lifecycle distinct from feature ViewModels (e.g. global token refresh, session listeners).
- **`:network`** splits off `:data` when network configuration (Ktor client + interceptors + Sentry hooks + retry policy) grows beyond a single file.
- **`:persistence`** splits off `:data` when you have multiple SQLDelight databases or share a single database across many repos.

Add via `/kmp-forge-add-module <name>`. New modules follow the same dependency rules (pure-Kotlin or Compose-aware as appropriate).

## ViewModel + Orbit pattern (state-only)

```kotlin
internal data class GalleryState(
    val loading: Boolean,
    val photos: List<Photo>,
    val error: DomainError?,

    // Consumable event slots — set inside intent {}, cleared by paired onXxxConsumed().
    val pendingNavigation: PhotoDetailRoute?,
    val pendingMessage: String?,
) {
    companion object {
        // Single starting-state source — used by container(...) and by tests.
        // No constructor defaults: every field is explicit here.
        val Initial = GalleryState(
            loading = false,
            photos = emptyList(),
            error = null,
            pendingNavigation = null,
            pendingMessage = null,
        )
    }
}

internal class GalleryViewModel(
    private val getPhotos: GetPhotosUseCase,
) : ViewModel(), ContainerHost<GalleryState, Nothing> {

    override val container = container<GalleryState, Nothing>(GalleryState.Initial)

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
internal sealed interface GalleryState {
    data object Loading : GalleryState
    data class Loaded(val photos: List<Photo>, val pendingNavigation: Route?) : GalleryState
    data class Error(val cause: DomainError) : GalleryState
}
// container(GalleryState.Loading)  — the initial state is an explicit object, not a no-arg ctor.
```

No constructor defaults here either — the starting state is an explicit object (`GalleryState.Loading`). UI matches on the sealed branch with a `when`. Default to flat data class — only promote when the flat shape grows boolean spaghetti (`if (loading && !error && photos.isEmpty()) ...`).

## Navigation wiring (Nav 3 entry contributions)

The app does **not** reference feature screens. Each feature exposes a public
`EntryProviderBuilder<NavKey>.addFooEntries(...)` extension (in `FooNavEntry.kt`)
that contributes its `entry<FooRoute> { FooScreen(...) }`; the app composes those
into `NavDisplay`'s `entryProvider { }`. This is what lets `FooScreen`/`FooViewModel`/`FooState`
stay `internal` — the only screen-facing public symbol a feature exports is the
entry contribution.

```kotlin
// :feature-gallery — the feature's only screen-facing public API
fun EntryProviderBuilder<NavKey>.addGalleryEntries(
    onNavigateBack: () -> Unit,
    onOpenPhoto: (PhotoId) -> Unit,   // outgoing nav as a callback — no cross-feature import
) {
    entry<GalleryRoute> { GalleryScreen(onNavigateBack = onNavigateBack, onOpenPhoto = onOpenPhoto) }
}

// :shared (App.kt) — owns the back stack and every target route
val backStack = rememberNavBackStack(GalleryRoute)
NavDisplay(
    backStack = backStack,
    entryProvider = entryProvider {
        addGalleryEntries(
            onNavigateBack = { backStack.removeLastOrNull() },
            onOpenPhoto = { backStack.add(PhotoDetailRoute(it)) },
        )
        addPhotoDetailEntries(onNavigateBack = { backStack.removeLastOrNull() })
    },
)
```

Cross-feature navigation flows through these callbacks, so a feature never depends
on another feature: `:feature-gallery` knows nothing about `PhotoDetailRoute` — the
app wires `onOpenPhoto`. Adding a screen to an existing feature means adding another
`entry<...> { ... }` line inside that feature's `addFooEntries`.

## Hybrid architecture rationale

Pure feature-first (every feature has its own `:presentation`, `:domain`, `:data`) creates module sprawl in small projects: a 5-feature app gets 15 modules. Pure layer-first (top-level `:presentation`, `:domain`, `:data` containing all features) makes "feature" a non-boundary — deleting a feature touches every layer.

Hybrid keeps the dominant code volume (UI + state) encapsulated per feature while keeping business logic and data centralized where cross-feature sharing is natural. Trade-off: a feature's domain logic is not private — it lives in the shared `:domain` module. Use package boundaries within `:domain` to keep features readable (`com.app.domain.gallery.*`).
