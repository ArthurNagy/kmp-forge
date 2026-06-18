# Stack

Every locked library, why it was chosen, when it's used, and idiomatic usage.

## Always included

### Kotlin Multiplatform + Compose Multiplatform
The foundation. Compose Multiplatform 1.10+ for Material 3 + multi-platform UI.

### Orbit MVI
- **Why**: explicit MVI shape (intent → reduce → state), built-in `ContainerHost.test()` harness, KMP-ready.
- **Where**: every ViewModel in every `:feature-*` module.
- **Idiom**: `internal class FooViewModel : ViewModel(), ContainerHost<FooState, Nothing> { override val container = container(FooState.Initial); fun load() = intent { reduce { state.copy(...) } } }`. State is `internal`, has no constructor defaults, and exposes its starting value as `FooState.Initial` (see [architecture.md § Visibility](architecture.md#visibility)).
- **State-only events** (no `postSideEffect`): one-shot events live as consumable state slots (`pendingNavigation: Route?`, `pendingMessage: String?`). UI observes via `LaunchedEffect`, consumes, calls paired `onXxxConsumed()` intent to clear. Rationale: everything is state — easier to test, easier to inspect, robust across config changes / process death.
- **Sub-states via sealed interface** when a flat data class overcomplicates state management (mutually-exclusive page-level transitions like `Loading | Loaded | Error`). See [architecture.md](architecture.md#sub-states-via-sealed-interface).
- **Anti-patterns**: mutating state outside `intent {}`; using `postSideEffect` (effect type is `Nothing`); throwing exceptions inside `intent {}` blocks (let use cases return `Result`); page-level sub-states modeled as booleans on a flat data class (promote to sealed interface).

### Koin
- **Why**: pure-Kotlin DI, KMP-native, runtime registration, low ceremony, easy to test.
- **Where**: each module exposes a `<moduleName>Module: Module`. `:composeApp` calls `startKoin { modules(domainModule, dataModule, uiModule, featureGalleryModule, ...) }` in the platform entry point.
- **Idiom**: `val galleryModule = module { viewModelOf(::GalleryViewModel) }`; in Composables, `val vm = koinViewModel<GalleryViewModel>()`.
- **Anti-patterns**: global service locator calls (`GlobalContext.get()`); constructing classes directly inside ViewModels instead of injecting.
- **Note**: Hilt is Android-only and cannot live in `commonMain` — Koin is the right call for any KMP project.

### Navigation 3 (Compose Multiplatform)
- **Why**: official Compose Navigation library with first-class KMP support since Compose MP 1.10. User-owned back stack as `SnapshotStateList<NavKey>`.
- **Where**: every screen defines a `@Serializable data class FooRoute(...) : NavKey` (public). The app-level back stack is constructed with `rememberNavBackStack(RootRoute)` and rendered via `NavDisplay`. Each feature contributes its screens through a public `addFooEntries(...)` entry-provider extension — the app never references `FooScreen` directly, which keeps screens/VMs/state `internal` (see [architecture.md § Navigation wiring](architecture.md#navigation-wiring-nav-3-entry-contributions)).
- **Idiom**:
  ```kotlin
  @Serializable data object GalleryRoute : NavKey
  @Serializable data class PhotoDetailRoute(val id: String) : NavKey

  // :feature-gallery — the feature's only screen-facing public symbol
  fun EntryProviderBuilder<NavKey>.addGalleryEntries(
      onOpenPhoto: (String) -> Unit,
      onNavigateBack: () -> Unit,
  ) {
      entry<GalleryRoute> { GalleryScreen(onOpenPhoto = onOpenPhoto, onNavigateBack = onNavigateBack) }
  }

  // :composeApp — owns the back stack and every target route
  val backStack = rememberNavBackStack(GalleryRoute)
  NavDisplay(
      backStack = backStack,
      entryProvider = entryProvider {
          addGalleryEntries(
              onOpenPhoto = { backStack.add(PhotoDetailRoute(it)) },
              onNavigateBack = { backStack.removeLastOrNull() },
          )
          addPhotoDetailEntries(onNavigateBack = { backStack.removeLastOrNull() })
      },
  )
  ```
- **Anti-patterns**: untyped routes (string keys); the app referencing a feature's `Screen`/`ViewModel` directly instead of its `addFooEntries(...)` contribution; a feature importing another feature's Route (pass outgoing nav as a callback instead); mutating the back stack from outside Composition; using `postSideEffect` for navigation (effect type is `Nothing`) — instead set a consumable `pendingNavigation: Route?` slot inside `intent {}` and mutate the back stack in a `LaunchedEffect` observing it.
- **Artifact**: `org.jetbrains.androidx.navigation3:navigation3-ui:1.1.1` (the JetBrains Compose Multiplatform port — Google's `androidx.navigation3:navigation3-ui` is Android/JVM-only and won't resolve in `commonMain` on iOS/web) plus `androidx.navigation3:navigation3-runtime:1.1.1` (Google's runtime *is* a true KMP artifact and is exactly what the UI port depends on, so both share the one `androidxNavigation3` version ref).

### Coil 3
- **Why**: KMP-native image loader, Compose integration, pluggable fetchers (Ktor when HTTP is on), shared memory + disk cache.
- **Where**: `AsyncImage(model = url, contentDescription = ...)` anywhere an image is rendered.
- **Idiom**: configure once via `SingletonImageLoader.setSafe { context -> ImageLoader.Builder(context).components { add(KtorNetworkFetcherFactory()) }.build() }`.
- **Anti-patterns**: per-screen `ImageLoader` instances; loading images on the main thread.

### KotlinX Serialization
- **Why**: required for Navigation 3 `@Serializable` routes; standard for any JSON.
- **Where**: every Nav 3 route data class; every DTO in `:data`.
- **Idiom**: `@Serializable data class UserDto(val id: String, val name: String)`.

### KotlinX Coroutines
- **Why**: standard async primitive.
- **Where**: every suspending boundary; Flow for reactive streams.
- **Anti-patterns**: `Dispatchers.IO` referenced directly in ViewModels or repos — use `DispatcherProvider` instead.

### kotlin-result (Result + DomainError)
- **Why**: a two-parameter `Result<V, E>` makes each use case's failure modes explicit in its signature, without Arrow's weight. Kotlin's stdlib `Result<T>` is single-param with a `Throwable`-only failure and can't carry a typed `DomainError`.
- **Where**: every use case returns `Result<T, DomainError>`; ViewModels consume it with `onSuccess`/`onFailure`; repositories return it from `:data`.
- **Coordinates**: Gradle `com.michael-bull.kotlin-result:kotlin-result` (+ `kotlin-result-coroutines` for `coroutineBinding`). Kotlin import package is `com.github.michaelbull.result.*` — **note the coordinate and package differ**. Declared `api` in `:domain` so it flows transitively to `:data`/`:feature-*`.
- **Idiom**: `repo.find(id)?.let { Ok(it) } ?: Err(UserError.NotFound)`; consume with `result.onSuccess { ... }.onFailure { ... }` or `result.fold(success = { ... }, failure = { ... })`. Multi-step: `coroutineBinding { val a = stepA().bind(); val b = stepB(a).bind(); b }`.
- **Anti-patterns**: importing `kotlin.Result` / using `runCatching` (returns the stdlib type — shadows this one); making `DomainError` extend `Throwable`; careless `.get()!!` / `unwrap()` instead of `fold`/`onSuccess`/`onFailure`/`getOrElse`.

### kotlinx-datetime
- **Why**: KMP-native date/time primitives (`Instant`, `LocalDate`, `Clock`).
- **Where**: any timestamp-aware code.
- **Anti-pattern**: `java.time` in `commonMain` (JVM-only).

### Kermit
- **Why**: KMP logger with severity, multi-target sinks (println/NSLog/logcat), plugs into Crashlytics/Sentry as a sink.
- **Where**: `Logger.d { "..." }` / `Logger.e(throwable) { "..." }` throughout.
- **Idiom**: `Logger.setTag("FooFeature")` at module init.
- **Sink wiring**: when Sentry is opted in, add `SentryLogWriter()` to Kermit's writers at app startup. ERROR+ logs become Sentry breadcrumbs.

### Compose Multiplatform Resources
- **Why**: type-safe, KMP-native string/drawable/font handling.
- **Where**: `commonMain/composeResources/values-<locale>/strings.xml`; accessed via `stringResource(Res.string.foo)`.
- **Anti-pattern**: hardcoded strings in `Text(...)` — every user-facing string goes through `Res.string`.

### DataStore (KMP)
- **Why**: key-value preferences with KMP support, coroutine + Flow API.
- **Where**: any small structured preference state (theme override, feature flags, onboarding state).
- **Idiom**:
  ```kotlin
  val themeMode: Flow<ThemeMode> = dataStore.data.map { it[KEY_THEME]?.let(ThemeMode::valueOf) ?: ThemeMode.SYSTEM }
  suspend fun setThemeMode(mode: ThemeMode) { dataStore.edit { it[KEY_THEME] = mode.name } }
  ```

## Opt-in libraries

### Ktor Client
- **When**: project needs HTTP.
- **Engines**: Darwin (iOS), OkHttp (Android), Java (desktop), JS (web).
- **Idiom**: provide `HttpClient` via Koin with `install(ContentNegotiation) { json() }`, `install(Logging) { logger = KermitKtorLogger }`.

### SQLDelight
- **When**: project needs relational storage. Choose over Exposed for mobile-first KMP work (mobile-proven, lightweight drivers, type-safe SQL from `.sq` files).
- **Where**: `:data` module. Drivers per platform via `expect/actual`.
- **Idiom**: SQL in `.sq` files; generated `Database` class accessed via Koin singleton.

### Store (MobileNativeFoundation/Store)
- **When**: offline-first repository with multiple backing sources (remote + cache + db). Common in feeds, lists, profile data — anywhere you want SWR-style staleness behavior with fallback to local.
- **Where**: `:data` module. One `Store<Key, Value>` per data type.
- **Idiom**:
  ```kotlin
  val userStore: Store<UserId, User> = StoreBuilder
      .from(
          fetcher = Fetcher.of { id -> api.getUser(id).toDomain() },
          sourceOfTruth = SourceOfTruth.of(
              reader = { id -> db.userQueries.byId(id).asFlow().mapToOneOrNull() },
              writer = { id, user -> db.userQueries.upsert(user.toEntity()) },
          ),
      )
      .build()
  ```
- **Why over a hand-rolled repo**: builds in stale-while-revalidate, error handling, and Flow-based reactivity. Worth it once a feature has both network + db sources.
- **Anti-pattern**: using Store for single-source data (only network, only db) — direct repo is simpler.

### Sentry
- **When**: opt into observability beyond Play Vitals / App Store Connect Crashes.
- **Artifact**: `io.sentry:sentry-kotlin-multiplatform`.
- **Init**: in `:composeApp` platform entry points, before Koin start:
  ```kotlin
  Sentry.init { options ->
      options.dsn = BuildConfig.SENTRY_DSN
      options.environment = if (BuildConfig.DEBUG) "debug" else "release"
  }
  ```
- **Kermit sink**: add `SentryLogWriter(minSeverity = Severity.Error)` to Kermit at startup.

### Firebase App Distribution (Android, iOS)
- **When**: shipping beta builds to testers before App Store / Play submission.
- **Wiring**: Android — `firebaseAppDistribution` Gradle plugin. iOS — `firebase appdistribution:distribute` CLI in `release.yml`.

### gradle-play-publisher
- **When**: graduating to Play Store releases.
- **Why over fastlane**: pure Gradle plugin, no Ruby toolchain.
- **Idiom**: `./gradlew publishReleaseBundle --track=internal` (or `alpha`/`beta`/`production`).

## Excluded by default

- **Image picker** (Peekaboo, FileKit, etc): no consistent app-wide need; add per-project when a feature needs media.
- **Fastlane**: Ruby overhead. Use `gradle-play-publisher` + Apple CLI tools. Add fastlane only when project specifically needs metadata + screenshot management.
- **Analytics + performance monitoring**: opt-in per project.
- **MockK** in `commonTest`: MockK is JVM-only. Allowed in `jvmTest`/`androidTest` for platform/third-party dep mocks. `commonTest` uses fakes.

## Version policy

Versions tracked in `gradle/libs.versions.toml`. Manual refresh via `/kmp-forge-bump-stack` (no Dependabot/Renovate). Reviewer reads each diff for breaking changes before commit.
