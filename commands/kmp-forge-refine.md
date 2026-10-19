---
description: Product-owner pass over the backlog — turn an idea, some vague issues, or the MVP spec's uncovered gaps into workable GitHub issues (via the kmp-product-owner agent; for an epic, the kmp-architect agent then fits it into the codebase and drafts its ADRs), file the ones you pick, and print the command to approve them. Never applies `ready`.
argument-hint: "<idea text> | #12 #15 | --gaps"
---

# /kmp-forge-refine

Backlog refinement for a kmp-forge project (the backlog is GitHub issues; `ready` = approved — see the plugin's [docs/product-workflow.md](https://github.com/arthurnagy/kmp-forge/blob/main/docs/product-workflow.md)). The `kmp-product-owner` agent does the reading and drafting in its own context; when an epic is in play, the `kmp-architect` agent then designs how it fits the codebase. You present their drafts, file the ones the user picks, and hand the approval back to the user.

**You never apply the `ready` label** — not even if the user asks you to in passing. Print the command for them to run (`! gh issue edit … --add-label ready` runs it from this prompt). With the autonomous loop installed, the merge guard denies it anyway.

## 1. Preconditions

Run from the project root:

```bash
gh auth status >/dev/null 2>&1 || echo "✗ gh not authenticated — run: gh auth login"
gh repo view --json nameWithOwner -q .nameWithOwner || echo "✗ origin is not a reachable GitHub repo"
[[ -f docs/MVP_SPEC.md ]] || echo "⚠ no docs/MVP_SPEC.md — --gaps needs it (run /kmp-forge-spec first)"
```

## 2. Mode from the argument

- `--gaps` (or no argument) → `mode: gaps` — draft the next slices the MVP spec needs that nothing covers yet.
- issue references (`#12 #15`, or numbers) → `mode: issues` — refine those.
- anything else → `mode: idea`, `request` = the text verbatim.

## 3. Draft

Spawn `kmp-forge:kmp-product-owner` with `mode`, `request`, `max: 5`, `claude_plugin_root: ${CLAUDE_PLUGIN_ROOT}`. Its final message is a structured block.

- `NEEDS_INPUT` → ask the user its `QUESTIONS` via `AskUserQuestion`, then re-spawn it with the answers appended to `request`.
- `NOTHING` → report its NOTES and stop.
- `FAILED` → report the `FAILURE:` line and stop.

## 4. Design (epics only)

Skip this step unless an epic is in play: a draft labeled `epic`, or (mode `issues`) a referenced issue labeled `epic` (`gh issue view <n> --json labels`).

For each epic, spawn `kmp-forge:kmp-architect` with:
- `epic` — `draft:<k>` with that draft's block attached verbatim, or `#<n>`;
- `slices` — every draft whose `epic:` line names it (blocks attached verbatim), plus, for an existing epic `#<n>`, its open slice issues — the ones whose **Notes** carry a `Part of #<n>` line (written when they were filed, step 6):
  ```bash
  gh issue list --state open --limit 200 --json number,body \
    --jq '.[] | select(.body | test("Part of #<n>\\b")) | .number'
  ```
- `claude_plugin_root: ${CLAUDE_PLUGIN_ROOT}`.

- `NEEDS_INPUT` → ask its `QUESTIONS` via `AskUserQuestion`, re-spawn it with the answers appended.
- `FAILED` → report the `FAILURE:` line and continue with the product owner's drafts unchanged — say the epic went undesigned.
- `OK` → apply its `SLICES` to the drafts, in the order it lists them (the epic's own draft stays first):
  - `keep draft:<k>` / `keep #<n>` → unchanged. `drop draft:<k>` → remove it (its `reason` says what covers it). `add` → a new draft (`action: create`, its `title`, `labels`, `body` with the **Depends on** section set from `depends on`, and `epic:` = this epic), referred to as `slice:<s>`.
  - Splits and merges the architect recommends under `NOTES` are not applied — acceptance criteria are product. Show them in step 5; if the user wants one, re-run the product owner (`mode: issues`, or the idea with the recommendation appended) rather than editing criteria here.
  - `amend draft:<k>` → edit that draft's body: replace the **Depends on** section with the new value (unless `unchanged`); append the `out of scope` lines to **Out of scope** and the `needs a human first` text to **Needs a human first**; append the `notes` to **Notes** under a `Technical notes (kmp-architect):` line (replacing a `_No response_` marker). Keep every `### <label>` heading verbatim — the loop parses them.
  - `amend #<n>` → the same edits, applied to that existing issue in step 6 if the user accepts them.

## 5. Choose

Show each epic's design first — its `DESIGN` lines, `RISKS`, `NOTES` and the titles of its ADR drafts — then each draft compactly: `k. <title>` · labels · `why` · its acceptance criteria (plus `+ technical notes` / `+ out of scope` where the architect amended it), then the `QUEUE` suggestions. Ask with `AskUserQuestion` (`multiSelect: true`, up to 4 options per question, several questions if needed):
- which drafts to file — offer editing a draft before filing ("Other" → apply the user's change to that draft);
- which ADR drafts to write, when there are any;
- which amendments to existing issues (`amend #<n>`) to apply, when there are any.

## 6. File

**ADRs first** (only the chosen ones), so the slices can cite them. For each, take the next free number — the highest `NNNN` in `docs/DECISIONS/` plus one, four digits — and write `docs/DECISIONS/NNNN-<kebab-case title, 3–6 words>.md` with the Write tool in the `adr-authoring` skill's format: `# NNNN. <title>`, `Date: <today>`, `Status: Accepted`, then the draft's Context / Decision / Consequences. **Do not commit them** — the user reviews and commits. In every draft, replace `adr:<j>` with `ADR NNNN (docs/DECISIONS/NNNN-….md)`; a citation of an ADR the user didn't pick is dropped from the note.

Make sure the workflow labels exist (idempotent; creates any missing label on GitHub):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/issues.sh" labels
```

File the chosen drafts **in their listed order** (dependencies first). Write each body to a temp file in your scratchpad, replacing every `draft:<j>` / `slice:<s>` with the number that draft got. A draft with an `epic:` line gets `Part of #<epic number>` as the first line of its **Notes** (replacing a `_No response_` marker) — the one link from a slice to its epic, which a later `/kmp-forge-refine #<epic>` looks up. Never record membership in **Depends on**: the queue skips an issue while anything it depends on is open, and an epic stays open.

```bash
gh issue create --title "<title>" --label "<labels, comma-separated, without ready>" --body-file "<body file>"
```

- `action: replace #<n>` → after creating the refined issue, comment on the original: `gh issue comment <n> --body "Refined into #<new>."` Ask before closing the original (`gh issue close <n> --reason "not planned"`) — it may be someone else's issue.
- Accepted `amend #<n>` → `gh issue view <n> --json body -q .body` into a temp file, apply the section edits from step 4 there, then `gh issue edit <n> --body-file <file>`.
- Each designed epic → post the design on the epic issue (the one just filed, or `#<n>`): `gh issue comment <epic> --body-file <file>` with a `### Technical design (kmp-architect)` heading, the `DESIGN` lines, the slice order as issue numbers, the ADR paths and the `RISKS`.
- `QUEUE` suggestions (priority changes on existing issues) → apply only the ones the user confirms (`gh issue edit <n> --add-label priority:high`, `--remove-label …`). Never `ready`.

## 7. Hand back

```
✓ Filed: #41 Remember the chosen theme · #42 … (labels: enhancement[, priority:…])
✓ Refined: #12 → #43 (original <closed | left open>)
✓ Designed: epic #40 — slices #41 → #42 → #43, design posted on #40
✍ ADRs written, uncommitted: docs/DECISIONS/0007-use-sqldelight-for-photo-cache.md
   review, then commit them (docs(adr): …) before approving the slices that cite them — the loop reads main
~ Queue: <priority changes applied, or none>

Approve the ones to build — only you apply `ready`:
  gh issue edit 41 42 43 --add-label ready
```

Leave out the lines that don't apply. An epic itself is never approved — its slices are.

## Notes

- Drafts follow the `backlog-issue-authoring` skill: the issue form's `### <label>` sections verbatim (the loop parses them), observable WHEN/THEN acceptance criteria, one change per issue, epics split into slices.
- Both agents are read-only; every GitHub write and every file written happens here, in the main conversation, after the user chose it.
- The architect runs for epics only, and only here: the autonomous loop calls the product owner in `gaps` mode when its queue empties (`queue-empty-refine: on` in `openspec/AUTOLOOP.md`) and files at most 3 drafts — also without `ready` — but never the architect. An epic drafted that way gets its design when you run `/kmp-forge-refine #<epic>`.
- The architect's technical notes reach implementation through each slice's **Notes** section, which the loop's proposer passes to `/opsx:propose` as guidance (scope stays Problem / Acceptance criteria / Out of scope).
