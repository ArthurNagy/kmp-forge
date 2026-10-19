---
name: data-layer
description: Write or change code in a kmp-forge project's :data module — internal repository implementations bound to :domain interfaces, data sources (Ktor HTTP, small preferences via a KeyValueStore or DataStore, SQLDelight, Store), DTOs and mappers, the exception boundary where every failure becomes a DomainError (catchNetwork-style helpers that rethrow cancellation), per-platform expect/actual pieces and their Koin module, dataModule bindings, and repository tests with fakes and MockEngine. Use when implementing a repository, adding an API call, a stored preference, a table or a cache, wiring a platform-specific dependency, or when an OpenSpec task touches :data.
---

# :data — kmp-forge style

`:data` implements the repository interfaces `:domain` declares. It is the only module that talks to the network, the disk or platform storage, and the only place exceptions are allowed to exist: **data sources may throw, repositories never do — every failure leaves as a `DomainError`.** Canonical rules: the plugin's [architecture.md](../../docs/architecture.md) (§ `:data`, § Visibility), [stack.md](../../docs/stack.md) (Ktor, DataStore, SQLDelight, Store) and [testing.md](../../docs/testing.md). The domain side of a slice (entities, `DomainError` cases, the interface) comes first; see the `domain-layer` skill.

## Shape

```
data/src/commonMain/kotlin/<base>/data/
  dataModule.kt                 the one public declaration in :data
  PlatformDataModule.kt         internal expect val platformDataModule (when a platform piece exists)
  CatchNetwork.kt               the boundary helper(s) — exceptions → DomainError
  RealDispatcherProvider.kt     (+ RealDispatcherProvider.<platform>.kt actuals)
  photo/
    PhotoDto.kt                 internal @Serializable wire shape + toDomain()
    PhotoRemoteDataSource.kt    internal interface + its Ktor implementation
    PhotoRepositoryImpl.kt      internal class PhotoRepositoryImpl : PhotoRepository
```

- **Everything is `internal` except `dataModule`.** The rest of the app sees only the `:domain` interface. Binding an internal implementation works because `dataModule` is in the same module.
- One repository **and one data source** per domain type, as in `:domain`.
- Depends on `:domain` plus the KMP libraries it needs. Never on `:ui` or a `:feature-*`.

## Recipe: implement a repository

### 1. DTOs and mappers

```kotlin
@Serializable
internal data class PhotoDto(
    val id: String,
    val title: String,
    val description: String? = null,                 // the API omits it when empty
    @SerialName("is_favorite") val favorite: Boolean = false,
)

internal fun PhotoDto.toDomain(): Photo = Photo(
    id = PhotoId(id),
    title = title,
    description = description,
    favorite = favorite,
)
```

- A DTO mirrors the wire format and never leaves `:data`. It is the one place default values are fine, where the API omits fields.
- Mappers are `internal` extensions next to the DTO (or a small `internal object …Parser` for XML / binary formats), with their own tests when they do real work.

### 2. Data sources

Put each data source behind an `internal interface` so the repository can be tested against a fake. A data source is a thin wrapper over one library: it speaks DTOs and **may throw**. HTTP status is its job — it returns a value for statuses that mean something and fails on the rest:

```kotlin
internal interface PhotoRemoteDataSource {
    suspend fun photos(): List<PhotoDto>
    suspend fun photo(id: String): PhotoDto?          // null: the server says it doesn't exist
}

internal class KtorPhotoRemoteDataSource(private val client: HttpClient) : PhotoRemoteDataSource {
    override suspend fun photos(): List<PhotoDto> {
        val response = client.get("photos")
        check(response.status.isSuccess()) { "HTTP ${response.status.value} for photos" }
        return response.body()
    }

    override suspend fun photo(id: String): PhotoDto? {
        val response = client.get("photos/$id")
        if (response.status == HttpStatusCode.NotFound) return null      // an answer, not a failure
        check(response.status.isSuccess()) { "HTTP ${response.status.value} for photos/$id" }
        return response.body()
    }
}
```

**Ktor.** Use one client: `createHttpClient()` (from the overlay), bound once as `single { createHttpClient() }`. Its engine-independent setup lives in `HttpClientConfig<*>.configureDefaults()`: base URL, auth, timeouts (`HttpTimeout`), logging. Tests build the same setup over a fake engine. When the app talks to services with different needs (a serial device next to a REST API), give each its own client behind a Koin qualifier (`single(named("media")) { … }`) and keep the shared setup in config extensions. Engine tuning that needs the platform (Android `Network` binding, OkHttp dispatchers) goes in the platform module. Secrets come from the environment and build config, never from source ([secrets.md](../../docs/secrets.md)).

**Small preferences: pick by how they're read.**
- **A few plain values read on demand** (an install id, a remembered choice): a `KeyValueStore`. Use a tiny interface, a platform implementation each, and an in-memory fake for tests:
  ```kotlin
  internal interface KeyValueStore {
      fun get(key: String): String?
      fun put(key: String, value: String)
  }
  // androidMain: SharedPreferences (context.getSharedPreferences(…, Context.MODE_PRIVATE)); iosMain: NSUserDefaults;
  // jvmMain: java.util.prefs.Preferences; webMain: localStorage. Bound in platformDataModule.
  ```
- **Values the UI observes, or structured state** (a theme the app re-renders on, settings screens): DataStore, as one Koin `single` **per file**. A second instance on the same file throws on first use. Read it with a flow that can't throw:
  ```kotlin
  override val themeMode: Flow<String?> = store.data
      .catch { e -> if (e is okio.IOException) emit(emptyPreferences()) else throw e }   // unreadable file → defaults
      .map { it[THEME_MODE] }
  ```
  DataStore throws **okio's** `IOException`. On iOS that is a different class from Ktor's `kotlinx.io.IOException`, so check the type of the library you call. DataStore 1.2 has no `js` target, so on web use the `KeyValueStore` route.

**SQLDelight.** SQL goes in `data/src/commonMain/sqldelight/<base-path>/data/db/*.sq`. The generated `AppDatabase` is a Koin `single` built from an `internal expect class DriverFactory { fun create(): SqlDriver }` (see *Platform pieces*). Observe with `query.asFlow().mapToList(dispatchers.io)` (`sqldelight-coroutines`), and write multi-row changes in one `transactionWithResult { }`. Once a schema version has shipped, every change needs a numbered `.sqm` migration.

**Store** (`store5`) only when a type has two or more sources, such as remote + database with stale-while-revalidate: one `Store<Key, Value>` per type ([stack.md § Store](../../docs/stack.md#store-mobilenativefoundationstore)). Single-source data uses a plain repository.

### 3. The repository: where exceptions become `DomainError`

One small boundary helper per kind of source, shared by the area's repositories:

```kotlin
// CatchNetwork.kt
/**
 * Runs [block], turning any failure into [DomainError.Network]. Rethrows [CancellationException] so coroutine
 * cancellation propagates (kotlin-result's runCatching would otherwise swallow it).
 */
internal inline fun <T> catchNetwork(block: () -> T): Result<T, DomainError> =
    runCatching(block).mapError { e ->
        if (e is CancellationException) throw e
        Logger.w(e) { "network call failed" }
        DomainError.Network(e.message)
    }
```

```kotlin
internal class PhotoRepositoryImpl(
    private val remote: PhotoRemoteDataSource,
    private val dispatchers: DispatcherProvider,
) : PhotoRepository {

    override suspend fun photos(): Result<List<Photo>, DomainError> =
        withContext(dispatchers.io) {
            catchNetwork { remote.photos() }.map { dtos -> dtos.map { it.toDomain() } }
        }

    override suspend fun photo(id: PhotoId): Result<Photo, DomainError> =
        withContext(dispatchers.io) {
            catchNetwork { remote.photo(id.value) }
                .toErrorIfNull { DomainError.NotFound }
                .map { it.toDomain() }
        }

    // setFavorite(…) and favorites() follow the same pattern.
}
```

- **Every call to a data source goes through a helper.** Nothing a library throws reaches `:domain`. One helper per kind of failure: `catchNetwork` maps to `Network(cause)`. A parser or storage helper (`runCatching { parser.parse(bytes) }.mapError { … DomainError.Unknown(it.message) }`) maps to `Unknown(cause)`, or to a case the app added. Statuses and answers that mean something were already decided in the data source (404 → `null` → `NotFound`).
- It is **kotlin-result's** `runCatching` (`import com.github.michaelbull.result.runCatching`, returns `Result<V, Throwable>`), never the stdlib's. Its `mapError` **rethrows `CancellationException` first, always**: otherwise a cancelled screen's call comes back as an error instead of stopping. Because there is no `catch` clause, detekt's `TooGenericExceptionCaught` doesn't apply. Don't hand-roll `catch (e: Exception)` to do the same job.
- When a failure is a *value* rather than an error (a probe that answers `null`, a retry loop that keeps the last failure), write a `try`/`catch` that rethrows `CancellationException` first, with `@Suppress("TooGenericExceptionCaught")` and a comment saying why every failure means the same thing there:
  ```kotlin
  @Suppress("TooGenericExceptionCaught") // any transport failure means "no answer" for the keepalive
  private suspend fun ping(): Reply? = try {
      client.ping()
  } catch (e: CancellationException) {
      throw e
  } catch (e: Exception) {
      log.d { "ping failed: ${e::class.simpleName}: ${e.message}" }
      null
  }
  ```
- I/O runs on `dispatchers.io` from the injected `DispatcherProvider`, CPU-heavy parsing on `dispatchers.default`. Never `Dispatchers.*`: only `RealDispatcherProvider` and its actuals name dispatchers.
- Streams (`Flow` / `StateFlow`) never throw: `.catch { }` inside the flow, or publish the failure in the emitted state (`error: DomainError?`).
- A `cause` is the exception message, kept for logs. The UI never shows it.

### 4. Wire it

```kotlin
val dataModule = module {
    includes(platformDataModule)                                    // only when platform pieces exist
    singleOf(::RealDispatcherProvider) bind DispatcherProvider::class
    single { createHttpClient() }
    singleOf(::KtorPhotoRemoteDataSource) bind PhotoRemoteDataSource::class
    singleOf(::PhotoRepositoryImpl) bind PhotoRepository::class
}
```

Repositories, data sources, clients and databases are `single`s. Constructor injection only. Work that must outlive a screen (a transfer, a session keepalive) gets an injected application-lifetime scope, `single { CoroutineScope(SupervisorJob() + get<DispatcherProvider>().default) }`, never a scope the repository creates and never cancels.

### Platform pieces (expect/actual + one Koin module)

Anything built differently per platform (a `KeyValueStore`, a DataStore file path, a SQLDelight driver, an OS service) gets a common `expect` plus an `internal expect val platformDataModule: Module` that `dataModule` includes. Write an actual for **every target the module builds**, or the build fails on the missing one: `androidMain` always, `jvmMain` for `jvm`, `nativeMain` for iOS, `webMain` for `js`/`wasmJs`. The targets are `kmpForge.targets` in `gradle.properties`.

```kotlin
// commonMain
internal expect val platformDataModule: Module

// androidMain: the app registers its Context when Koin starts at launch (initKoin(context)).
// Resolve it in the definition, never inside a lambda that runs later.
internal actual val platformDataModule: Module = module {
    single<KeyValueStore> { SharedPreferencesKeyValueStore(context = get()) }
}

// nativeMain (iOS)
internal actual val platformDataModule: Module = module {
    single<KeyValueStore> { UserDefaultsKeyValueStore() }
}
```

A DataStore file path per platform works the same way: `PreferenceDataStoreFactory.createWithPath(produceFile = { path.toPath() })`, with `context.filesDir` on Android, `NSFileManager`'s document directory on iOS (`@OptIn(ExperimentalForeignApi::class)`), and a per-user app directory on desktop. The file name must end in `.preferences_pb`.

## Tests

`data/src/commonTest/`: test the repository against **fake data sources**. `commonTest` sees `internal` declarations, so the fakes stay `internal` and module-local. Cover the success mapping and **every error the repository can return**.

```kotlin
internal class FakePhotoRemoteDataSource : PhotoRemoteDataSource {
    var photos: List<PhotoDto> = emptyList()
    var failWith: Throwable? = null
    override suspend fun photos(): List<PhotoDto> = failWith?.let { throw it } ?: photos
    override suspend fun photo(id: String): PhotoDto? = failWith?.let { throw it } ?: photos.firstOrNull { it.id == id }
}

class PhotoRepositoryImplTest {
    @Test
    fun mapsATransportFailureToNetwork() = runTest {
        val remote = FakePhotoRemoteDataSource().apply { failWith = IllegalStateException("HTTP 500 for photos") }
        val repo = PhotoRepositoryImpl(remote, TestDispatcherProvider(testScheduler))

        assertEquals(Err(DomainError.Network("HTTP 500 for photos")), repo.photos())
    }
}
```

- **Cancellation, once per helper:** a data source that throws `CancellationException` must make the repository call throw it too (`assertFailsWith<CancellationException>`), not return an `Err`.
- **The Ktor data source and the status handling:** build the production setup over Ktor's multiplatform fake engine, `HttpClient(MockEngine { respond(content = "…", status = HttpStatusCode.NotFound, headers = headersOf(HttpHeaders.ContentType, "application/json")) }) { configureDefaults() }`. Then check 404 → `NotFound`, 5xx → `Network`, a malformed or non-JSON body → `Network`. Init adds `libs.ktor.client.mock` to `:data`'s `commonTest` when Ktor is selected; older projects add it from the catalog. MockK stays out of `commonTest`.
- **Preferences:** an in-memory `KeyValueStore` (a `mutableMapOf` behind the interface), or for DataStore an in-memory store:
  ```kotlin
  private class FakePreferencesDataStore : DataStore<Preferences> {
      val state = MutableStateFlow(emptyPreferences())
      var readFailure: Throwable? = null

      override val data: Flow<Preferences> = flow {
          readFailure?.let { throw it }
          emitAll(state)
      }

      override suspend fun updateData(transform: suspend (t: Preferences) -> Preferences): Preferences =
          transform(state.value).also { state.value = it }
  }
  ```
- Mappers and parsers with real logic get their own tests, fed with captured fixtures.
- Never touch the real network or disk in `commonTest`.

## Before you hand it on

- Nothing in `:data` is public except `dataModule`. No DTO, `HttpResponse` or `Preferences` appears in a `:domain` signature.
- No exception escapes a repository: every data-source call goes through a boundary helper that rethrows `CancellationException` first, each broad `try/catch` carries its reason, and flows `.catch`.
- No `Dispatchers.*` outside `RealDispatcherProvider`. Every `expect` has an actual on every target.
- Each new repository or data source is bound in `dataModule`, and its tests cover every error it can return plus cancellation.
- `./gradlew :data:jvmTest` while iterating. Before pushing, run `./gradlew spotlessApply` (the samples here are compact, and ktlint_official reflows signatures and comments), then the CI gate: `./gradlew spotlessCheck detekt build koverVerify`.
