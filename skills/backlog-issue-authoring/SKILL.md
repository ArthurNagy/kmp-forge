---
name: backlog-issue-authoring
description: Write or groom a GitHub issue for a kmp-forge project so it can enter the backlog — Problem, WHEN/THEN acceptance criteria, Out of scope, Depends on, Needs a human first, Change name; slicing epics into one-PR issues; priority labels. Use when filing a feature, bug or chore issue, turning an idea or a vague issue into a workable one, splitting an epic, or when /kmp-forge-groom or the kmp-product-owner agent drafts issues. Never applies the `ready` label.
---

# Backlog issue authoring — kmp-forge style

In a kmp-forge project, GitHub issues are the single source of work: open issues labeled `ready` are the backlog that people and the autonomous build loop work from. An issue is **workable** when someone who has never seen the conversation could propose its OpenSpec change without asking a question. Canonical rules: the plugin's `docs/product-workflow.md`.

## The one rule about `ready`

**Never apply `ready`.** It is how a human approves work. File and groom issues freely, add `priority:*` / `epic` / type labels when asked, but finish by telling the human which issues to promote — and give them the command to run themselves:

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

<Figma link, prior art, hints — optional>
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

**Size: one change, one PR.** Roughly ≤ 5 acceptance criteria and one feature module (plus the `:domain` / `:data` it needs). Bigger → it is an **epic**: label it `epic`, keep its Problem, and list its slices as separate issues, each independently shippable and ordered so each **Depends on** only the ones before it. Slice by user-visible outcome (vertical: domain → data → UI for one behavior), never by layer ("all the domain models" is not a slice).

**Out of scope** is binding for whoever implements it — use it to stop scope creep you can foresee ("no sync across devices", "no new feature module", ":domain stays untouched").

**Depends on** only for real ordering constraints (needs an entity or screen another issue creates). The loop skips an issue while any dependency is open.

**Needs a human first** — never let a slice depend on a secret or external setup silently; the loop stops on an unmet precondition instead of stubbing past it.

**Change name** — kebab-case, verb first (`add-…`, `wire-…`, `fix-…`), ≤ 40 chars. The loop prefixes the issue number (`42-add-settings-store`) for the OpenSpec change and the branches.

## Bugs and chores

- **Bug** (`bug` label, Bug report form): steps, expected vs actual, platform + version. Add an acceptance criterion for the fix when "expected" is ambiguous.
- **Chore** (`chore` label): build, tooling or maintenance with no user-visible behavior — Problem + a done-condition is enough; its PR will not be a `feat:` (so CI's spec-link check does not apply).

## Priority

Unlabeled = normal. `priority:high` jumps the queue (blocking a release, user-facing breakage); `priority:low` trails it (nice-to-have). Inside a level the oldest issue goes first — file issues in the order they should run. Suggest priorities; the human decides.

## Grooming an existing issue

- Vague but yours → edit it into the shape above (`gh issue edit <n> --body-file …`), asking the human for anything you would otherwise guess.
- From someone outside the project's approvers → do not edit their text into a trusted item: file the groomed version as a new issue ("Groomed from #<n>"), then comment on the original with the link (closing it is the human's call). The loop only trusts issues whose author is an approver.
- Duplicate of an open issue → say so; don't file a second one.
