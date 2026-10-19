---
name: data-layer
description: Write or change code in a kmp-forge project's :data module — internal repository implementations bound to :domain interfaces, data sources (Ktor HTTP, DataStore preferences, SQLDelight, Store), DTOs and mappers, turning exceptions into DomainError values at the boundary, per-platform expect/actual pieces and their Koin module, dataModule bindings, and repository tests with fake data sources. Use when implementing a repository, adding an API call, a stored preference, a table or a cache, wiring a platform-specific dependency, or when an OpenSpec task touches :data.
---

# :data — kmp-forge style

`:data` implements the repository interfaces `:domain` declares. It is the only module that talks to the network, the disk or platform storage, and the only place exceptions are allowed to exist: **they stop here and leave as `DomainError` values.** Canonical rules: the plugin's [architecture.md](../../docs/architecture.md) (§ `:data`, § Visibility), [stack.md](../../docs/stack.md) (Ktor, DataStore, SQLDelight, Store) and [testing.md](../../docs/testing.md). The domain side of a slice (entities, errors, the interface) comes first; see the `domain-layer` skill.

## Shape

```
data/src/commonMain/kotlin/<base>/data/
  dataModule.kt                 the one public declaration in :data
  PlatformDataModule.kt         internal expect val platformDataModule (when a platform piece exists)
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
- Mappers are `internal` extensions next to the DTO. A mapping that can fail (an unknown enum value, a malformed date) returns `Result<…, <Area>Error>` instead of throwing.

### 2. Data sources

Put each data source behind an `internal interface` so the repository can be tested against a fake. A data source is a thin wrapper over one library. It speaks DTOs and **may throw**; the repository is where exceptions stop.

```kotlin
internal interface PhotoRemoteDataSource {
    suspend fun photos(): List<PhotoDto>
}

internal class KtorPhotoRemoteDataSource(private val client: HttpClient) : PhotoRemoteDataSource {
    override suspend fun photos(): List<PhotoDto> = client.get("photos").body()
}
```

**Ktor.** Use one client: `createHttpClient()` (from the overlay), bound once as `single { createHttpClient() }`. Its setup lives in `HttpClientConfig<*>.configureDefaults()`, so tests can build the same client over a fake engine. That setup includes `expectSuccess = true`, so a non-2xx response throws a `ResponseException` (`ClientRequestException` for 4xx, `ServerResponseException` for 5xx) instead of failing later inside `body()`. Projects scaffolded before that change need `expectSuccess = true` (and the `configureDefaults()` split) added to `HttpClientFactory.kt`. Base URL, auth and logging go in `configureDefaults()`, never per data source. Secrets come from the environment and build config, never from source ([secrets.md](../../docs/secrets.md)).

**DataStore** (preferences). Allow **one instance per file per process**: a second `DataStore` on the same file throws on first use, so it is a Koin `single`. The file path is per platform (see *Platform pieces* below). Read with a flow that can't throw:

```kotlin
internal class DataStoreSettingsLocalDataSource(private val store: DataStore<Preferences>) : SettingsLocalDataSource {
    override val themeMode: Flow<String?> = store.data
        .catch { e -> if (e is okio.IOException) emit(emptyPreferences()) else throw e }   // unreadable file → defaults
        .map { it[THEME_MODE] }

    override suspend fun setThemeMode(value: String) {
        store.edit { it[THEME_MODE] = value }
    }

    private companion object {
        val THEME_MODE = stringPreferencesKey("theme_mode")
    }
}
```

DataStore throws **okio's** `IOException`. On iOS that is a different class from Ktor's `kotlinx.io.IOException`, so catch the type of the library you call. DataStore 1.2 has no `js` target: with web in the project, preferences need a `localStorage`-backed implementation in `webMain` behind the same interface.

**SQLDelight.** SQL goes in `data/src/commonMain/sqldelight/<base-path>/data/db/*.sq`. The generated `AppDatabase` is a Koin `single` built from an `internal expect class DriverFactory { fun create(): SqlDriver }` (see *Platform pieces*). Observe with `query.asFlow().mapToList(dispatchers.io)` (`sqldelight-coroutines`), and write multi-row changes in one `transactionWithResult { }`. Driver exceptions share no common supertype across platforms. That is the one case for a broad catch: put it in a single private boundary helper, documented with KDoc (example below).

**Store** (`store5`) only when a type has two or more sources, such as remote + database with stale-while-revalidate: one `Store<Key, Value>` per type ([stack.md § Store](../../docs/stack.md#store-mobilenativefoundationstore)). Single-source data uses a plain repository.

### 3. The repository: where exceptions become errors

```kotlin
internal class PhotoRepositoryImpl(
    private val remote: PhotoRemoteDataSource,
    private val dispatchers: DispatcherProvider,
) : PhotoRepository {

    override suspend fun photos(): Result<List<Photo>, PhotoError> =
        withContext(dispatchers.io) {
            remoteCall("photos") { remote.photos().map { it.toDomain() } }
        }

    // photo(id), setFavorite(…) and favorites() follow the same pattern.

    private inline fun <T> remoteCall(operation: String, block: () -> T): Result<T, PhotoError> =
        try {
            Ok(block())
        } catch (e: CancellationException) {
            throw e                                         // cancellation must propagate, always first
        } catch (e: ResponseException) {
            log.w(e) { "$operation: HTTP ${e.response.status}" }
            Err(if (e.response.status == HttpStatusCode.NotFound) PhotoError.NotFound else PhotoError.Unavailable)
        } catch (e: IOException) {                          // kotlinx.io: offline, DNS, timeouts
            log.w(e) { "$operation: network" }
            Err(PhotoError.Offline)
        } catch (e: ContentConvertException) {              // a JSON body that doesn't match the DTO
            log.e(e) { "$operation: unreadable response" }
            Err(PhotoError.Unavailable)
        } catch (e: NoTransformationFoundException) {       // a 2xx that isn't JSON at all (captive portal, proxy page)
            log.e(e) { "$operation: unexpected content type" }
            Err(PhotoError.Unavailable)
        }

    private companion object {
        val log = Logger.withTag("PhotoRepository")
    }
}
```

- **Catch the specific types each library throws.** detekt rejects `catch (e: Exception)` / `Throwable` (`TooGenericExceptionCaught`) and an exception that is caught but never used (`SwallowedException`). Logging it with Kermit counts as using it.
- **Rethrow `CancellationException` first.** Catching it breaks structured concurrency: a cancelled screen's call would "fail" instead of stopping. (`runCatching` swallows it too, which is one more reason it's off-limits.)
- The broad-catch exception, for a driver that throws unrelated types: one private helper whose KDoc says why, with the suppression on that helper only.
  ```kotlin
  /** SQLDelight drivers (Android framework, JDBC, SQLiter) throw unrelated types; this is the storage boundary. */
  @Suppress("TooGenericExceptionCaught")
  private inline fun <T> storage(operation: String, block: () -> T): Result<T, PhotoError> =
      try {
          Ok(block())
      } catch (e: CancellationException) {
          throw e
      } catch (e: Exception) {
          log.e(e) { "$operation failed" }
          Err(PhotoError.Unavailable)
      }
  ```
  Never inline in a method body, never in `:domain` / `:feature-*`, and never to silence a finding you could fix by naming the type.
- I/O runs on `dispatchers.io` from the injected `DispatcherProvider`, never `Dispatchers.IO`. Only `RealDispatcherProvider` and its actuals name dispatchers.
- Streams (`Flow`) handle failures with `.catch { }` inside the flow, never letting them reach the collector.
- Log the cause before mapping it, so an `Unavailable` in the UI still leaves a trace with the real exception.

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

Repositories, data sources, clients and databases are `single`s. Constructor injection only.

### Platform pieces (expect/actual + one Koin module)

Anything built differently per platform (a DataStore file path, a SQLDelight driver, a `Context`) gets a common `expect` plus an `internal expect val platformDataModule: Module` that `dataModule` includes. Write an actual for **every target the module builds**, or the build fails on the missing one: `androidMain` always, `jvmMain` for `jvm`, `nativeMain` for iOS, `webMain` for `js`/`wasmJs`. The targets are `kmpForge.targets` in `gradle.properties`. A web actual can't use DataStore.

```kotlin
// commonMain
internal const val SETTINGS_FILE = "settings.preferences_pb"   // createWithPath wants .preferences_pb

internal fun createDataStore(producePath: () -> String): DataStore<Preferences> =
    PreferenceDataStoreFactory.createWithPath(produceFile = { producePath().toPath() })   // okio.Path.Companion.toPath

internal expect val platformDataModule: Module

// androidMain: KoinApplication registers the Android Context; resolve it in the definition, not in the lambda
internal actual val platformDataModule: Module = module {
    single {
        val context: Context = get()
        createDataStore { context.filesDir.resolve(SETTINGS_FILE).absolutePath }
    }
}

// nativeMain (iOS)
@OptIn(ExperimentalForeignApi::class)
internal actual val platformDataModule: Module = module {
    single {
        createDataStore {
            val documents = NSFileManager.defaultManager.URLForDirectory(
                directory = NSDocumentDirectory,
                inDomain = NSUserDomainMask,
                appropriateForURL = null,
                create = false,
                error = null,
            )
            requireNotNull(documents?.path) + "/$SETTINGS_FILE"
        }
    }
}

// jvmMain (desktop): a per-user app directory; DataStore creates missing parent directories
internal actual val platformDataModule: Module = module {
    single { createDataStore { File(System.getProperty("user.home"), ".<app-name>/$SETTINGS_FILE").absolutePath } }
}
```

## Tests

`data/src/commonTest/`: test the repository against **fake data sources**. `commonTest` sees `internal` declarations, so the fakes stay `internal` and module-local. Cover the success mapping and **every error branch the repository can return**.

```kotlin
internal class FakePhotoRemoteDataSource : PhotoRemoteDataSource {
    var photos: List<PhotoDto> = emptyList()
    var failWith: Throwable? = null
    override suspend fun photos(): List<PhotoDto> = failWith?.let { throw it } ?: photos
}

class PhotoRepositoryImplTest {
    @Test
    fun mapsNetworkFailureToOffline() = runTest {
        val remote = FakePhotoRemoteDataSource().apply { failWith = IOException("no route to host") }
        val repo = PhotoRepositoryImpl(remote, TestDispatcherProvider(testScheduler))

        assertEquals(Err(PhotoError.Offline), repo.photos())
    }
}
```

- Mappers with real logic (renames, enums, dates) get their own tests.
- **Ktor data source and the error mapping end to end:** build the production client setup over Ktor's multiplatform fake engine, `HttpClient(MockEngine { respond(content = "…", status = HttpStatusCode.NotFound, headers = headersOf(HttpHeaders.ContentType, "application/json")) }) { configureDefaults() }`, then check status → error mapping (404, 5xx, malformed JSON, a non-JSON 200). Init adds `libs.ktor.client.mock` to `:data`'s `commonTest` when Ktor is selected; older projects add it from the catalog. MockK stays out of `commonTest`.
- **DataStore data source:** test it against an in-memory store rather than a file:
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
  `readFailure = okio.IOException("corrupt")` checks the fallback to defaults. Any other exception must still propagate.
- Cover cancellation once per boundary helper: a cancelled call must not come back as an `Err`.
- Never touch the real network or disk in `commonTest`.

## Before you hand it on

- Nothing in `:data` is public except `dataModule`. No DTO, `HttpResponse` or `Preferences` appears in a `:domain` signature.
- No exception escapes a repository: `CancellationException` is rethrown first, everything else is mapped and logged, and flows `.catch`.
- No `Dispatchers.*` outside `RealDispatcherProvider`. Every `expect` has an actual on every target.
- Each new repository or data source is bound in `dataModule`, and its tests cover every error it can return.
- `./gradlew :data:jvmTest` while iterating. Before pushing, run `./gradlew spotlessApply` (the samples here are compact, and ktlint_official reflows signatures and comments), then the CI gate: `./gradlew spotlessCheck detekt build koverVerify`.
