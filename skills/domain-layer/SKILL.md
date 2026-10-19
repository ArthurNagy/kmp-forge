---
name: domain-layer
description: Write or change code in a kmp-forge project's :domain module — use cases returning kotlin-result's Result<T, DomainError>, entities and value types without default values, one repository interface per domain type, cases of the app-wide sealed DomainError, DispatcherProvider, domainModule wiring, shared fakes in :testing, and use-case tests. Use when adding or changing a use case, entity, repository interface or error case, when an OpenSpec task touches :domain, or when deciding whether a piece of logic belongs in :domain.
---

# :domain — kmp-forge style

`:domain` is the app's business logic in pure Kotlin: what the app knows (entities), what it can do (use cases), what it needs from the outside world (repository interfaces) and how that can fail (`DomainError`). It depends on nothing internal and runs on every target, so all of it is testable on the host in milliseconds. Canonical rules: the plugin's [architecture.md](../../docs/architecture.md) (§ What goes where, § Visibility), [testing.md](../../docs/testing.md) and the project's ADRs 0005 (Result + DomainError) and 0006 (DispatcherProvider). The gates — `kmp-reviewer`, detekt, Kover — enforce them.

## What belongs here

| In `:domain` | Elsewhere |
|---|---|
| entities and value types (`Photo`, `PhotoId`) | DTOs and wire formats → `:data` |
| use cases (`GetPhotosUseCase`) | ViewModels, state, strings → `:feature-*` |
| repository **interfaces** (`PhotoRepository`) | their implementations, Ktor, DataStore, SQLDelight → `:data` |
| `DomainError` — one app-wide sealed interface | its user-facing text → `:ui`'s `DomainError.toMessage()` |
| `DispatcherProvider` (interface) | `Dispatchers.IO` / `Default` / `Main` |

Dependencies: Kotlin stdlib, kotlinx-coroutines, kotlinx-datetime, kotlinx-serialization, kotlin-result, koin-core (for `domainModule` only). Never Compose, Android, Ktor, DataStore, SQLDelight, Coil, Kermit or `java.*`. Package by area: `<base>.domain.photo`, `<base>.domain.settings`.

## Adding a slice — in this order

Entity → any new `DomainError` case → repository interface → use case → `domainModule` → fake in `:testing` → tests. Each step compiles on its own, and `:data` / `:feature-*` work can start once the interface exists.

### 1. Entities and value types

```kotlin
package <base>.domain.photo

import kotlin.jvm.JvmInline

@JvmInline
value class PhotoId(val value: String)

data class Photo(
    val id: PhotoId,
    val title: String,
    val description: String?,
    val favorite: Boolean,
)
```

- **No default values.** Every call site states every field, and adding a field breaks every place that must decide its value. (`null` is a value you pass explicitly, not a default.)
- Immutable: `val`s and read-only collections (`List`, not `MutableList`). An invariant the type must always hold goes in `init { require(…) }`.
- IDs as value classes (`PhotoId`), so a `PhotoId` can't be passed where a `UserId` is expected.
- No presentation: no display strings, no formatting, no colors. Derived facts are fine as getters (`val isFavorite`, `val primaryFile`). Dates via kotlinx-datetime / `kotlin.time`, never `java.time`.
- Public: entities are the cross-module vocabulary.

### 2. Errors: one app-wide `DomainError`

The template ships `<base>.domain.DomainError`, and the app keeps exactly one:

```kotlin
sealed interface DomainError {
    data object NotFound : DomainError
    data class Network(val cause: String?) : DomainError      // cause: diagnostic detail for logs
    data class Unknown(val cause: String?) : DomainError
    data object TitleBlank : DomainError                      // added by the photo slice
}
```

- **Add a case when the user must be told something new** (the server rejected the login, a name is blank, the card is full). Don't add one per library failure: transport problems are `Network(cause)` and anything unclassified is `Unknown(cause)`. Name a case after what the user must hear, not after what threw.
- **Never a second hierarchy** (`PhotoError`, `sealed interface XError : DomainError`). Since it's sealed, a new case breaks `:ui`'s exhaustive `DomainError.toMessage()` until it has a message there, plus a string in `:ui`'s `values/strings.xml`. That is the point: no error reaches a screen without words.
- A `cause` is for logs: `:data` fills it with the exception message, and the UI never shows it.
- A value, never a `Throwable` / `Exception` subtype.

### 3. Repository interfaces

```kotlin
interface PhotoRepository {
    suspend fun photos(): Result<List<Photo>, DomainError>
    suspend fun photo(id: PhotoId): Result<Photo, DomainError>
    suspend fun setFavorite(id: PhotoId, favorite: Boolean): Result<Unit, DomainError>
    fun favorites(): Flow<List<Photo>>
}
```

- **One per domain type.** `PhotoRepository` handles `Photo` and nothing else. Never an `AppRepository` / `DataRepository`. Two types that are really one aggregate become one domain type, not two repos.
- One-shot operations are `suspend` and return `Result<T, DomainError>`. Streaming state is a `Flow` / `StateFlow` and **never throws**; a failure the UI must show goes into the emitted value (e.g. an `error: DomainError?` field of the state the repository publishes).
- Domain types only in signatures: no DTOs, no `HttpResponse`, no `Preferences`.
- Only the interface lives here. Its `internal` implementation lives in `:data` (see the `data-layer` skill).

### 4. Use cases

```kotlin
package <base>.domain.photo

import <base>.domain.DispatcherProvider
import <base>.domain.DomainError
import com.github.michaelbull.result.Result
import com.github.michaelbull.result.map
import kotlinx.coroutines.withContext

class GetPhotosUseCase(
    private val photos: PhotoRepository,
    private val dispatchers: DispatcherProvider,
) {
    suspend operator fun invoke(): Result<List<Photo>, DomainError> =
        withContext(dispatchers.default) {
            photos.photos().map { list -> list.sortedBy { it.title.lowercase() } }
        }
}
```

- **Public class, public constructor.** `:feature-*` tests build real use cases with fakes. In production only `domainModule` constructs them.
- One `operator fun invoke`. ViewModels depend on use cases, never on repositories, so a pass-through gets one too (`class GetPhotoUseCase(private val photos: PhotoRepository) { suspend operator fun invoke(id: PhotoId) = photos.photo(id) }`). Write a use case when a screen needs the operation, not for every repository method in advance.
- Business rules live here: validation, ordering, combining repositories, choosing which error applies. Validate before calling the repository: `if (title.isBlank()) return Err(DomainError.TitleBlank)`.
- Take `DispatcherProvider` when the use case does CPU-heavy work, and switch with `withContext(dispatchers.default)`. Repository implementations move their own I/O to `dispatchers.io`. Never `Dispatchers.*` here.
- **Failures are values.** No `throw`, no `try/catch`, no `!!` / `getOrThrow()` / `unwrap()`. Not `kotlin.Result` or the stdlib's `runCatching`.
- Several steps: `coroutineBinding` stops at the first `Err`.

  ```kotlin
  import com.github.michaelbull.result.coroutines.coroutineBinding

  class ToggleFavoriteUseCase(private val photos: PhotoRepository) {
      suspend operator fun invoke(id: PhotoId): Result<Photo, DomainError> = coroutineBinding {
          val photo = photos.photo(id).bind()
          photos.setFavorite(id, !photo.favorite).bind()
          photo.copy(favorite = !photo.favorite)
      }
  }
  ```
- kotlin-result members are imported one by one (`Result`, `Ok`, `Err`, `map`, `mapError`, `andThen`, …): ktlint and detekt reject wildcard imports. Its Gradle coordinate (`com.michael-bull.kotlin-result`) differs from its package (`com.github.michaelbull.result`).

### 5. Wire it

```kotlin
val domainModule = module {
    factoryOf(::GetPhotosUseCase)       // org.koin.core.module.dsl.factoryOf
    factoryOf(::ToggleFavoriteUseCase)
}
```

Use cases are stateless, so register them with `factoryOf`. Repository interfaces are bound in `:data`'s `dataModule`, not here. Constructor injection only: no `KoinComponent`, no `GlobalContext.get()`.

### 6. Fake in `:testing`

Fakes of `:domain` interfaces go in `:testing/src/commonMain`, because `:domain`'s use-case tests **and** `:feature-*`'s ViewModel tests both use them, so one copy serves both. A fake only one module's tests need may stay in that module's `commonTest`.

```kotlin
package <base>.testing

class FakePhotoRepository : PhotoRepository {
    private val store = MutableStateFlow<Map<PhotoId, Photo>>(emptyMap())
    var nextError: DomainError? = null

    fun seed(vararg photos: Photo) = store.update { current -> current + photos.associateBy { it.id } }

    override suspend fun photos(): Result<List<Photo>, DomainError> =
        nextError?.let { Err(it) } ?: Ok(store.value.values.toList())

    override suspend fun photo(id: PhotoId): Result<Photo, DomainError> =
        nextError?.let { Err(it) } ?: store.value[id]?.let { Ok(it) } ?: Err(DomainError.NotFound)

    override suspend fun setFavorite(id: PhotoId, favorite: Boolean): Result<Unit, DomainError> =
        photo(id).map { photo -> store.update { it + (id to photo.copy(favorite = favorite)) } }

    override fun favorites(): Flow<List<Photo>> = store.map { photos -> photos.values.filter { it.favorite } }
}
```

A fake behaves like the real thing (in-memory state, a stream that reflects writes) and exposes knobs (`seed`, `nextError`). Test knobs may have defaults; the no-defaults rule is for entities and `State`. Never MockK in `commonTest`.

### 7. Tests

`domain/src/commonTest/`: every use case gets its happy path and **each error it can return**. Tag a test that covers an OpenSpec scenario with `// Scenario: <exact name>`, which is how QA traces coverage.

```kotlin
class GetPhotosUseCaseTest {
    @Test
    fun returnsPhotosSortedByTitle() = runTest {
        val repo = FakePhotoRepository().apply { seed(photo(id = "1", title = "b"), photo(id = "2", title = "a")) }

        val result = GetPhotosUseCase(repo, TestDispatcherProvider(testScheduler))()

        assertEquals(listOf("a", "b"), result.get()?.map { it.title })      // import com.github.michaelbull.result.get
    }

    @Test
    fun surfacesNetworkFailure() = runTest {
        val repo = FakePhotoRepository().apply { nextError = DomainError.Network("offline") }

        assertEquals(Err(DomainError.Network("offline")), GetPhotosUseCase(repo, TestDispatcherProvider(testScheduler))())
    }
}
```

Always `TestDispatcherProvider(testScheduler)`, the `runTest` scheduler. A dispatcher with its own scheduler hangs or fails with "Detected use of different schedulers". Build test entities with a small local builder (`photo(id, title)`) that passes every field explicitly.

## Before you hand it on

- `:domain` imports nothing outside the allowed list above, and nothing references `Dispatchers.*`.
- Entities have no default values. Use cases are public with public constructors.
- Errors are cases of the one `DomainError`, and each new case has its message in `:ui`'s `toMessage()`.
- Each new use case is in `domainModule` and has tests for success and every error it can return.
- Each fake matches its interface's latest shape.
- `./gradlew :domain:jvmTest` while iterating. Before pushing, run `./gradlew spotlessApply` (the samples here are compact, and ktlint_official reflows signatures and comments), then the CI gate: `./gradlew spotlessCheck detekt build koverVerify` (75% line coverage).
