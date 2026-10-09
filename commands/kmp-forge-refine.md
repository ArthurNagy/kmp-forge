---
description: Product-owner pass over the backlog — turn an idea, some vague issues, or the MVP spec's uncovered gaps into workable GitHub issues (via the kmp-product-owner agent), file the ones you pick, and print the command to approve them. Never applies `ready`.
argument-hint: "<idea text> | #12 #15 | --gaps"
---

# /kmp-forge-refine

Backlog refinement for a kmp-forge project (the backlog is GitHub issues; `ready` = approved — see the plugin's [docs/product-workflow.md](https://github.com/arthurnagy/kmp-forge/blob/main/docs/product-workflow.md)). The `kmp-product-owner` agent does the reading and drafting in its own context; you present its drafts, file the ones the user picks, and hand the approval back to the user.

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

## 4. Choose

Show each draft compactly — `k. <title>` · labels · `why` · its acceptance criteria — then the `QUEUE` suggestions. Ask with `AskUserQuestion` (`multiSelect: true`, up to 4 drafts per question, several questions if needed) which drafts to file; offer editing a draft before filing ("Other" → apply the user's change to that draft).

## 5. File

Make sure the workflow labels exist (idempotent; creates any missing label on GitHub):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/issues.sh" labels
```

File the chosen drafts **in their listed order** (dependencies first). Write each body to a temp file in your scratchpad, replacing every `draft:<j>` with the number draft *j* got:

```bash
gh issue create --title "<title>" --label "<labels, comma-separated, without ready>" --body-file "<body file>"
```

- `action: replace #<n>` → after creating the refined issue, comment on the original: `gh issue comment <n> --body "Refined into #<new>."` Ask before closing the original (`gh issue close <n> --reason "not planned"`) — it may be someone else's issue.
- `QUEUE` suggestions (priority changes on existing issues) → apply only the ones the user confirms (`gh issue edit <n> --add-label priority:high`, `--remove-label …`). Never `ready`.

## 6. Hand back

```
✓ Filed: #41 Remember the chosen theme · #42 … (labels: enhancement[, priority:…])
✓ Refined: #12 → #43 (original <closed | left open>)
~ Queue: <priority changes applied, or none>

Approve the ones to build — only you apply `ready`:
  gh issue edit 41 42 43 --add-label ready
```

## Notes

- Drafts follow the `backlog-issue-authoring` skill: the issue form's `### <label>` sections verbatim (the loop parses them), observable WHEN/THEN acceptance criteria, one change per issue, epics split into slices.
- The agent is read-only; every GitHub write happens here, in the main conversation, after the user chose it.
- The autonomous loop calls the same agent in `gaps` mode when its queue empties (`queue-empty-refine: on` in `openspec/AUTOLOOP.md`) and files at most 3 drafts — also without `ready`.
