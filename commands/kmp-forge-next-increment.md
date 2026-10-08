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

- **Kill switch:** the file named by `kill-switch:` in the loop configuration (default `openspec/STOP`). Check it at the start of Phase 0 **and before every phase transition and every merge**. If it exists, finish nothing further — leave PRs open, print `LOOP HALTED (kill switch <path> present)`, and tell `/loop` to stop.
- **Merging is yours alone.** No subagent may run `gh pr merge` or push to `main`; the `merge-guard` PreToolUse hook denies both for subagent callers in `enforce` mode (see *The merge guard* below). A merge requires **CI green AND your posted gate verdict on the PR's current head reads PASS**. Never force-merge, never `--admin`.
- **Post the gate verdict to the PR before you merge it.** It is the audit trail, it is how a resumed iteration recovers the round, and it is what the merge guard checks.
- **Gate rounds.** Each gate run on a PR is a *round*, posted as `### 🤖 <gate> — round <r>/3 — <VERDICT>`. A non-PASS verdict in round 1 or 2 hands the findings to the fixer (a *fix cycle*) and is followed by another round. **A non-PASS verdict in round 3 — i.e. after two fix cycles — is STOP + escalate.** So a legal PR carries at most two non-PASS 🤖 reviews before its PASS.
- **One slice per iteration.** Do not batch backlog items.
- **Non-interactive only.** Never take a path that would prompt a human. If you are about to ask a question, STOP + escalate instead.
- Commit bodies end with `Co-Authored-By: Claude <noreply@anthropic.com>`; PR bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

When you "STOP + escalate": leave the repo in a safe state (no half-merged branch, nothing discarded), print the `⛔ ESCALATION` block, and tell `/loop` to stop.

## Your subagents

| Phase | `subagent_type` | Returns |
|---|---|---|
| 1 · Propose | `kmp-forge:kmp-loop-proposer` | `RESULT / PR / CI / CYCLES` |
| 2 · Spec gate | `kmp-forge:kmp-spec-critic` | `VERDICT: PASS \| REVISE \| BLOCK` + findings |
| 3 · Implement | `kmp-forge:kmp-loop-implementer` | `RESULT / PR / CI / FILES` |
| 4 · Code gate | `kmp-forge:kmp-loop-code-reviewer` **and** `kmp-forge:kmp-reviewer` | `VERDICT: PASS \| CHANGES \| ERROR` + findings |
| 2b / 4b · Fix | `kmp-forge:kmp-loop-fixer` | `RESULT / CI / APPLIED / UNADDRESSED` |

Pass each worker the `slug`, plus `goal` and `boundaries` verbatim from the backlog, plus `claude_plugin_root` = `${CLAUDE_PLUGIN_ROOT}`; pass `local-gate` (from the loop configuration) to the implementer and the fixer; pass `pr`, `branch`, and `round` to the gates and the fixer. If a worker returns `RESULT: FAILED`, its `FAILURE:` line is your escalation cause — do not retry it blind.

## Flow

### 0. Precheck and resume

1. **Read the loop configuration** from `openspec/AUTOLOOP.md`'s `## Loop configuration` section: `local-gate`, `spec-workflow`, `backlog`, `kill-switch`, and the `### Queue-empty handoff` block. Missing file or missing keys → fail-safe defaults: backlog `openspec/backlog.md`, kill-switch `openspec/STOP`, local-gate `./gradlew spotlessApply detekt build -x test jvmTest koverVerify`, handoff = "extend the backlog or stop".
2. If the kill-switch file exists → kill-switch halt.
3. **Working tree.** `git fetch origin --prune`, then `git status --porcelain`:
   - **Clean** → continue.
   - **Only steering files are dirty** — the backlog, `openspec/AUTOLOOP.md`, `.claude/hooks/merge-guard.mode` (the runbook tells the human to edit these while the loop runs) → commit them to `main`, not into a PR branch:
     ```bash
     git stash push -- <the dirty steering files>       # only if you are not on main
     git switch main && git pull --ff-only
     git stash pop                                      # only if you stashed; conflict → STOP + escalate
     git add -- <the dirty steering files>
     git commit -m "chore(autoloop): commit steering edits"
     git push origin main
     ```
     (A bookkeeping-only push from the main conversation — the merge guard allows it.)
   - **Anything else is dirty** → STOP + escalate. Never stash-and-forget, reset, or commit work you did not make.
4. `git switch main && git pull --ff-only`. Read the backlog. Take the **first `- [ ]` item** in the Queue. Parse `slug`, `goal`, `boundaries`, and any `needs-human:` line.
   - A `needs-human:` line naming an unprovisioned prerequisite (credentials, a URL) is a **precondition, not a task**. Check it before doing anything. If unmet → STOP + escalate immediately, before Phase 1.
   - **If no unchecked item remains → the queue is COMPLETE.** Archive any still-active change and land it:
     ```bash
     openspec archive <slug> --yes
     git add -- openspec && git commit -m "docs(openspec): archive <slug>" && git push origin main
     ```
     Print a `🏁 QUEUE EMPTY` block containing the configured **Queue-empty handoff** verbatim, then tell `/loop` to stop and wait for the human. Do not invent new backlog items.
5. **Derive the phase to resume at — never guess from memory.** A prior iteration may have been interrupted, compacted, or crashed between any two steps. The repo, GitHub, and OpenSpec are the only sources of truth. Query by **head branch and every state** (a plain `--search "<slug>"` misses branch names, and `--state open` misses a PR merged just before a crash):
   ```bash
   gh pr list --head "spec/<slug>" --state all --json number,state --limit 5
   gh pr list --head "feat/<slug>" --state all --json number,state --limit 5
   openspec list --json
   ```
   If a head has several PRs, the OPEN one wins, then the most recent MERGED one.

   | docs PR (`spec/<slug>`) | code PR (`feat/<slug>`) | Resume at |
   |---|---|---|
   | none, and no `openspec/changes/<slug>/` on `main` | none | **Phase 1** (fresh start — the proposer reuses an existing `spec/<slug>` branch) |
   | OPEN | none | **Phase 2** — first `git switch spec/<slug> && git pull --ff-only`: the critic reads the proposal from the working tree |
   | MERGED — or none, with `openspec/changes/<slug>/` on `main` | none | **Phase 3** |
   | MERGED | OPEN | **Phase 4** — first `git switch feat/<slug> && git pull --ff-only` |
   | MERGED | MERGED | **Phase 5** (tick the backlog) |
   | CLOSED without merge (either) | — | STOP + escalate — a human closed it; do not reopen or re-propose |

6. **Recover the gate round** for an open PR from the 🤖 reviews *your* account posted (`ME=$(gh api user --jq .login)`):
   ```bash
   gh pr view <pr> --json headRefOid,reviews | jq -r --arg me "$ME" '
     .headRefOid as $head
     | [.reviews[]? | select(.author.login == $me and ((.body // "") | startswith("### 🤖 ")))]
     | sort_by(.submittedAt) | .[]
     | ((.body | split("\n")[0] | split(" — ") | last | split(":")[0] | split(" ")[0])
        + "\t" + (if .commit.oid == $head then "head" else "old" end))'
   ```
   One line per posted round, oldest first: `<VERDICT>\t<head|old>`. With *n* lines and the last one as the standing verdict:
   - no lines → run the gate, round 1;
   - `PASS head` → the gate already passed on this exact commit — go straight to the merge step (CI must still be green);
   - `PASS old` → commits landed after the PASS → re-run the gate, round *n*+1;
   - non-PASS `head` → its fix was never pushed → if *n* ≥ 3, STOP + escalate; else spawn the fixer for those findings (cycle *n*), then re-gate as round *n*+1;
   - non-PASS `old` → the fix was pushed but never re-reviewed → if *n* ≥ 3, STOP + escalate; else re-run the gate, round *n*+1.

### 1. Propose (docs PR)

Spawn `kmp-forge:kmp-loop-proposer` with the slug, goal, and boundaries. If a prior change is still active in `openspec/changes/` with all tasks done, pass it as `prev-slug` so this PR both archives-prev and proposes-next.

`RESULT: FAILED` → STOP + escalate with its `FAILURE:` line. `RESULT: OK` → Phase 2 with its `PR:`. The proposer leaves the working tree on `spec/<slug>`; confirm with `git branch --show-current` before Phase 2.

### 2. Spec review gate

1. Check the kill switch. Confirm the working tree is on `spec/<slug>` at the PR head (`git pull --ff-only`).
2. Spawn `kmp-forge:kmp-spec-critic` with the slug, `round`, goal, and boundaries. It returns `VERDICT: PASS | REVISE | BLOCK` plus findings.
3. **Post the verdict to the docs PR:**
   ```bash
   gh pr review <pr> --comment --body "<body>"
   ```
   `<body>` begins `### 🤖 spec-critic — round <r>/3 — <VERDICT>`, then the BLOCKING / IMPROVEMENTS findings and the RATIONALE. (Comment-event review — GitHub blocks self-approval; your decision below is the real gate.)
4. **PASS** → check the kill switch → `gh pr merge <pr> --squash --delete-branch`, then `git switch main && git pull --ff-only`. Go to Phase 3.
5. **REVISE** → round 3 → STOP + escalate. Otherwise spawn `kmp-forge:kmp-loop-fixer` with `target: spec`, `branch: spec/<slug>`, the PR number, the cycle (= this round), and the findings verbatim. On its `RESULT: OK` (pushed, CI green), `git pull --ff-only`, re-spawn the spec critic, and post round *r*+1.
6. **BLOCK** → STOP + escalate. Leave the PR open with the posted BLOCK review; do **not** merge. The slice is fundamentally wrong for now.

### 3. Implement (code PR)

Check the kill switch. From a freshly-pulled `main`, spawn `kmp-forge:kmp-loop-implementer` with the slug, goal, boundaries, `local-gate`, and any notes the spec gate raised. It creates (or reuses) `feat/<slug>`, applies `tasks.md`, mirrors CI locally until green, opens the code PR, and drives CI to green.

`RESULT: FAILED` → STOP + escalate. `RESULT: OK` → Phase 4 with its `PR:`.

### 4. Code review gate

Runs only once CI is green — the two merge conditions are **CI green AND this review PASS on the current head**.

1. Check the kill switch. Make sure the working tree is on `feat/<slug>` at the PR head and `origin/main` is fresh: `git switch feat/<slug> && git pull --ff-only && git fetch origin main`.
2. Spawn **both reviewers in a single message** so they run concurrently, giving each the PR number, the branch, the round, and the exact diff range `origin/main...origin/feat/<slug>`:
   - `kmp-forge:kmp-loop-code-reviewer` — correctness bugs; runs `/code-review high --comment <pr>` (the PR number is mandatory — without a target `/code-review` reviews the empty local diff), which posts each finding as an inline PR comment. Returns `VERDICT: PASS | CHANGES | ERROR`.
   - `kmp-forge:kmp-reviewer` — locked-stack convention violations. Prompt it with: "Review exactly `git diff origin/main...origin/feat/<slug>` (PR #<pr>) for locked-stack violations; if that diff is empty or cannot be produced, say so instead of reporting no findings."
3. **Fail closed.** If the code reviewer returns `ERROR`, or `kmp-reviewer` reports it could not obtain the diff → STOP + escalate. An empty or unverifiable diff is never a PASS.
4. Merge their findings. **Blocking** = any correctness bug, any locked-stack violation that changes behavior or architecture, any missing test for new behavior, any committed secret, any breach of a locked invariant declared in the project's CLAUDE.md. Non-blocking = style and nits.
5. **Post a summary review to the PR:**
   ```bash
   gh pr review <pr> --comment --body "<body>"
   ```
   `<body>` begins `### 🤖 Claude Code review — round <r>/3 — <PASS: no blocking findings | CHANGES: <k> blocking>`, then the `kmp-reviewer` findings (bulleted, `file:line`), the count of inline findings posted, and a one-line verdict.
6. **Blocking findings** → round 3 → STOP + escalate. Otherwise spawn `kmp-forge:kmp-loop-fixer` with `target: code`, `branch: feat/<slug>`, the PR number, the cycle (= this round), `local-gate`, and the blocking findings verbatim. A non-empty `UNADDRESSED:` list → STOP + escalate. On its `RESULT: OK`, re-review from step 1 and post round *r*+1.
7. **PASS** → check the kill switch → `gh pr merge <pr> --squash --delete-branch`; `git switch main && git pull --ff-only`.

### 5. Bookkeeping & report

1. The just-implemented change stays active in `openspec/changes/<slug>/`; the **next** iteration's Phase 1 archives it. Do not archive it now.
2. Tick this slice in the backlog: `- [ ]` → `- [x]` with a short ` — PR #<n>, merged` note. Carry any deferred finding into the next slice's `carried-over:` line. Commit directly to `main` as `docs(backlog): mark <slug> done` and `git push origin main`. (Bookkeeping-only — the merge guard allows a push to `main` from you when every changed file is under `openspec/`, the backlog, or the guard mode file.)
3. Print the increment report:
   ```
   ✅ INCREMENT COMPLETE — <slug>
   ✓ Docs PR #<n>: merged (spec gate: <verdict>, <r> rounds)
   ✓ Code PR #<n>: merged (code gate: <verdict>, <r> rounds)
   ✓ Backlog: ticked, <k> items remaining

   Next: <the next queue item's slug, or "queue empty — handoff printed above">
   ```
4. If more unchecked items remain **and** the kill-switch file is absent → tell `/loop` to continue. Otherwise stop.

## The merge guard

`.claude/hooks/merge-guard.sh` runs as a `PreToolUse` hook on every `Bash`, `Write`/`Edit` and `mcp__*` call — yours and every subagent's. Independently of you, it:

- re-checks every merge — `gh pr merge` in any form, `gh api` merge endpoints, MCP merge tools — for: all checks on the head commit green, and the newest `### 🤖` review **posted by your GitHub account** reading `PASS` **on the PR's current head commit**;
- denies merges and pushes to `main` from subagents, `--admin`, force-pushes/deletes of `main`, API ref writes, and any push to `main` from you that touches more than loop bookkeeping;
- denies subagents writing the guard, its mode file, or `.claude/settings*.json`;
- fails closed (in the enforce modes) when it cannot reach GitHub or hits an internal error.

Its mode lives in `.claude/hooks/merge-guard.mode`:
- `log` — observes and records to `.claude/hooks/merge-guard.log`; never blocks. Trust-ramp default.
- `enforce-ci` — denies merges whose CI is not green, `--admin`, force-pushes/deletes of `main`, API ref writes, subagent tampering; does not evaluate gate reviews, callers, or push contents (for supervised use outside the loop).
- `enforce` — everything above. **Run the loop in this mode once the log agrees with it.**
- `off` — disabled.

The guard is a backstop, not a substitute. It cannot tell a good proposal from a bad one; it only makes "never force-merge" true by construction rather than by your adherence. Never work around it — a denied merge means a precondition is genuinely unmet. If you believe it denied wrongly, STOP + escalate and say so.

## Escalation format

```
⛔ ESCALATION — <slug> @ <phase>
What failed: <precise cause — quote the worker's FAILURE: line>
Tried: <fix attempts — rounds r/3>
Repo state: <branch, PR #, merged? y/n>
Decision needed: <the specific human judgment required>
```

## Notes

- This command assumes `/kmp-forge-add-autoloop` has been run: OpenSpec initialized (`/opsx:*` commands present), backlog + AUTOLOOP.md seeded, merge guard installed. If any of that is missing, stop and point the user at `/kmp-forge-add-autoloop`.
- Launch: `/loop /kmp-forge-next-increment`. One invocation = one increment; `/loop` provides the repetition.
- Steering: edit the backlog at any time (the loop takes the topmost unchecked item next iteration and commits your uncommitted edits at its next Phase 0); create the configured kill-switch file (`kill-switch:` in `openspec/AUTOLOOP.md`, default `openspec/STOP` — gitignored) for an emergency stop, delete it to resume.
