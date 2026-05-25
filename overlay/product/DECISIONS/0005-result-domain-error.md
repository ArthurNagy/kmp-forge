# 5. Use Result<T> + sealed DomainError for error handling

Date: ${SCAFFOLD_DATE}
Status: Accepted

## Context

We need an error-handling philosophy that:
- Makes the failure modes of each use case explicit in its type signature
- Doesn't require introducing a new functional library
- Lets the UI exhaustively match on error types without try/catch ceremony

Alternatives considered:
- **Arrow Either / Raise** — `Either<E, A>` with `Raise` DSL. Adds `arrow-kt` dependency and a learning curve. Excellent type safety, more powerful combinators.
- **Exceptions caught at ViewModel** — throw freely across layers; `intent {}` wraps in try/catch. Less type-system ceremony; failure modes invisible until tested or hit at runtime.

## Decision

Use Kotlin's `Result<T>` (stdlib) plus a per-use-case `sealed interface DomainError`. Every use case signature reads:

```kotlin
suspend operator fun invoke(...): Result<Data, DomainError>
```

where `DomainError` is a sealed type local to that use case (or scoped to the domain area). UI exhaustively maps the error in state.

## Consequences

- Easier: failure modes visible in signatures; UI knows every branch; no surprise exceptions; stdlib only — no new library.
- Harder: more `Result<T>` plumbing than throwing exceptions; need to remember not to `.getOrThrow()` carelessly.
- Reviewer enforces: use cases return `Result<T, DomainError>` — never throw; ViewModels use `onSuccess`/`onFailure` and `reduce { state.copy(error = ...) }` rather than `try/catch` inside `intent {}`; `:domain` never throws checked or unchecked business errors.

If a project grows beyond what `Result<T>` can express cleanly (multi-step domain workflows, monadic composition), supersede this ADR with one adopting Arrow Either + Raise.
