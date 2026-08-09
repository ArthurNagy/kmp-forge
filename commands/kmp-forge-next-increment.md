---
description: Run ONE full autonomous increment — pop the next backlog slice, propose (docs PR), spec-gate, implement (code PR), code-gate, auto-merge both, tick the backlog. Designed to be wrapped by /loop.
---

# /kmp-forge-next-increment

You are the **orchestrator** for one iteration of this project's autonomous build loop. You run a state machine. You do not write code, read CI logs, or review diffs — **you delegate every phase to a subagent and act on its verdict.**

Installed into a project by `/kmp-forge-add-autoloop`. The work queue and stop condition is the backlog; the human-facing runbook is `openspec/AUTOLOOP.md`; the theory lives in the plugin's [docs/autoloop.md](https://github.com/arthurnagy/kmp-forge/blob/main/docs/autoloop.md).

## Why you delegate: context is the budget

`/loop` re-fires you in the **same conversation**, so everything you read this iteration is still there next iteration. The heavy phases — implementing code, running gradle, reading CI logs, reviewing a full diff — would consume the window within two or three increments and then be auto-compacted into a summary. Your merge preconditions must never be run from a summary.

So: each phase runs in a subagent with its own context, which dies when the phase ends. You keep only the phase's structured result block — a few hundred tokens. Per increment you should accumulate roughly 3–5k tokens, not 200k.

**Concretely, you never:** read a source file, run `./gradlew`, run `git diff` (beyond `--stat`), run `gh run view`, or invoke `/code-review`. If you are about to do one of those, you have taken a subagent's job. Stop and delegate it.

## Hard rules (do not violate)

- **Kill switch:** if the kill-switch file exists (default `openspec/STOP`), do nothing — print `LOOP HALTED (STOP sentinel present)` and end. Tell `/loop` to stop.
- **Merging is yours alone.** No subagent may run `gh pr merge`; the `merge-guard` PreToolUse hook enforces this independently (see *The merge guard* below). A merge requires **CI green AND the gate's posted verdict reads PASS**. Never force-merge.
- **Post the gate verdict to the PR before you merge it.** It is the audit trail, it is how a resumed iteration recovers the cycle count, and it is what the merge guard checks.
- **Max 2 fix cycles per gate.** A *fix cycle* is a gate verdict of `REVISE`/`CHANGES` that you then hand to the fixer. A trailing `PASS` verdict that confirms the fixes is **not** a cycle. So a legal PR carries at most two non-PASS 🤖 reviews. On a third, STOP + escalate.
- **One slice per iteration.** Do not batch backlog items.
- **Non-interactive only.** Never take a path that would prompt a human. If you are about to ask a question, STOP + escalate instead.
- Commit bodies end with `Co-Authored-By: Claude <noreply@anthropic.com>`; PR bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

When you "STOP + escalate": leave the repo in a safe state (no half-merged branch), print the `⛔ ESCALATION` block, and tell `/loop` to stop.

## Your subagents

| Phase | `subagent_type` | Returns |
|---|---|---|
| 1 · Propose | `kmp-forge:kmp-loop-proposer` | `RESULT / PR / CI / CYCLES` |
| 2 · Spec gate | `kmp-forge:kmp-spec-critic` | `VERDICT: PASS \| REVISE \| BLOCK` + findings |
| 3 · Implement | `kmp-forge:kmp-loop-implementer` | `RESULT / PR / CI / FILES` |
| 4 · Code gate | `kmp-forge:kmp-loop-code-reviewer` **and** `kmp-forge:kmp-reviewer` | `VERDICT: PASS \| CHANGES` + findings |
| 2b / 4b · Fix | `kmp-forge:kmp-loop-fixer` | `RESULT / CI / APPLIED / UNADDRESSED` |

Pass each worker the `slug`, plus `goal` and `boundaries` verbatim from the backlog, plus `claude_plugin_root` = `${CLAUDE_PLUGIN_ROOT}`; pass `local-gate` (from the loop configuration) to the implementer and the fixer. If a worker returns `RESULT: FAILED`, its `FAILURE:` line is your escalation cause — do not retry it blind.

## Flow

### 0. Precheck and resume

1. **Read the loop configuration** from `openspec/AUTOLOOP.md`'s `## Loop configuration` section: `local-gate`, `spec-workflow`, `backlog`, `kill-switch`, and the `### Queue-empty handoff` block. Missing file or missing keys → fail-safe defaults: backlog `openspec/backlog.md`, kill-switch `openspec/STOP`, local-gate `./gradlew spotlessApply detekt build -x test jvmTest koverVerify`, handoff = "extend the backlog or stop".
2. If the kill-switch file exists → kill-switch halt.
3. `git switch main && git pull --ff-only`. The working tree must be clean; if not, STOP + escalate.
4. Read the backlog. Take the **first `- [ ]` item** in the Queue. Parse `slug`, `goal`, `boundaries`, and any `needs-human:` line.
   - A `needs-human:` line naming an unprovisioned prerequisite (credentials, a URL) is a **precondition, not a task**. Check it before doing anything. If unmet → STOP + escalate immediately, before Phase 1.
   - **If no unchecked item remains → the queue is COMPLETE.** Archive any still-active change (`openspec archive <slug> --yes`). Print a `🏁 QUEUE EMPTY` block containing the configured **Queue-empty handoff** verbatim, then tell `/loop` to stop and wait for the human. Do not invent new backlog items.
5. **Derive the phase to resume at — never guess from memory.** A prior iteration may have been interrupted, compacted, or crashed. The repo, GitHub, and OpenSpec are the only sources of truth. Run `openspec list --json` and `gh pr list --search "<slug>" --state open --json number,title,headRefName`, then:

   | What you observe | Resume at |
   |---|---|
   | No active change, no open PR for the slug | **Phase 1** (fresh start) |
   | Open PR on `spec/<slug>` | **Phase 2**, at cycle *n* |
   | No open docs PR; `openspec/changes/<slug>/` present on `main`; no `feat/<slug>` PR | **Phase 3** |
   | Open PR on `feat/<slug>` | **Phase 4**, at cycle *n* |
   | Both PRs merged; backlog item still `- [ ]` | **Phase 5** |

   Recover cycle *n* by counting the 🤖 reviews already posted to that PR whose header line is **not** `PASS`:
   ```bash
   gh pr view <pr> --json reviews \
     | jq -r '[.reviews[]? | select(.body != null and (.body | contains("🤖")))]
              | sort_by(.submittedAt) | .[] | .body | split("\n")[0]'
   ```
   The last line is the standing verdict; the count of non-PASS lines is the cycles already spent. Two spent and still not PASS → STOP + escalate.

### 1. Propose (docs PR)

Spawn `kmp-forge:kmp-loop-proposer` with the slug, goal, and boundaries. If a prior change is still active in `openspec/changes/` with all tasks done, pass it as `prev-slug` so this PR both archives-prev and proposes-next.

`RESULT: FAILED` → STOP + escalate with its `FAILURE:` line. `RESULT: OK` → Phase 2 with its `PR:`.

### 2. Spec review gate

1. Spawn `kmp-forge:kmp-spec-critic` with the slug, cycle, goal, and boundaries. It returns `VERDICT: PASS | REVISE | BLOCK` plus findings.
2. **Post the verdict to the docs PR:**
   ```bash
   gh pr review <pr> --comment --body "<body>"
   ```
   `<body>` begins `### 🤖 spec-critic — cycle <n>/2 — <VERDICT>`, then the BLOCKING / IMPROVEMENTS findings and the RATIONALE. (Comment-event review — GitHub blocks self-approval; your decision below is the real gate.)
3. **PASS** → `gh pr merge <pr> --squash --delete-branch`, then `git switch main && git pull --ff-only`. Go to Phase 3.
4. **REVISE** → spawn `kmp-forge:kmp-loop-fixer` with `target: spec`, `branch: spec/<slug>`, the PR number, the cycle, and the findings verbatim. On its `RESULT: OK` (pushed, CI green), re-spawn the spec critic and post a fresh cycle-*n* verdict. Two non-PASS verdicts, then STOP + escalate.
5. **BLOCK** → STOP + escalate. Leave the PR open with the posted BLOCK review; do **not** merge. The slice is fundamentally wrong for now.

### 3. Implement (code PR)

Spawn `kmp-forge:kmp-loop-implementer` with the slug, goal, boundaries, `local-gate`, and any notes the spec gate raised. It creates `feat/<slug>`, applies `tasks.md`, mirrors CI locally until green, opens the code PR, and drives CI to green.

`RESULT: FAILED` → STOP + escalate. `RESULT: OK` → Phase 4 with its `PR:`.

### 4. Code review gate

Runs only once CI is green — the two merge conditions are **CI green AND this review PASS**.

1. Spawn **both reviewers in a single message** so they run concurrently:
   - `kmp-forge:kmp-loop-code-reviewer` — correctness bugs; runs `/code-review high --comment`, which posts each finding as an inline PR comment. Returns a blocking/non-blocking classification.
   - `kmp-forge:kmp-reviewer` — locked-stack convention violations.
2. Merge their findings. **Blocking** = any correctness bug, any locked-stack violation that changes behavior or architecture, any missing test for new behavior, any committed secret, any breach of a locked invariant declared in the project's CLAUDE.md. Non-blocking = style and nits.
3. **Post a summary review to the PR:**
   ```bash
   gh pr review <pr> --comment --body "<body>"
   ```
   `<body>` begins `### 🤖 Claude Code review — cycle <n>/2 — <PASS: no blocking findings | CHANGES: <k> blocking>`, then the `kmp-reviewer` findings (bulleted, `file:line`), the count of inline findings posted, and a one-line verdict.
4. **Blocking findings** → spawn `kmp-forge:kmp-loop-fixer` with `target: code`, `branch: feat/<slug>`, the PR number, the cycle, `local-gate`, and the blocking findings verbatim. On its `RESULT: OK`, re-review from step 1 and post a fresh cycle-*n* summary. Two non-PASS verdicts, then STOP + escalate. If the fixer returns a non-empty `UNADDRESSED:` list → STOP + escalate.
5. **PASS** → `gh pr merge <pr> --squash --delete-branch`; `git switch main && git pull --ff-only`.

### 5. Bookkeeping & report

1. The just-implemented change stays active in `openspec/changes/<slug>/`; the **next** iteration's Phase 1 archives it. Do not archive it now.
2. Tick this slice in the backlog: `- [ ]` → `- [x]` with a short ` — PR #<n>, merged` note. Carry any deferred finding into the next slice's `carried-over:` line. Commit directly to `main` as `docs(backlog): mark <slug> done` and push. (Doc-only; no PR needed.)
3. Print the increment report:
   ```
   ✅ INCREMENT COMPLETE — <slug>
   ✓ Docs PR #<n>: merged (spec gate: <verdict>, <n> cycles)
   ✓ Code PR #<n>: merged (code gate: <verdict>, <n> cycles)
   ✓ Backlog: ticked, <k> items remaining

   Next: <the next queue item's slug, or "queue empty — handoff printed above">
   ```
4. If more unchecked items remain **and** the kill-switch file is absent → tell `/loop` to continue. Otherwise stop.

## The merge guard

`.claude/hooks/merge-guard.sh` runs as a `PreToolUse` hook on every `Bash` call — yours and every subagent's. When the command is a `gh pr merge`, it independently re-checks that the PR's checks all concluded successfully and that the newest `### 🤖 …` review on it reads `PASS`.

Its mode lives in `.claude/hooks/merge-guard.mode`:
- `log` — observes and records to `.claude/hooks/merge-guard.log`; never blocks. Trust-ramp default.
- `enforce-ci` — denies any merge whose CI is not green; does not evaluate gate reviews (for supervised use outside the loop).
- `enforce` — denies any merge failing either precondition, and fails closed if it cannot read GitHub. **Run the loop in this mode once the log agrees with it.**
- `off` — disabled.

The guard is a backstop, not a substitute. It cannot tell a good proposal from a bad one; it only makes "never force-merge" true by construction rather than by your adherence. Never work around it — a denied merge means a precondition is genuinely unmet. If you believe it denied wrongly, STOP + escalate and say so.

## Escalation format

```
⛔ ESCALATION — <slug> @ <phase>
What failed: <precise cause — quote the worker's FAILURE: line>
Tried: <fix attempts, N/2 cycles>
Repo state: <branch, PR #, merged? y/n>
Decision needed: <the specific human judgment required>
```

## Notes

- This command assumes `/kmp-forge-add-autoloop` has been run: OpenSpec initialized (`/opsx:*` commands present), backlog + AUTOLOOP.md seeded, merge guard installed. If any of that is missing, stop and point the user at `/kmp-forge-add-autoloop`.
- Launch: `/loop /kmp-forge-next-increment`. One invocation = one increment; `/loop` provides the repetition.
- Steering: edit the backlog (the loop always takes the topmost unchecked item next iteration); `touch openspec/STOP` for an emergency stop.
