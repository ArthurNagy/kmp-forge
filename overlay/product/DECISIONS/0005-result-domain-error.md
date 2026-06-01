# 5. Use kotlin-result (Result<V, E>) + sealed DomainError for error handling

Date: ${SCAFFOLD_DATE}
Status: Accepted

## Context

We need an error-handling philosophy that:
- Makes the failure modes of each use case explicit in its type signature
- Doesn't pull in a heavy functional-programming library or a new paradigm
- Lets the UI exhaustively match on error types without try/catch ceremony

Alternatives considered:
- **Kotlin stdlib `Result<T>`** — single type parameter; the failure is always a `Throwable`. Cannot carry a typed `DomainError` without making `DomainError` extend `Throwable` (category error + stack-trace cost) and casting in every `onFailure`. The error type is also erased from the signature (`Result<User>` hides the failure mode) — which defeats the first requirement. Rejected.
- **Arrow Either / Raise** — `Either<E, A>` with the `Raise` DSL. Excellent, but adds the `arrow-kt` dependency and a non-trivial learning curve (effect scopes, context receivers). Heavier than this project needs by default.
- **Exceptions caught at ViewModel** — throw freely across layers; `intent {}` wraps in try/catch. Less type-system ceremony; failure modes invisible until tested or hit at runtime. Rejected.

## Decision

Use [`kotlin-result`](https://github.com/michaelbull/kotlin-result) — a tiny, pure-Kotlin, multiplatform two-parameter `Result<V, E>` (`Ok`/`Err`) — plus a per-use-case `sealed interface DomainError`. Every use case signature reads:

```kotlin
suspend operator fun invoke(...): Result<Data, DomainError>
```

where `DomainError` is a sealed type local to that use case (or scoped to the domain area). UI exhaustively maps the error in state.

- **Gradle coordinate**: `com.michael-bull.kotlin-result:kotlin-result` (Maven Central). `kotlin-result-coroutines` adds `coroutineBinding { }` for multi-step compositions.
- **Kotlin import package**: `com.github.michaelbull.result.*` (`Ok`, `Err`, `onSuccess`, `onFailure`, `fold`, `map`, `mapError`, `andThen`, `getOrElse`, …). Note the coordinate and the package differ.
- Declared `api` in `:domain` so the `Result` type leaks transitively to `:data` and `:feature-*`.

```kotlin
import com.github.michaelbull.result.Ok
import com.github.michaelbull.result.Err
import com.github.michaelbull.result.Result

suspend operator fun invoke(id: UserId): Result<User, DomainError> =
    repo.find(id)?.let { Ok(it) } ?: Err(UserError.NotFound)
```

## Consequences

- Easier: failure modes visible in signatures; UI matches every branch exhaustively; no surprise exceptions; rich combinators out of the box; `coroutineBinding` covers multi-step workflows without Arrow.
- Harder: one small dependency. The type is named `Result`, which **shadows `kotlin.Result`** — import `com.github.michaelbull.result.*` consistently and avoid `runCatching` (which returns the stdlib type).
- Reviewer enforces: use cases return `Result<T, DomainError>` — never throw; ViewModels use `onSuccess`/`onFailure` and `reduce { state.copy(error = ...) }` rather than `try/catch` inside `intent {}`; `:domain` never throws checked or unchecked business errors; no careless `.get()!!` / `unwrap()`.

If a project grows to need a full effect system (typed errors across many composed steps, context receivers), supersede this ADR with one adopting Arrow Either + Raise.
