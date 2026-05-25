# Product workflow

Every scaffolded project ships with a `docs/` directory and a `.github/ISSUE_TEMPLATE/` directory for the non-code side of product development.

## docs/MVP_SPEC.md

The single source of truth for product scope. Authored via `/kmp-forge-spec` (interactive interview by default; `--from-dump` mode accepts a free-form paste and structures it).

### Template

```markdown
# <APP_NAME> — MVP Spec

## Overview
<one paragraph: what the app does and the problem it solves>

## Target users
<who; primary persona one paragraph, secondary in bullets if relevant>

## Business model
<freemium, one-time purchase, subscription, free with ads, etc>

## Must-have (v1)
- <feature 1 in user terms>
- <feature 2>
- ...

## Out of scope (v1)
- <explicitly deferred feature>
- ...

## Key user flows
### Flow 1: <e.g. First-time setup>
1. <step>
2. <step>

### Flow 2: <e.g. Daily core action>
1. <step>

## Critical technical considerations
- <performance budget, memory, offline support, etc>

## Success metrics
- <e.g. activation rate, day-7 retention, NPS target>
```

### Lifecycle

- Write v0 at project start via `/kmp-forge-spec`.
- Update whenever scope decisions change. Commit changes via `docs:` Conventional Commit.
- Linked from `CLAUDE.md` so Claude reads it for context on every session.

## docs/DECISIONS/ (ADRs)

Architecture Decision Records using the [Michael Nygard format](https://github.com/joelparkerhenderson/architecture-decision-record/blob/main/locales/en/templates/decision-record-template-by-michael-nygard/index.md).

### File naming

`NNNN-kebab-case-title.md` — e.g. `0007-add-sqldelight.md`, `0012-switch-to-posthog.md`.

Numbers are sequential. Never reuse a number. Never reorder.

### Pre-seeded ADRs

`/kmp-forge-init` ships these from `overlay/product/DECISIONS/`:

- `0001-orbit-mvi.md` — why Orbit over Molecule/hand-rolled
- `0002-koin.md` — why Koin over kotlin-inject/Metro
- `0003-hybrid-architecture.md` — why feature-presentation + shared domain/data
- `0004-nav3.md` — why Navigation 3 over AndroidX Nav 2 / Voyager / Decompose
- `0005-result-domain-error.md` — why Result<T> + sealed DomainError over Arrow Either / exceptions
- `0006-dispatcher-provider.md` — why inject DispatcherProvider over using Dispatchers.IO directly

These document *why this stack was chosen for this project* and serve as starting context. The user can amend or supersede them per project.

### When to write a new ADR

- Adopting an opt-in library (Sentry, SQLDelight, Ktor)
- Changing a core stack choice (rare — typically supersedes an existing ADR)
- Architectural decision affecting multiple modules (e.g. moving `:auth` out of `:data`)
- Distribution / release / observability tier change

Skip for: dependency version bumps, internal refactors, bug fixes.

### ADR template

```markdown
# NNNN. <title>

Date: <YYYY-MM-DD>
Status: Accepted | Superseded by [NNNN](NNNN-...)

## Context
<what's driving this decision>

## Decision
<what we will do>

## Consequences
<what becomes easier, what becomes harder>
```

## docs/ROADMAP.md (optional)

Not scaffolded by default. Add when the project has > ~10 must-have features that warrant explicit phasing.

When added, structure as phases with target dates:

```markdown
# Roadmap

## Phase 1 — MVP (target: YYYY-MM-DD)
- <must-have 1>
- <must-have 2>

## Phase 2 — Polish (target: YYYY-MM-DD)
- <feature>

## Phase 3 — Growth (target: YYYY-MM-DD)
- <feature>
```

Updated as scope shifts. Linked from `CLAUDE.md` if present.

## .github/ISSUE_TEMPLATE/

Three templates ship:

### `bug_report.yml`

```yaml
name: Bug report
description: Something is broken or behaving unexpectedly
labels: [bug]
body:
  - type: textarea
    attributes: { label: What happened?, description: Concrete steps + expected vs actual }
    validations: { required: true }
  - type: input
    attributes: { label: Platform, placeholder: "Android 14 / iOS 17 / desktop macOS 14 / web Chrome 120" }
  - type: input
    attributes: { label: App version, placeholder: "v0.3.2" }
  - type: textarea
    attributes: { label: Logs / screenshots }
```

### `feature_request.yml`

```yaml
name: Feature request
description: A new capability or improvement
labels: [enhancement]
body:
  - type: textarea
    attributes: { label: Problem, description: What user problem does this solve? }
    validations: { required: true }
  - type: textarea
    attributes: { label: Proposed solution }
  - type: textarea
    attributes: { label: Alternatives considered }
```

### `adr_proposal.yml`

```yaml
name: ADR proposal
description: Propose an architecture decision worth recording
labels: [adr]
body:
  - type: input
    attributes: { label: Proposed title, placeholder: "Switch from X to Y" }
    validations: { required: true }
  - type: textarea
    attributes: { label: Context }
    validations: { required: true }
  - type: textarea
    attributes: { label: Decision }
  - type: textarea
    attributes: { label: Consequences }
```

## Design references

Per-project Figma URL (or other design tool) lives in `CLAUDE.md` so Claude has the link in context every session.

`:ui` design tokens stay in code as source-of-truth for spacing/colors/typography that the running app uses. Figma is the visual brief; tokens are the implementation.

## Linking from CLAUDE.md

The scaffolded `CLAUDE.md` references `docs/MVP_SPEC.md` so Claude reads it. ADRs are not auto-loaded — Claude reads them when relevant context appears (e.g. user asks "why are we using Koin").
