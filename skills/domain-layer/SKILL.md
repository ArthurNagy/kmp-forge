---
name: domain-layer
description: Write or change code in a kmp-forge project's :domain module — use cases returning kotlin-result's Result<T, DomainError>, entities and value types without default values, one repository interface per domain type, the sealed DomainError (built-in cases plus an area's own DomainError.Typed errors), DispatcherProvider, domainModule wiring, shared fakes in :testing, and use-case tests. Use in a kmp-forge project (its CLAUDE.md links kmp-forge's docs as its rules) when adding or changing a use case, entity, repository interface or error case, when an OpenSpec task touches :domain, or when deciding whether a piece of logic belongs in :domain.
---

# :domain — kmp-forge style

`:domain` is the app's business logic in pure Kotlin: what the app knows (entities), what it can do (use cases), what it needs from the outside world (repository interfaces) and how that can fail (`DomainError`). It depends on nothing internal and runs on every target, so all of it is testable on the host in milliseconds. Canonical rules: the plugin's [architecture.md](../../docs/architecture.md) (§ What goes where, § Visibility), [testing.md](../../docs/testing.md) and the project's ADRs 0005 (Result + DomainError) and 0006 (DispatcherProvider). The gates — `kmp-reviewer`, detekt, Kover — enforce them.

## What belongs here

| In `:domain` | Elsewhere |
|---|---|
| entities and value types (`Photo`, `PhotoId`) | DTOs and wire formats → `:data` |
| use cases (`GetPhotosUseCase`) | ViewModels, state, strings → `:feature-*` |
| repository **interfaces** (`PhotoRepository`) | their implementations, Ktor, DataStore, SQLDelight → `:data` |
| `DomainError` (built-in cases) and each area's typed errors | their words → `:ui`'s `DomainError.toMessage()` / the screen that reacts |
| `DispatcherProvider` (interface) | `Dispatchers.IO` / `Default` / `Main` |

Dependencies: Kotlin stdlib, kotlinx-coroutines, kotlinx-datetime, kotlinx-serialization, kotlin-result, koin-core (for `domainModule` only). Never Compose, Android, Ktor, DataStore, SQLDelight, Coil, Kermit or `java.*`. Package by area: `<base>.domain.photo`, `<base>.domain.settings`.

## Adding a slice — in this order

Entity → the area's typed errors (if it has failures of its own) → repository interface → use case → `domainModule` → fake in `:testing` → tests. Each step compiles on its own, and `:data` / `:feature-*` work can start once the interface exists.

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

### 2. Errors: built-in cases, plus the area's typed errors

The template ships `<base>.domain.DomainError`. Its built-in cases cover what every app hits, and `:ui`'s `toMessage()` words them once:

```kotlin
sealed interface DomainError {
    sealed interface Network : DomainError {
        data object Connectivity : Network                        // no connection, a drop, a timeout
        data class Http(val status: Int, val code: String?) : Network   // the server answered with an error
    }
    data object NotFound : DomainError
    data class Unknown(val cause: String?) : DomainError          // cause: diagnostic detail for logs
    interface Typed : DomainError                                 // extension point for an area's own errors
}
```

A domain area's **own** failures (a rule it enforces, a refusal that carries details) are a sealed interface in its package that extends `DomainError.Typed`, with the payload a screen needs to react:

```kotlin
package <base>.domain.photo

sealed interface PhotoError : DomainError.Typed {
    data object TitleBlank : PhotoError
    data class AlbumFull(val limit: Int) : PhotoError
}
```

- **Use a built-in case for transport and generic failures:** `Network.Connectivity`, `Network.Http`, `NotFound`, `Unknown`. `:data` produces them, so don't re-type them per area (no `PhotoNetworkError`).
- **Use a typed error when a screen must react specifically:** say something only this area can explain, show a payload (`AlbumFull(limit)`), or offer a different action. Name it after what the user must hear, not after what threw.
- Screens word the typed errors they handle; anything they don't handle falls back to `toMessage()`'s generic message. A typed error nobody handles is just an `Unknown` with extra steps, so add one only when a screen will use it.
- A new **built-in** case is rare (a failure every area can hit, such as `Unauthorized` once the app has accounts). Since `DomainError` is sealed, it breaks `:ui`'s exhaustive `toMessage()` until it has a message there, plus a string in `:ui`'s `values/strings.xml`.
- A `cause` is for logs: `:data` fills it with the exception message, and the UI never shows it.
- Every error is a value, never a `Throwable` / `Exception` subtype, and every error type extends `DomainError`.

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
- Business rules live here: validation, ordering, combining repositories, choosing which error applies. Validate before calling the repository: `if (title.isBlank()) return Err(PhotoError.TitleBlank)`.
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
        val repo = FakePhotoRepository().apply { nextError = DomainError.Network.Connectivity }

        assertEquals(Err(DomainError.Network.Connectivity), GetPhotosUseCase(repo, TestDispatcherProvider(testScheduler))())
    }
}
```

Always `TestDispatcherProvider(testScheduler)`, the `runTest` scheduler. A dispatcher with its own scheduler hangs or fails with "Detected use of different schedulers". Build test entities with a small local builder (`photo(id, title)`) that passes every field explicitly.

## Before you hand it on

- `:domain` imports nothing outside the allowed list above, and nothing references `Dispatchers.*`.
- Entities have no default values. Use cases are public with public constructors.
- Transport and generic failures use the built-in `DomainError` cases. The area's own failures are its sealed `DomainError.Typed` errors, each one a screen will react to.
- Each new use case is in `domainModule` and has tests for success and every error it can return.
- Each fake matches its interface's latest shape.
- `./gradlew :domain:jvmTest` while iterating. Before pushing, run `./gradlew spotlessApply` (the samples here are compact, and ktlint_official reflows signatures and comments), then the CI gate: `./gradlew spotlessCheck detekt build koverVerify` (75% line coverage).
