---
name: adr-authoring
description: Author Architecture Decision Records (ADRs) for kmp-forge projects following the Michael Nygard format. Use when documenting a stack or architecture decision, adopting an opt-in library, superseding a prior decision, or when /kmp-forge-init asks about adding a non-default lib.
---

# ADR authoring — kmp-forge style

ADRs live in `docs/DECISIONS/NNNN-kebab-case-title.md`. They capture *why* a non-obvious decision was made — the kind of thing you'd otherwise re-debate every six months.

## Format (Michael Nygard)

```markdown
# NNNN. <title>

Date: YYYY-MM-DD
Status: Accepted | Superseded by [NNNN](NNNN-...)

## Context
<what's driving this decision? what's the problem or the constraint?>

## Decision
<what we will do — concrete, action-oriented>

## Consequences
<what becomes easier, what becomes harder, what reviewer must enforce going forward>
```

## File naming

`NNNN-kebab-case-title.md` where:

- `NNNN` is sequential (0001, 0002, ...), never reused, never reordered
- title is kebab-case, brief (3–6 words)

Examples:
- `0007-add-sqldelight.md`
- `0012-switch-to-posthog.md`
- `0018-extract-auth-module.md`

## Status

- **Accepted** — current decision
- **Superseded by [NNNN](NNNN-...)** — replaced by a later ADR; this ADR is read-only history
- **Deprecated** — no longer relevant; left for context

Never edit an Accepted ADR's substance. Write a new ADR that supersedes it.

## When to write an ADR

✓ Adopting an opt-in library (Sentry, SQLDelight, Ktor, gradle-play-publisher)
✓ Changing a core stack choice (Koin → kotlin-inject — rare; supersedes 0002)
✓ Architectural decisions affecting 2+ modules (extracting `:auth`, splitting `:designsystem`)
✓ Distribution tier change (graduating from GitHub Releases to Play Store)
✓ Observability tier change (opting into Sentry)
✓ Per-project decisions that diverge from kmp-forge defaults

✗ Library version bumps (no ADR; just commit)
✗ Internal refactors with no architectural impact
✗ Bug fixes
✗ UI / design changes (those live in Figma + design tokens)

## Pre-seeded ADRs (from kmp-forge overlay)

Every scaffolded project ships with these 6, documenting the locked-stack rationale:

- `0001-orbit-mvi.md` — why Orbit over Molecule / hand-rolled
- `0002-koin.md` — why Koin over kotlin-inject / Metro
- `0003-hybrid-architecture.md` — why feature-presentation + shared domain/data
- `0004-nav3.md` — why Nav 3 over AndroidX Nav 2 / Voyager / Decompose
- `0005-result-domain-error.md` — why kotlin-result (Result<V, E>) + sealed DomainError over Arrow / exceptions
- `0006-dispatcher-provider.md` — why inject DispatcherProvider

The project's first author-written ADR starts at `0007`.

## Writing tips

### Context section

State the *forcing function* — what made this decision necessary? Not "we should do X"; instead "we need X because Y, and the existing approach doesn't work because Z."

✓ "Crashes from desktop and web targets weren't reaching our dashboard. Play Vitals and App Store Connect cover Android/iOS only — we needed cross-platform crash reporting."

✗ "We need crash reporting." (no forcing function — leaves the reader wondering why now)

### Decision section

Imperative: "We will adopt X."

Include the specific shape of the adoption — version, library, idiomatic snippet. Reviewer should be able to enforce it.

✓ "Adopt Sentry via `sentry-kotlin-multiplatform`. Init in `:composeApp` platform entry points before Koin. Wire Kermit→Sentry sink at minSeverity = Severity.Warn."

✗ "Add Sentry." (no shape)

### Consequences section

Three pillars:
- **Easier** — what does this unlock or simplify?
- **Harder** — what new ongoing cost does it create?
- **Enforced** — what does kmp-reviewer (or you) now enforce on every PR?

✓
> - Easier: cross-platform crashes in one dashboard; breadcrumbs from Kermit attached.
> - Harder: SENTRY_DSN secret to manage; another SDK to bump on `/kmp-forge-bump-stack`.
> - Reviewer enforces: don't log raw user input (PII); add Kermit log calls at ERROR/WARN at semantic boundaries.

### Length

100–250 lines max. ADRs are not specs; they're decision logs. If you find yourself writing implementation detail, link to code or a doc instead.

## Updating decisions

Don't edit Accepted ADRs in place. Write a new ADR that supersedes:

```markdown
# 0014. Switch from kotlin-result to Arrow Either

Date: 2026-09-01
Status: Accepted (supersedes [0005](0005-result-domain-error.md))

## Context
After 18 months, multi-step domain workflows have grown verbose even with kotlin-result's `coroutineBinding`; we want Raise's typed-error effect scopes...

## Decision
Adopt arrow-kt's Either<DomainError, T> with Raise DSL across :domain...
```

Then update `0005-result-domain-error.md`:

```diff
- Status: Accepted
+ Status: Superseded by [0014](0014-switch-to-arrow-either.md)
```

(That's the *only* edit to an Accepted ADR that's allowed.)

## Linking ADRs

Use relative paths within the project:

```markdown
See [0003 — Hybrid architecture](0003-hybrid-architecture.md) for module-layout rationale.
```

For cross-project plugin docs, use the full GitHub URL:

```markdown
See [architecture.md](https://github.com/arthurnagy/kmp-forge/blob/main/docs/architecture.md).
```
