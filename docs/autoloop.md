# Autonomous build loop

Opt-in machinery that builds a kmp-forge project increment-by-increment with no handholding: each iteration pops a backlog slice, proposes it as an OpenSpec change (docs PR), gates the spec, implements it (code PR), gates the code, and auto-merges — or stops and escalates. Battle-tested on a real project before being promoted into the plugin.

## The three tiers

| Tier | What | Needs |
|---|---|---|
| CI recipe | `driving-ci-green` skill — watch checks, read failures, mirror the gate locally, without flooding context | nothing; active in every kmp-forge project |
| Spec gate | `kmp-spec-critic` agent — adversarial PASS/REVISE/BLOCK review of an OpenSpec proposal before it becomes code | OpenSpec (`openspec init --tools claude`) |
| Full loop | `/kmp-forge-next-increment` + worker agents + merge guard + backlog | `/kmp-forge-add-autoloop` |

The first two are useful entirely without the loop: the skill in any supervised session, the spec critic whenever OpenSpec is in play ("review my change proposal before I implement it").

## Launch

```
/loop /kmp-forge-next-increment
```

One `/kmp-forge-next-increment` invocation = one full increment. `/loop` (self-paced) re-fires it after each increment. Stops on: empty queue, `openspec/STOP`, or escalation. Per-project configuration (local gate command, backlog path, queue-empty handoff) lives in `openspec/AUTOLOOP.md`'s `## Loop configuration` section, which the orchestrator reads at Phase 0.

## Why every phase runs in a subagent

`/loop` re-fires the orchestrator in the **same conversation**, so context accumulates across increments. Implementing Kotlin, running gradle, reading CI logs, and reviewing a full diff would fill the window within two or three increments — and then auto-compaction would summarize the loop's own merge rules. A loop that auto-merges to `main` must never be running on a *paraphrase* of "never force-merge".

So the orchestrator is a thin state machine: it reads the backlog, decides, posts verdicts, and merges. Everything expensive happens in a worker whose context dies when its phase ends:

| Phase | Worker | What stays inside it |
|---|---|---|
| Propose | `kmp-loop-proposer` | proposal drafting, `openspec validate`, CI logs |
| Spec gate | `kmp-spec-critic` | the whole proposal |
| Implement | `kmp-loop-implementer` | all code, every gradle run, CI logs |
| Code gate | `kmp-loop-code-reviewer` + `kmp-reviewer` | the full diff |
| Fix | `kmp-loop-fixer` | edit/build/fix churn |

The orchestrator keeps only each worker's structured result block — a few hundred tokens per phase, roughly 3–5k per increment.

This also makes the loop **crash-resumable**: no phase state is held in the conversation. The orchestrator re-derives where it is from `openspec list`, `gh pr list`, and the 🤖 verdict reviews already posted to the PR. Interrupt it anywhere and re-launch; it picks up at the right phase.

## The two gates

| Gate | Who | Checks |
|---|---|---|
| Spec (docs PR) | `kmp-spec-critic` | scope vs backlog, layer placement per [architecture.md](architecture.md), locked project invariants (project CLAUDE.md), dependency safety, `openspec validate`, task executability |
| Code (code PR) | `kmp-loop-code-reviewer` (correctness, via `/code-review high --comment`) + `kmp-reviewer` (locked-stack conventions) | blocking = correctness bugs, locked-invariant violations, missing tests, layer violations, secrets |

Both gates **post their verdict to the PR** (`### 🤖 … — cycle n/2 — VERDICT`) — the audit trail, the resume mechanism, and what the merge guard checks. The loop runs as the user's own GitHub account and GitHub blocks self-*approval*, so verdicts post as Comment-style reviews; the merge decision is the orchestrator's, gated on "no blocking findings".

A merge to `main` happens **only** when CI is green **and** the posted verdict is PASS. Otherwise the loop auto-fixes (≤2 tries) or stops and escalates — it never force-merges.

## Fix cycles

A **fix cycle** is a gate verdict of `REVISE`/`CHANGES` that gets handed to `kmp-loop-fixer`. A trailing `PASS` that confirms the fixes is not a cycle. So a legal PR carries at most two non-PASS 🤖 reviews, optionally followed by a PASS. Cycle count is recovered on resume by counting the non-PASS 🤖 reviews on the PR.

## The merge guard

Merging to `main` is the loop's one irreversible act, so "never force-merge" is also **code**: `.claude/hooks/merge-guard.sh` (installed by `/kmp-forge-add-autoloop`, source in `overlay/autoloop/`) runs as a `PreToolUse` hook on every Bash call — the orchestrator's and every subagent's. On a `gh pr merge` it independently re-checks GitHub: (1) every check concluded successfully, (2) the newest `### 🤖` gate review reads PASS. It fails closed when it cannot reach GitHub and is not fooled by whitespace or by the PR number's position.

Mode lives in `.claude/hooks/merge-guard.mode`, re-read on every invocation:

| Mode | Behavior |
|---|---|
| `log` | Observe only; record a verdict line to `merge-guard.log` evaluating both preconditions. **Install default.** |
| `enforce-ci` | Deny any merge whose CI is not green. Gate reviews not evaluated — the guard as a general "Claude never merges a red PR" rule, usable without the loop. |
| `enforce` | Deny any merge failing either precondition. Fails closed. **The loop's target mode.** |
| `off` | Disabled. |

**Trust ramp:** it installs in `log` so it cannot block a real merge before you have seen it agree with the loop. After an increment or two, `cut -f2,5,6 .claude/hooks/merge-guard.log` — every merge the loop performed should show `ALLOW`. Then `echo enforce > .claude/hooks/merge-guard.mode`. From then on the rule is enforced by the harness rather than trusted to the model — immune to compaction, to a confused subagent, and to future edits of the command body.

## Steering

- **Reorder / edit / insert work:** edit `openspec/backlog.md`; the loop takes the topmost unchecked item next iteration.
- **Emergency stop:** `touch openspec/STOP`; delete to resume.
- **Hard stop now:** interrupt `/loop` (Esc) or tell it to stop.

## When it escalates

The loop prints a `⛔ ESCALATION` block (what failed, what was tried, repo state, the one decision needed) and stops when: CI is still red after 2 fix cycles; a gate returns BLOCK, or REVISE/CHANGES twice unresolved; a worker returns `RESULT: FAILED`; the next slice has an unmet `needs-human:` precondition (credentials, a URL — checked *before* proposing, never stubbed past); the merge guard denies a merge the loop believed was ready; or git state is dirty/conflicted.

## Backlog format

`openspec/backlog.md` is the work queue and stop condition. Items:

```markdown
- [ ] slug: `add-settings-store`
  goal: <what the slice must achieve — detailed enough to propose without questions>
  boundaries: <binding exclusions — layers not to touch, decisions not to make>
  needs-human: <optional precondition verified BEFORE starting (credentials, a URL)>
  carried-over: <optional deferred findings from earlier slices>
```

The loop pops the first `- [ ]`, and ticks it `- [x] — PR #n, merged` when done. When the queue empties it prints the configured **queue-empty handoff** (from `openspec/AUTOLOOP.md`) and stops — it never invents new work.

## Installing

`/kmp-forge-add-autoloop` — checks preconditions (git, `gh` auth, CI workflow, `jq`, `openspec`), runs `openspec init --tools claude` if needed, seeds `openspec/AUTOLOOP.md` + `openspec/backlog.md`, installs the merge guard + `.claude/settings.json` wiring, and appends the CLAUDE.md section. The agents and the orchestrator command ship with the plugin — nothing per-project to copy, and plugin updates reach every project.

## Coexistence with supervised work

Installing the loop installs OpenSpec project-wide, and **OpenSpec takes priority once present**: supervised sessions route behavior changes through the same workflow the loop uses — `/opsx:propose` → (optionally `kmp-spec-critic`) → `/opsx:apply` — rather than editing behavior directly. `openspec/specs/**` is the record `kmp-spec-critic` judges dependency-safety against; a supervised edit that changes spec-covered behavior without a spec delta silently invalidates that record, and future loop proposals get judged against stale specs.

Direct edits remain right for: docs, formatting and build chores, and refactors with no spec-visible behavior change. If you must hot-fix spec-covered behavior directly, follow up with a spec delta so the record catches up.

## Limitations

- **The gates + CI are the only barrier** between a proposal and `main` — by design, and reversible via `git revert` of any squashed PR commit. Watch the first 1–2 increments live before leaving it unattended.
- **UI/UX slices should not auto-merge**: CI can't verify look and feel, and review agents can't judge UX unattended. Keep the loop on logic/state/data slices; gate UI slices for human review (open the PR, stop).
- **Branch protection:** "require approvals" blocks the loop (GitHub forbids self-approval; gates post comment-reviews). Supported: no protection + guard in `enforce`, or required status checks with zero required approvals.
- `/loop` and `/code-review` are Claude Code features the loop depends on; `kmp-loop-code-reviewer` falls back to reviewing the diff itself if `/code-review` is unavailable.
- The `### 🤖` review marker is a contract shared by the orchestrator (posts it) and the merge guard (greps it) — a third-party review containing `🤖` on the same PR could confuse the newest-review check.
