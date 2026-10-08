# 6. Inject DispatcherProvider instead of using Dispatchers directly

Date: ${SCAFFOLD_DATE}
Status: Accepted

## Context

Coroutine-using code (use cases, repositories, ViewModels) needs to specify which dispatcher to run on. The default option — referencing `Dispatchers.IO`, `Dispatchers.Default`, etc. directly — is convenient but:
- Couples business logic to the global Dispatchers singleton
- Makes tests flaky: real dispatchers run on background threads, breaking `runTest` determinism
- Hides the dispatcher choice in implementations; consumers can't override

## Decision

Declare a `DispatcherProvider` interface in `:domain`:

```kotlin
interface DispatcherProvider {
    val main: CoroutineDispatcher
    val io: CoroutineDispatcher
    val default: CoroutineDispatcher
}
```

Production `RealDispatcherProvider` (in `:data` or `:shared`) returns the standard `Dispatchers.Main / IO / Default`. Tests pass a `TestDispatcherProvider` backed by `StandardTestDispatcher`.

Use cases and repositories take `DispatcherProvider` via constructor injection (Koin-wired). They reference `dispatchers.io` / `dispatchers.default`, never `Dispatchers.IO` directly.

## Consequences

- Easier: deterministic `runTest`-based tests; explicit dispatcher choice in every coroutine-using class; trivial to swap in `Unconfined` or test dispatchers for specific tests.
- Harder: one more constructor parameter on every use case / repo; reviewer must catch raw `Dispatchers.*` references.
- Reviewer enforces: no raw `Dispatchers.IO/Default/Main` references in `:domain`, `:data`, or `:feature-*`. Only the entry points (`:shared` composition root, `:androidApp`, `:desktopApp`) and `RealDispatcherProvider` may name them.

ViewModels typically don't need `DispatcherProvider` directly — Orbit's `intent {}` runs on the configured container dispatcher; use cases handle their own dispatcher switching.
