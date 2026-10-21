---
name: adr-authoring
description: Author or supersede an Architecture Decision Record in a kmp-forge project (its CLAUDE.md links kmp-forge's docs as its rules) — Nygard format in docs/DECISIONS/NNNN-kebab-title.md, next free number, Context with alternatives considered, Decision, Consequences. Use when recording why a stack, module or architecture choice was made, adopting an opt-in library (Ktor, SQLDelight, Sentry, gradle-play-publisher), changing distribution or observability tier, superseding an earlier ADR, or when /kmp-forge-add-library, /kmp-forge-refine or the kmp-architect agent calls for an ADR.
---

# ADR authoring — kmp-forge style

ADRs live in `docs/DECISIONS/NNNN-kebab-case-title.md`. They capture *why* a non-obvious decision was made — the kind of thing a team otherwise re-debates every six months.

## Format (Michael Nygard)

```markdown
# NNNN. <title>

Date: YYYY-MM-DD
Status: Accepted | Accepted (supersedes [NNNN](NNNN-...)) | Superseded by [NNNN](NNNN-...) | Deprecated

## Context
<what's driving this decision? what's the problem or the constraint?>

Alternatives considered:
- **<option>** — <why it loses here>
- **<option>** — <why it loses here>

## Decision
<imperative, starting with the verb: "Use …", "Adopt …" — concrete, action-oriented>

## Consequences
<what becomes easier, what becomes harder, what reviewer must enforce going forward>
```

## File naming

`NNNN-kebab-case-title.md` where:

- `NNNN` is the highest number in `docs/DECISIONS/` plus one, four digits — never reused, never reordered
- title is kebab-case, brief (3–6 words)

Examples:
- `0007-add-sqldelight.md`
- `0012-switch-to-posthog.md`
- `0018-extract-auth-module.md`

## Status

- **Accepted** — current decision
- **Accepted (supersedes …)** — `Status: Accepted (supersedes [NNNN](NNNN-...))`: current decision that replaces an earlier ADR (§ Updating decisions)
- **Superseded by …** — `Status: Superseded by [NNNN](NNNN-...)`: replaced by a later ADR; this ADR is read-only history
- **Deprecated** — no longer relevant (the thing it governed is gone); left for context

Never edit an Accepted ADR's substance. Write a new ADR that supersedes it.

## When to write an ADR

✓ Adopting an opt-in library (Sentry, SQLDelight, Ktor, gradle-play-publisher)
✓ Changing a core stack choice (Koin → kotlin-inject — rare; supersedes 0002)
✓ Architectural decisions affecting 2+ modules (extracting `:auth`, splitting `:designsystem`)
✓ Distribution tier change (graduating from GitHub Releases to Play Store)
✓ Observability tier change (opting into Sentry)
✓ Per-project decisions that diverge from kmp-forge defaults
✓ A leaked secret — `NNNN-secret-rotation.md`: date, secret type, scope, remediation ([secrets.md](../../docs/secrets.md))

✗ Library version bumps (no ADR; just commit)
✗ Internal refactors with no architectural impact
✗ Bug fixes
✗ UI / design changes (those live in Figma + design tokens)

## From an `adr_proposal.yml` issue

The issue form (`adr` label) collects **Proposed title**, **Context**, **Decision** and **Consequences**; the issue
is where the decision is discussed, the ADR file is the record. Once the proposal is agreed:

1. Number it — the highest number in `docs/DECISIONS/` plus one — and name the file after the proposed title in
   kebab-case (`NNNN-kebab-case-title.md`).
2. Carry the form's sections into the format above: **Context** gains the forcing function and an
   **Alternatives considered** list (the options the issue thread weighed — ask for them when the issue names none);
   **Decision** is rewritten imperatively with the concrete shape; **Consequences** gets its Easier / Harder /
   Enforced lines.
3. `Date:` is the day it is written, `Status: Accepted` (or `Accepted (supersedes [NNNN](…))`, plus the superseded
   ADR's status line — § Updating decisions).
4. Copy each enforceable rule to CLAUDE.md § Project-specific overrides, commit both as `docs(adr): <title>`, and
   open the PR with `Closes #<issue>` in its body so merging records the decision and closes the proposal.

A proposal that is turned down gets no ADR file: whoever turned it down closes the issue with a comment saying why.

## Pre-seeded ADRs (from kmp-forge overlay)

Every scaffolded project ships with these 6, documenting the locked-stack rationale:

- `0001-orbit-mvi.md` — why Orbit over Molecule / hand-rolled
- `0002-koin.md` — why Koin over kotlin-inject / Metro
- `0003-hybrid-architecture.md` — why feature-presentation + shared domain/data
- `0004-nav3.md` — why Nav 3 over AndroidX Nav 2 / Voyager / Decompose
- `0005-result-domain-error.md` — why kotlin-result (Result<V, E>) + sealed DomainError over Arrow / exceptions
- `0006-dispatcher-provider.md` — why inject DispatcherProvider

A new ADR takes the highest number in `docs/DECISIONS/` plus one — `0007` in a fresh scaffold, later in an adopted
project that already had ADRs. Commit ADRs on their own as `docs(adr): <title>` (what `/kmp-forge-refine`
tells the user to do).

## Writing tips

### Context section

State the *forcing function* — what made this decision necessary? Not "we should do X"; instead "we need X because Y, and the existing approach doesn't work because Z."

✓ "Crashes from desktop and web targets weren't reaching our dashboard. Play Vitals and App Store Connect cover Android/iOS only — we needed cross-platform crash reporting."

✗ "We need crash reporting." (no forcing function — leaves the reader wondering why now)

### Decision section

Imperative, starting with the verb — "Use X", "Adopt X" — like the seeded ADRs.

Include the specific shape of the adoption — version, library, idiomatic snippet. Reviewer should be able to enforce it.

✓ "Adopt Sentry via `sentry-kotlin-multiplatform`. Init in the `:shared` composition root (and per-platform entry points `:androidApp`/`:desktopApp`/`iosApp/` as needed) before Koin. Wire Kermit→Sentry sink at minSeverity = Severity.Warn."

✗ "Add Sentry." (no shape)

### Consequences section

Three pillars:
- **Easier** — what does this unlock or simplify?
- **Harder** — what new ongoing cost does it create?
- **Enforced** — what must every PR now respect? `kmp-reviewer` enforces the rules in the project's CLAUDE.md
  § Project-specific overrides, not the ADRs themselves — so copy each enforceable rule there as one line
  (`- <rule> (ADR NNNN)`), in the same commit as the ADR.

✓
> - Easier: cross-platform crashes in one dashboard; breadcrumbs from Kermit attached.
> - Harder: SENTRY_DSN secret to manage; another SDK to bump on `/kmp-forge-bump-stack`.
> - Enforced (copied to CLAUDE.md § Project-specific overrides): don't log raw user input (PII); add Kermit log calls at ERROR/WARN at semantic boundaries.

### Length

Usually under ~60 lines — the seeded ADRs are 25–50. ADRs are not specs; they're decision logs. Implementation detail belongs in code or a doc the ADR links to.

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
