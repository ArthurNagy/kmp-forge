# 1. Use Orbit MVI for state management

Date: ${SCAFFOLD_DATE}
Status: Accepted

## Context

We need a state-management pattern across all ViewModels with:
- Explicit MVI shape (intent → reduce → state) for predictability
- First-class support for one-shot side effects (navigation, toasts)
- KMP support (works in `commonMain`)
- Built-in testability without external mocking

Alternatives considered:
- **Molecule (cashapp)** — uses Compose runtime to model state. Lower ceremony but no formal MVI shape; side effects are a manual pattern.
- **Hand-rolled MVI on StateFlow + sealed events** — full control but boilerplate-heavy across every feature.

## Decision

Use [Orbit MVI](https://orbit-mvi.org/) on every ViewModel. ViewModels extend `androidx.lifecycle.ViewModel` and implement `ContainerHost<State, Effect>`. State mutations go through `intent { reduce { ... } }`; one-shot events via `postSideEffect(...)`.

## Consequences

- Easier: consistent MVI shape across features; built-in `ContainerHost.test()` harness for unit tests; clean separation of state vs side effects.
- Harder: one more library dependency to maintain; new contributors learn Orbit's DSL.
- Reviewer enforces: no state mutation outside `intent {}`; no one-shot events via state.
