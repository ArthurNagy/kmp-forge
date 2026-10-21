---
name: backlog-issue-authoring
description: Write or refine a GitHub issue for a kmp-forge project so it can enter the backlog — Problem, WHEN/THEN acceptance criteria, Out of scope, Depends on, Needs a human first, Change name; splitting bigger work into a parent issue with one-PR sub-issues; priority labels. Use in a kmp-forge project (its CLAUDE.md links kmp-forge's docs as its rules) when filing a feature, bug or chore issue, turning an idea or a vague issue into a workable one, splitting work too big for one PR, or when /kmp-forge-refine or the kmp-product-owner agent drafts issues. Never applies the `ready` label.
---

# Backlog issue authoring — kmp-forge style

In a kmp-forge project, GitHub issues are the single source of work: open issues labeled `ready` are the backlog that people and the autonomous build loop work from. An issue is **workable** when someone who has never seen the conversation could propose its OpenSpec change without asking a question. Its readers: the human who approves it, the `kmp-architect` agent (in `/kmp-forge-refine`, for a parent issue or one that needs design — it adds technical **Notes** and **Out of scope** lines), the proposer that turns it into an OpenSpec change (`/opsx:propose`, by hand or in the autonomous loop), and `kmp-qa`, which checks its acceptance criteria. Canonical rules: the plugin's `docs/product-workflow.md`.

## The one rule about `ready`

**Never apply `ready`.** It is how a human approves work. File and refine issues freely, add `priority:*` / type labels when asked, but finish by telling the human which issues to promote — and give them the command to run themselves:

```
gh issue edit 41 42 43 --add-label ready
```

(With the autonomous loop installed, its merge guard denies applying `ready` outright.)

## Shape — the Feature / backlog item form

Write the body as the form renders it (`### <label>` sections); `scripts/issues.sh` and the loop's workers parse these exact headings, so keep them verbatim:

```markdown
### Problem

<who has the problem, what it costs them, why now — product terms, not implementation>

### Acceptance criteria

- WHEN <a user or caller does X / state is Y> THEN <observable outcome>
- WHEN … THEN …

### Out of scope

- <binding exclusions: layers not to touch, features not to build, decisions not to make>

### Depends on

#12, #15

### Needs a human first

<credentials, a URL, a store listing — anything only a person can provide; empty if none>

### Change name

add-settings-store

### Notes

<Figma link, prior art, hints, technical notes — optional; guidance for the design, never scope>
```

Empty optional sections render as `_No response_`; omit them or leave that marker. Title: what the user gets, imperative, ≤ 60 chars ("Remember the chosen theme across restarts"), not the implementation ("Add DataStore to SettingsRepository").

## What makes it workable

**Acceptance criteria** — each line becomes at least one OpenSpec scenario and one test, and QA checks the user-visible ones on an emulator. So each must be:
- observable — what the user sees or the caller gets, never "uses DataStore" or "adds a ViewModel";
- specific — concrete inputs and outcomes, including the unhappy path (offline, empty, invalid) when it matters;
- independent — one outcome per line.

✓ `WHEN the user picks Dark in Settings THEN the app switches to dark colors immediately`
✓ `WHEN the app restarts THEN the last picked theme is applied before the first frame`
✗ `Theme works correctly` (not checkable) · ✗ `Store the theme in DataStore` (implementation)

**Size: one change, one PR.** Roughly ≤ 5 acceptance criteria and one feature module (plus the `:domain` / `:data` it needs). Bigger → it is a **parent issue**: keep its Problem as the whole outcome and split the work into GitHub **sub-issues** (`gh issue create --parent <n>`, or `gh issue edit <sub> --parent <n>` for an existing one), each independently shippable and ordered so each **Depends on** only the ones before it. Slice by user-visible outcome (vertical: domain → data → UI for one behavior), never by layer ("all the domain models" is not a sub-issue). Never put the parent in a sub-issue's **Depends on**: a parent stays open, and the queue skips an issue while anything it depends on is open — it skips the parent itself too, since its sub-issues are the work. In `/kmp-forge-refine` the `kmp-architect` agent then fits the work into the codebase — for a parent, and for a single issue that adds a module, a data source or library, a platform or a cross-cutting concern: it fixes the technical order, may add one enabling `chore` issue for infrastructure (applying SQLDelight, adding a platform, extracting a module), appends technical **Notes** and **Out of scope** lines to each issue, and drafts the ADRs the work needs.

**Out of scope** is binding for whoever implements it — use it to stop scope creep you can foresee ("no sync across devices", "no new feature module", ":domain stays untouched").

**Depends on** only for real ordering constraints (needs an entity or screen another issue creates). The loop skips an issue while any dependency is open.

**Needs a human first** — never let a slice depend on a secret or external setup silently; the loop stops on an unmet precondition instead of stubbing past it.

**Change name** — kebab-case, verb first (`add-…`, `wire-…`, `fix-…`), ≤ 40 chars. The loop prefixes the issue number (`42-add-settings-store`) for the OpenSpec change and the branches.

## Bugs and chores

- **Bug** (`bug` label, Bug report form) — its headings, verbatim (`scripts/issues.sh` and the loop read
  **Acceptance criteria**, **Depends on** and **Change name** from a bug the same way):

  ```markdown
  ### What happened?

  <steps to reproduce; expected vs actual>

  ### Acceptance criteria

  - WHEN the device is offline THEN the gallery shows the cached photos instead of an error

  ### Depends on

  #12

  ### Change name

  fix-offline-gallery

  ### Platform

  iPhone 15 · iOS 17

  ### App version

  v0.3.2

  ### Logs / screenshots

  <log excerpt>
  ```

  **What happened?** is required; add an acceptance criterion for the fix whenever "expected" is ambiguous — each
  becomes a regression test. Its PR is a `fix(…)`.
- **Chore** (`chore` label): build, tooling or maintenance with no user-visible behavior — including the enabling
  issue the `kmp-architect` adds before infrastructure-dependent work (applying SQLDelight, adding a
  platform). It uses the **backlog form's shape** above, labeled `chore` instead of `enhancement`: **Problem** says why
  the work is needed now, **Acceptance criteria** are done-conditions a reviewer can check (`WHEN the project builds THEN
  :data generates AppDatabase with the photos table and its query tests pass`), plus **Out of scope** / **Depends on** /
  **Change name** as usual. Its PR is not a `feat:` (so CI's spec-link check does not apply).

## Priority

Unlabeled = normal. `priority:high` jumps the queue (blocking a release, user-facing breakage); `priority:low` trails it (nice-to-have). Inside a level the oldest issue goes first — file issues in the order they should run. Suggest priorities; the human decides.

## Refining an existing issue

- Vague but yours → edit it into the shape above (`gh issue edit <n> --body-file …`), asking the human for anything you would otherwise guess.
- From someone outside the project's approvers → do not edit their text into a trusted item: file the refined version as a new issue ("Refined from #<n>"), then comment on the original with the link (closing it is the human's call). The loop only trusts issues whose author is an approver.
- Duplicate of an open issue → say so; don't file a second one.
