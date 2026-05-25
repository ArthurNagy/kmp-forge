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
:domain     ──▶ (nothing internal — pure Kotlin + Coroutines + kotlinx-datetime + kotlinx-serialization)
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

### `:data`
- Repository **implementations** (`UserRepositoryImpl`)
- Data sources: `UserRemoteDataSource` (Ktor), `UserLocalDataSource` (DataStore/SQLDelight)
- DTOs (`UserDto`) + mappers (`UserDto.toDomain()`)
- Koin module exposing implementations bound to `:domain` interfaces.

### `:ui`
- `AppTheme {}` wrapper around `MaterialTheme`
- Design tokens: `AppColors`, `AppType`, `AppSpacing`, `AppDimens` as Kotlin objects
- Reusable Composables (buttons, cards, dialogs) — strictly stateless, hoisted-state pattern
- Compose Multiplatform Resources (`Res.string`, `Res.drawable`)

### `:feature-<name>`
- One `*Screen.kt` per screen — stateless, takes state + lambdas
- One `*ViewModel.kt` per screen — `class FooViewModel(private val useCase: ...) : ViewModel(), ContainerHost<FooState, FooEffect>`
- One `*State.kt` sealed file with `data class FooState(...)` and `sealed interface FooEffect`
- One `*Destination.kt` — `@Serializable data class FooRoute(...) : NavKey` plus an extension hooking it into the back stack
- One `*Module.kt` — Koin module exposing the ViewModel via `viewModelOf(::FooViewModel)`
- `commonTest/FooViewModelTest.kt` with `ContainerHost.test()`

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

## ViewModel + Orbit pattern

```kotlin
class GalleryViewModel(
    private val getPhotos: GetPhotosUseCase,
    private val dispatchers: DispatcherProvider,
) : ViewModel(), ContainerHost<GalleryState, GalleryEffect> {

    override val container = container<GalleryState, GalleryEffect>(GalleryState())

    fun load() = intent {
        reduce { state.copy(loading = true) }
        getPhotos()
            .onSuccess { photos -> reduce { state.copy(loading = false, photos = photos) } }
            .onFailure { error -> reduce { state.copy(loading = false, error = error) } }
    }

    fun openPhoto(id: PhotoId) = intent {
        postSideEffect(GalleryEffect.NavigateToDetail(id))
    }
}
```

- ViewModel never references `Dispatchers.IO` directly — use `dispatchers.io` from `DispatcherProvider`.
- Use case returns `Result<T, DomainError>`. ViewModel uses `onSuccess` / `onFailure` and updates state.
- One-shot events (navigation, toasts) flow via `postSideEffect` to `GalleryEffect`, never via state.

## Hybrid architecture rationale

Pure feature-first (every feature has its own `:presentation`, `:domain`, `:data`) creates module sprawl in small projects: a 5-feature app gets 15 modules. Pure layer-first (top-level `:presentation`, `:domain`, `:data` containing all features) makes "feature" a non-boundary — deleting a feature touches every layer.

Hybrid keeps the dominant code volume (UI + state) encapsulated per feature while keeping business logic and data centralized where cross-feature sharing is natural. Trade-off: a feature's domain logic is not private — it lives in the shared `:domain` module. Use package boundaries within `:domain` to keep features readable (`com.app.domain.gallery.*`).
