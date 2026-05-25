# 3. Hybrid architecture — feature presentation + shared domain/data

Date: ${SCAFFOLD_DATE}
Status: Accepted

## Context

We need a module layout that:
- Encapsulates UI per feature (most code volume)
- Shares business logic and data layer cleanly across features
- Avoids module sprawl in small-to-medium projects (~3–15 features)
- Keeps a clear "delete this feature" boundary

Alternatives considered:
- **Pure feature-first** (every feature has its own `:presentation`, `:domain`, `:data`): module sprawl, cross-feature shared logic gets duplicated or needs a shared module anyway.
- **Pure layer-first** (top-level `:presentation`, `:domain`, `:data` containing all features): "feature" stops being a real boundary; every change touches multiple modules.

## Decision

Hybrid:
- `:feature-<name>` modules contain only Compose UI + ViewModel + state + Koin module + Nav 3 destination.
- Shared `:domain` holds use cases, domain entities, repository interfaces, `DispatcherProvider`, `DomainError` sealed bases.
- Shared `:data` holds repository implementations, data sources, DTOs, mappers.
- Shared `:ui` holds `AppTheme`, design tokens, reusable Composables.

Dependency direction: `:composeApp → :feature-* → {:ui, :domain}`; `:data → :domain`; `:domain` depends on nothing internal.

## Consequences

- Easier: most-changed code (UI + state) is encapsulated per feature; cross-feature business logic naturally shared; reasonable module count.
- Harder: feature-specific domain logic isn't private — lives in `:domain` under feature-named packages. Discipline via package boundaries, not module boundaries.
- Reviewer enforces: features never depend on other features; `:data` never imports `:ui`; `:domain` stays pure-Kotlin.

## When to extract a new shared module

See [architecture.md § When to extract a new shared module](https://github.com/arthurnagy/kmp-forge/blob/main/docs/architecture.md#when-to-extract-a-new-shared-module).
