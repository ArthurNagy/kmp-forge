# Stack

Every locked library, why it was chosen, when it's used, and idiomatic usage.

## Always included

### Kotlin Multiplatform + Compose Multiplatform
The foundation. Compose Multiplatform 1.10+ for Material 3 + multi-platform UI.

### Orbit MVI
- **Why**: explicit MVI shape (intent → reduce → state), built-in `ContainerHost.test()` harness, KMP-ready.
- **Where**: every ViewModel in every `:feature-*` module.
- **Idiom**: `class FooViewModel : ViewModel(), ContainerHost<FooState, Nothing> { override val container = container(FooState()); fun load() = intent { reduce { state.copy(...) } } }`
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
- **Where**: every screen defines a `@Serializable data class FooRoute(...) : NavKey`. App-level back stack constructed with `rememberNavBackStack(RootRoute)` and rendered via `NavDisplay`.
- **Idiom**:
  ```kotlin
  @Serializable data object GalleryListRoute : NavKey
  @Serializable data class PhotoDetailRoute(val id: String) : NavKey

  val backStack = rememberNavBackStack(GalleryListRoute)
  NavDisplay(backStack) { key ->
      when (key) {
          GalleryListRoute -> GalleryScreen(onOpen = { backStack.add(PhotoDetailRoute(it)) })
          is PhotoDetailRoute -> PhotoDetailScreen(id = key.id, onBack = { backStack.removeLastOrNull() })
      }
  }
  ```
- **Anti-patterns**: untyped routes (string keys); mutating the back stack from outside Composition (do it inside `intent {}` via `postSideEffect`).
- **Artifact**: `androidx.navigation3:navigation3-ui:1.1.2`, `androidx.navigation3:navigation3-runtime:1.1.2`.

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
