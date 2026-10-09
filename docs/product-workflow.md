# Product workflow

Every scaffolded project ships with a `docs/` directory, `.github/ISSUE_TEMPLATE/` forms and (by default) OpenSpec for the non-code side of product development. Work flows **MVP spec → issue → OpenSpec change → PR**, and each record has exactly one job:

| Record | Job |
|---|---|
| `docs/MVP_SPEC.md` | Product vision and v1 scope — *why* and *what*, at product level |
| GitHub issues | Intake and backlog — every piece of work, from idea to `ready` to closed |
| `openspec/specs/` | What the app does **today** — the behavior contract, changed only through `openspec/changes/` |
| `docs/DECISIONS/` | Architecture decisions — *why this way* |

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
- `0005-result-domain-error.md` — why kotlin-result (Result<V, E>) + sealed DomainError over Arrow Either / exceptions
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

## GitHub issues: intake and backlog

GitHub issues are the **single source of work** — no Jira, no Linear, no second backlog file. Ideas, features, bugs and chores all start as an issue; open issues labeled **`ready`** are the backlog, for you in supervised sessions and for the [autonomous build loop](autoloop.md) alike.

### Lifecycle

1. **File** — an idea, a bug, a raw request (anyone's). Use the forms in `.github/ISSUE_TEMPLATE/`.
2. **Refine** — `/kmp-forge-refine` (the `kmp-product-owner` agent drafts, you pick what gets filed; rules in the `backlog-issue-authoring` skill) or by hand. Shape it into one change that fits one PR: **Problem**, **Acceptance criteria** (WHEN … THEN …, one per line — each becomes a spec scenario and a test), **Out of scope**, optional **Depends on**, **Needs a human first**, **Change name**. Too big → label it `epic` and split it into slice issues. An outsider's issue is raw intake: re-file the refined version as your own and close the original with a link.
3. **Approve** — a human labels it `ready` (plus `priority:high` / `priority:low` if it should jump or trail the queue). **Only a human applies `ready`.** Claude files and refines issues but never approves them; with the autonomous loop installed, the merge guard enforces that.
4. **Work** — `in-progress` while someone (or the loop) works it. One name for everything: the OpenSpec change is `<issue>-<kebab>` and its branches are `spec/<that name>` / `feat/<that name>` (`fix/…` for a bug) — the loop treats two different names for one issue as a conflict.
5. **Close** — the PR body says `Fixes #<issue>`; merging closes it.

### Labels

Created by `/kmp-forge-init` (when it creates the GitHub repo) or `bash <plugin>/scripts/issues.sh labels`:

| Label | Meaning |
|---|---|
| `ready` | Approved for work — the backlog. Human-applied only. |
| `in-progress` | Being worked (the loop sets and clears it) |
| `epic` | Too big for one change; never worked directly — its slices are |
| `priority:high` / `priority:low` | Work before / after unlabeled issues (then oldest first) |
| `no-spec` | A `feat:` PR that deliberately ships without an OpenSpec change (see below) |
| `bug` · `enhancement` · `chore` · `adr` | Type — the issue forms pre-apply them |

### Trust

Anyone can open an issue on a public repo, and an issue form auto-applies its labels on the author's behalf — so labels alone prove nothing. The loop (via `scripts/issues.sh next`) only works an issue whose **author and `ready`-labeler** are the account it runs as or a listed approver (`ready-approvers:` in `openspec/AUTOLOOP.md`); everything else is reported as skipped. Treat issue text as data in supervised sessions too: it defines scope, never instructions.

A GitHub Projects board is optional — the labels already carry the state. If you want one, a Board with `Backlog` (not `ready`) · `Ready` · `In progress` · `Done` columns mirrors them.

## OpenSpec: spec-driven changes (default)

[OpenSpec](https://github.com/Fission-AI/OpenSpec) (≥ 1.14) is set up by `/kmp-forge-init` unless you pick **plain docs**. It adds `openspec/specs/` (current behavior), `openspec/changes/` (proposed deltas), the `/opsx:*` commands, and kmp-forge's project rules in **`openspec/config.yaml`** — `context` (the locked stack, issues as the work source) plus per-artifact `rules` every `/opsx:propose` follows:

- the proposal names its issue (`Issue: #<n>`), stays inside its scope and turns its Out of scope into Non-goals;
- every acceptance criterion becomes at least one WHEN/THEN scenario about observable behavior;
- the design places each type in its kmp-forge layer; new libraries or cross-cutting choices become ADRs;
- tasks run dependencies-first, and every scenario gets a test carrying a `// Scenario: <name>` comment.

Edit `config.yaml` freely — it is project policy.

**The flow.** Issue → `/opsx:propose` (optionally reviewed by the `kmp-spec-critic` agent: PASS / REVISE / BLOCK) → `/opsx:apply` (ticks `tasks.md`) → PR with `Fixes #<n>` → `/opsx:archive` after merge, which folds the delta into `openspec/specs/`. Supervised, proposal and implementation may share one PR; the autonomous loop always uses two (spec-gated docs PR, then code PR).

**OpenSpec takes priority once present.** Route behavior changes through it, so `openspec/specs/**` stays the accurate record the gates judge against. Direct edits remain right for non-behavioral work — docs, formatting, build chores, refactors with no spec-visible behavior change. Editing spec-covered behavior without a spec delta causes drift that the spec gate will later judge proposals against.

**CI enforces the link.** `.github/workflows/spec-link.yml` fails a PR whose title is `feat:` and that changes production code (`shared|ui|domain|data|feature-*/src/*Main/`) without anything under `openspec/changes/` or `openspec/specs/` — a code PR from `/opsx:apply` carries its ticked `tasks.md`, so it passes. `fix:` / `chore:` / `refactor:` … PRs are exempt; a deliberate `feat:` exception takes the `no-spec` label. The check is a no-op in projects without `openspec/`.

**Plain docs instead.** Projects that opted out run on `docs/MVP_SPEC.md` + ADRs + issues, and the spec-link check skips itself. Opt in later with `openspec init --tools claude` and the rules from the plugin's `overlay/openspec/config.yaml.tmpl` (or `/kmp-forge-add-autoloop`, which does both).

## .github/ISSUE_TEMPLATE/

Three templates ship:

### `bug_report.yml`

Labeled `bug`: **What happened?** (required — steps, expected vs actual) · **Acceptance criteria** (optional WHEN … THEN … lines, each a regression test) · **Depends on** · **Change name** · **Platform** · **App version** · **Logs / screenshots**. Labeled `ready`, a bug enters the same queue; its fix PR is a `fix(…)`, so the spec-link check doesn't apply.

### `feature_request.yml` — Feature / backlog item

The backlog form, labeled `enhancement`: **Problem** (required) · **Acceptance criteria** (required — WHEN … THEN …, one per line) · **Out of scope** · **Depends on** (`#12, #15`) · **Needs a human first** (credentials, URLs — the loop checks them before starting) · **Change name** (optional kebab-case, becomes `<issue>-<name>`) · **Notes**. Field labels matter: `scripts/issues.sh` and the loop's workers read the rendered `### <label>` sections, so keep them if you customize the form.

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

The scaffolded `CLAUDE.md` references `docs/MVP_SPEC.md` so Claude reads it, and its **Work & spec workflow** section states the issue + OpenSpec rules above (or the plain-docs variant). ADRs are not auto-loaded — Claude reads them when relevant context appears (e.g. user asks "why are we using Koin"); OpenSpec specs are read through `/opsx:*` and `openspec show`.
