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

Use [Orbit MVI](https://orbit-mvi.org/) on every ViewModel. ViewModels extend `androidx.lifecycle.ViewModel` and implement `ContainerHost<State, Nothing>`. State mutations go through `intent { reduce { ... } }`.

**State-only events** — we do NOT use `postSideEffect`. Effect type is always `Nothing`. One-shot events (navigation, toasts, snackbars) are modeled as consumable state slots (`pendingNavigation: Route?`, `pendingMessage: String?`) set inside `intent {}` and cleared by paired `onXxxConsumed()` intents the UI calls after rendering.

**Sub-states via sealed interface** when a flat data class would force boolean spaghetti at the page level (mutually-exclusive `Loading | Loaded | Error`). Default is flat data class; promote only when warranted.

## Consequences

- Easier: consistent MVI shape across features; built-in `ContainerHost.test()` harness for unit tests; every piece of UI behavior is observable state — robust across config changes / process death; testing one-shot events is trivial (just assert state slot transitions).
- Harder: one more library dependency to maintain; new contributors learn the consumable-slot pattern; bookkeeping of `onXxxConsumed()` intent pairs.
- Reviewer enforces: no state mutation outside `intent {}`; no `postSideEffect` anywhere; `ContainerHost<State, Nothing>` only; page-level boolean spaghetti gets promoted to a sealed interface.
