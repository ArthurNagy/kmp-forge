---
name: data-layer
description: Write or change code in a kmp-forge project's :data module — internal repository implementations bound to :domain interfaces, data sources (Ktor HTTP, small preferences via a KeyValueStore or DataStore, SQLDelight, Store), DTOs and mappers, the exception boundary where every failure becomes a DomainError (catchNetwork classifies connectivity / HTTP status / unknown and rethrows cancellation), per-platform expect/actual pieces and their Koin module, dataModule bindings, and repository tests with fakes and MockEngine. Use when implementing a repository, adding an API call, a stored preference, a table or a cache, wiring a platform-specific dependency, or when an OpenSpec task touches :data.
---

# :data — kmp-forge style

`:data` implements the repository interfaces `:domain` declares. It is the only module that talks to the network, the disk or platform storage, and the only place exceptions are allowed to exist: **data sources may throw, repositories never do — every failure leaves as a `DomainError`.** Canonical rules: the plugin's [architecture.md](../../docs/architecture.md) (§ `:data`, § Visibility), [stack.md](../../docs/stack.md) (Ktor, DataStore, SQLDelight, Store) and [testing.md](../../docs/testing.md). The domain side of a slice (entities, `DomainError` cases, the interface) comes first; see the `domain-layer` skill.

## Shape

```
data/src/commonMain/kotlin/<base>/data/
  dataModule.kt                 the one public declaration in :data
  PlatformDataModule.kt         internal expect val platformDataModule (when a platform piece exists)
  CatchNetwork.kt               the network boundary — exceptions → DomainError (Ktor opt-in, with tests)
  HttpStatusException.kt        HttpResponse.requireSuccess() and the exception it throws (Ktor opt-in)
  platform/                     platform `actual` adapters (KeyValueStore, DataStore / driver factories) — Kover-excluded glue
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
    suspend fun setFavorite(id: String, favorite: Boolean)
}

internal class KtorPhotoRemoteDataSource(private val client: HttpClient) : PhotoRemoteDataSource {
    override suspend fun photos(): List<PhotoDto> {
        val response = client.get("photos")
        response.requireSuccess()                                         // non-2xx → HttpStatusException
        return response.body()
    }

    override suspend fun photo(id: String): PhotoDto? {
        val response = client.get("photos/$id")
        if (response.status == HttpStatusCode.NotFound) return null      // an answer, not a failure
        response.requireSuccess()
        return response.body()
    }

    override suspend fun setFavorite(id: String, favorite: Boolean) {
        client.put("photos/$id") { parameter("favorite", favorite) }.requireSuccess()
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

  // androidMain, package <base>.data.platform — thin adapters there are platform glue, excluded from Kover
  internal class SharedPreferencesKeyValueStore(context: Context) : KeyValueStore {
      private val prefs = context.getSharedPreferences("app", Context.MODE_PRIVATE)
      override fun get(key: String): String? = prefs.getString(key, null)
      override fun put(key: String, value: String) = prefs.edit().putString(key, value).apply()
  }
  // iosMain: NSUserDefaults.standardUserDefaults (stringForKey / setObject); jvmMain: java.util.prefs.Preferences;
  // webMain: localStorage. Bound in platformDataModule.
  ```
  Keep the adapters this thin. The logic on top of a `KeyValueStore` stays in common code, tested with an in-memory fake.
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

The Ktor opt-in ships the network boundary, `CatchNetwork.kt`, with its tests:

```kotlin
internal suspend fun <T> catchNetwork(block: suspend () -> T): Result<T, DomainError> = runCatching { block() }.mapError { e ->
    if (e is CancellationException) throw e                   // cancellation must propagate, always first
    Logger.w(e) { "network call failed" }
    when (e) {
        is HttpStatusException -> DomainError.Network.Http(e.status, e.code)   // from response.requireSuccess()
        is IOException -> DomainError.Network.Connectivity                    // kotlinx.io: offline, DNS, timeouts
        else -> DomainError.Unknown(e.message)                                // e.g. a body that doesn't parse
    }
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

    override suspend fun setFavorite(id: PhotoId, favorite: Boolean): Result<Unit, DomainError> =
        withContext(dispatchers.io) {
            catchNetwork { remote.setFavorite(id.value, favorite) }
        }

    // favorites(): a stream the UI observes — back it with a MutableStateFlow the repository updates
    // after each successful photos() / setFavorite(), so it never throws.
}
```

- **Every call to a data source goes through a helper.** Nothing a library throws reaches `:domain`. `catchNetwork` classifies network failures into the built-in cases. Other sources get a helper of the same shape: a parser or storage helper (`runCatching { parser.parse(bytes) }.mapError { … DomainError.Unknown(it.message) }`) maps to `Unknown(cause)`, or to the area's typed error when a screen must react (`PhotoError.AlbumFull(limit)`). Statuses and answers that mean something are decided before the boundary: in the data source (404 → `null`), then in the repository (`null` → `NotFound`, an API error code → a typed error).
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
- When the API sends a machine-readable error code in its error body, the data source reads it and throws `HttpStatusException(status, code)` itself. The repository can then turn a known code into the area's typed error (`code == "album_full"` → `PhotoError.AlbumFull(limit)`).

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
    override suspend fun setFavorite(id: String, favorite: Boolean) {
        failWith?.let { throw it }
        photos = photos.map { if (it.id == id) it.copy(favorite = favorite) else it }
    }
}

class PhotoRepositoryImplTest {
    @Test
    fun aDroppedConnectionBecomesConnectivity() = runTest {
        val remote = FakePhotoRemoteDataSource().apply { failWith = IOException("no route to host") }   // kotlinx.io
        val repo = PhotoRepositoryImpl(remote, TestDispatcherProvider(testScheduler))

        assertEquals(Err(DomainError.Network.Connectivity), repo.photos())
    }
}
```

- **Cancellation, once per helper:** a data source that throws `CancellationException` must make the repository call throw it too (`assertFailsWith<CancellationException>`), not return an `Err`.
- **The Ktor data source and the status handling:** build the production setup over Ktor's multiplatform fake engine, `HttpClient(MockEngine { respond(content = "…", status = HttpStatusCode.NotFound, headers = headersOf(HttpHeaders.ContentType, "application/json")) }) { configureDefaults() }`. Then check 404 → `NotFound`, 5xx → `Network.Http(status, …)`, a malformed or non-JSON body → `Unknown`. `CatchNetworkTest` (shipped with the Ktor opt-in) already covers the helper's own mapping. Init adds `libs.ktor.client.mock` to `:data`'s `commonTest` when Ktor is selected; older projects add it from the catalog. MockK stays out of `commonTest`.
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
- No `Dispatchers.*` outside `RealDispatcherProvider`. Every `expect` has an actual on every target, and platform adapters live in `<base>.data.platform`.
- Each new repository or data source is bound in `dataModule`, and its tests cover every error it can return plus cancellation.
- `./gradlew :data:jvmTest` while iterating. Before pushing, run `./gradlew spotlessApply` (the samples here are compact, and ktlint_official reflows signatures and comments), then the CI gate: `./gradlew spotlessCheck detekt build koverVerify`.
