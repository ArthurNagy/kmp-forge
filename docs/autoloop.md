# Autonomous build loop

Opt-in machinery that builds a kmp-forge project increment-by-increment with no handholding: each iteration takes the next `ready` GitHub issue, proposes it as an OpenSpec change (docs PR), gates the spec, implements it (code PR), gates the code, and auto-merges — or stops and escalates. Battle-tested on a real project before being promoted into the plugin.

## The three tiers

| Tier | What | Needs |
|---|---|---|
| CI recipe | `driving-ci-green` skill — watch checks, read failures, mirror the gate locally, without flooding context | nothing; active in every kmp-forge project |
| Spec gate | `kmp-spec-critic` agent — adversarial PASS/REVISE/BLOCK review of an OpenSpec proposal before it becomes code | OpenSpec (`openspec init --tools claude`) |
| Full loop | `/kmp-forge-next-increment` + worker agents + merge guard + the GitHub-issue queue | `/kmp-forge-add-autoloop` |

The first two are useful entirely without the loop: the skill in any supervised session, the spec critic whenever OpenSpec is in play ("review my change proposal before I implement it").

## Launch

```
/loop /kmp-forge-next-increment
```

One `/kmp-forge-next-increment` invocation = one full increment. `/loop` (self-paced) re-fires it after each increment. Stops on: empty queue, the kill-switch file (default `openspec/STOP`), or escalation. Per-project configuration (local gate command, backlog path, queue-empty handoff) lives in `openspec/AUTOLOOP.md`'s `## Loop configuration` section, which the orchestrator reads at Phase 0.

## Why every phase runs in a subagent

`/loop` re-fires the orchestrator in the **same conversation**, so context accumulates across increments. Implementing Kotlin, running gradle, reading CI logs, and reviewing a full diff would fill the window within two or three increments — and then auto-compaction would summarize the loop's own merge rules. A loop that auto-merges to `main` must never be running on a *paraphrase* of "never force-merge".

So the orchestrator is a thin state machine: it asks the queue for the next issue, decides, posts verdicts, and merges. Everything expensive happens in a worker whose context dies when its phase ends:

| Phase | Worker | What stays inside it |
|---|---|---|
| Propose | `kmp-loop-proposer` | proposal drafting, `openspec validate`, CI logs |
| Spec gate | `kmp-spec-critic` | the whole proposal |
| Implement | `kmp-loop-implementer` | all code, every gradle run, CI logs |
| Code gate | `kmp-loop-code-reviewer` + `kmp-reviewer` | the full diff |
| Fix | `kmp-loop-fixer` | edit/build/fix churn |

The orchestrator keeps only each worker's structured result block — a few hundred tokens per phase, roughly 3–5k per increment.

This also makes the loop **crash-resumable**: no phase state is held in the conversation. The orchestrator re-derives where it is from `openspec list`, the docs and code PRs found **by head branch in every state** (`gh pr list --head spec/<slug> --state all` — so a PR merged just before a crash is seen as merged, not re-run), and the 🤖 verdict reviews already posted to the open PR, including which commit each was posted on. It checks out the open PR's branch before re-running a gate (the spec gate reads the proposal from the working tree). Interrupt it anywhere and re-launch; it picks up at the right phase.

## The two gates

| Gate | Who | Checks |
|---|---|---|
| Spec (docs PR) | `kmp-spec-critic` | scope vs the issue (every acceptance criterion → a scenario, Out of scope respected), layer placement per [architecture.md](architecture.md), locked project invariants (project CLAUDE.md), dependency safety, `openspec validate`, task executability |
| Code (code PR) | `kmp-loop-code-reviewer` (correctness, via `/code-review high --comment <pr>`) + `kmp-reviewer` (locked-stack conventions, on `origin/main...origin/feat/<slug>`) | blocking = correctness bugs, locked-invariant violations, missing tests, layer violations, secrets |

Both gates **post their verdict to the PR** (`### 🤖 <gate> — round r/3 — VERDICT`) — the audit trail, the resume mechanism, and what the merge guard checks.

The code gate **fails closed**: it is always given the PR number and the exact diff range (without a target, `/code-review` reviews the empty local diff of a pushed branch — which would read as "no findings"). If the reviewer cannot establish a non-empty diff matching the PR head, it returns `ERROR`, and the loop escalates rather than passing. The loop runs as the user's own GitHub account and GitHub blocks self-*approval*, so verdicts post as Comment-style reviews; the merge decision is the orchestrator's, gated on "no blocking findings".

A merge to `main` happens **only** when CI is green **and** the posted verdict is PASS. Otherwise the loop auto-fixes (≤2 tries) or stops and escalates — it never force-merges.

## Fix cycles

Each gate run on a PR is a **round** (at most 3). A non-PASS verdict (`REVISE`/`CHANGES`) in round 1 or 2 is handed to `kmp-loop-fixer` — a **fix cycle** — and followed by another round; a non-PASS verdict in round 3 escalates. So a legal PR carries at most two non-PASS 🤖 reviews before its PASS. On resume the round is recovered from the 🤖 reviews the loop's account posted, and whether the newest one was posted on the current head tells the orchestrator if its fix was already pushed.

## The merge guard

Merging to `main` is the loop's one irreversible act, so "never force-merge" is also **code**: `.claude/hooks/merge-guard.sh` (installed by `/kmp-forge-add-autoloop`, source in `overlay/autoloop/`) runs as a `PreToolUse` hook on every Bash, Write/Edit and `mcp__*` call — the orchestrator's and every subagent's (a subagent's calls carry an `agent_id`). Independently of the model it:

- **re-checks every merge** — `gh pr merge` in any flag order or wrapper (`gh pr --repo o/r merge 7`, `bash -c '…'`, `$(…)`, `xargs`), `gh api` writes to `…/pulls/<n>/merge`, GraphQL merge mutations, MCP tools named `*merge*` — against GitHub: (1) every check on the head commit concluded successfully; (2) the newest review **posted by the loop's own GitHub account** whose body starts `### 🤖 ` has `PASS` as its verdict field, **and was posted on the PR's current head commit** (a PASS that predates later pushes is stale);
- **denies** merges by subagents, `--admin`, force-pushes or deletes of `main`, `gh api` / MCP writes that update `main` directly, and any push to `main` from the orchestrator that touches more than loop bookkeeping (`openspec/**`, the mode file — the queue-empty archive and the human's steering edits);
- **denies applying the `ready` label** — `gh issue create|edit --label/--add-label ready`, `gh api` writes to an issue's labels, GraphQL label mutations (they carry ids, not names), MCP issue/label tools — from the orchestrator and every subagent. `ready` is how a human approves work; the loop never approves its own;
- **denies subagents writing the guard itself** — the script, its mode file, `.claude/settings*.json`;
- **fails closed**: every GitHub call is time-boxed so the hook always finishes inside its `timeout` (Claude Code lets a tool call through when a hook times out or exits non-zero other than 2), and in the enforce modes an unreachable GitHub, an unresolvable PR, a missing `jq`, or an internal error denies the call.

Mode lives in `.claude/hooks/merge-guard.mode` (tracked — project policy), re-read on every invocation:

| Mode | Behavior |
|---|---|
| `log` | Observe only; record a verdict line to `merge-guard.log` that evaluates every precondition as `enforce` would. **Install default.** |
| `enforce-ci` | Deny any merge whose CI is not green, `--admin`, force-pushes/deletes of `main`, API ref writes, and subagent tampering. Gate reviews, callers and push contents are not evaluated — the guard as a general "Claude never merges a red PR" rule, usable without the loop. |
| `enforce` | Everything above. Fails closed. **The loop's target mode.** |
| `off` | Disabled. |

**Trust ramp:** it installs in `log` so it cannot block a real merge before you have seen it agree with the loop. After an increment or two, `cut -f2,5,6 .claude/hooks/merge-guard.log` — every merge the loop performed should show `ALLOW`. Then `echo enforce > .claude/hooks/merge-guard.mode` and commit it. From then on the rule is enforced by the harness rather than trusted to the model — immune to compaction, to a confused subagent, and to future edits of the command body.

**Wiring matters.** The hook command is `bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/merge-guard.sh"`, quoted: an unquoted path splits on spaces, the hook exits 127, and Claude Code treats that as a non-blocking error — the guard would silently never run. `/kmp-forge-add-autoloop`'s smoke check runs the guard through the exact wired command string to catch this. The script's `# version:` header is bumped on every change, so a re-run of the installer can tell a stale project copy.

## Steering

All work steering happens on GitHub, where you already triage:

- **Add work:** file an issue and label it `ready`. **Reorder:** `priority:high` / `priority:low` (then oldest first). **Pause one:** remove `ready` — an `in-progress` issue without it is skipped until relabeled. **Keep a big one out:** `epic` (split it into slice issues).
- **Runbook / guard mode:** edit `openspec/AUTOLOOP.md` or `.claude/hooks/merge-guard.mode` any time; the loop commits your uncommitted edits to `main` at its next Phase 0.
- **Emergency stop:** create the kill-switch file (`kill-switch:` in `openspec/AUTOLOOP.md`, default `touch openspec/STOP`, gitignored); the loop checks it before every phase and every merge. Delete it to resume.
- **Hard stop now:** interrupt `/loop` (Esc) or tell it to stop.

## When it escalates

The loop prints a `⛔ ESCALATION` block (what failed, what was tried, repo state, the one decision needed) and stops when: CI is still red after 2 fix cycles; a gate returns BLOCK, or is still not PASS in round 3; the code gate returns ERROR (no verifiable diff); a worker returns `RESULT: FAILED`; the next issue has an unmet **Needs a human first** precondition (credentials, a URL — checked *before* proposing, never stubbed past); the queue reports a conflict (two `in-progress` issues, or one issue with two change names in flight); the merge guard denies a merge the loop believed was ready; a human closed one of the slice's PRs; or the tree has uncommitted changes other than steering edits.

## Work queue: GitHub issues

The queue is the repo's open issues labeled **`ready`** — the same issues you triage by hand; there is no second backlog file. `scripts/issues.sh next` (in the plugin) picks the next one, so the rules are code, not model judgment:

1. An open `in-progress` issue (the loop's current slice) is resumed first. Two at once is a conflict → escalate.
2. Otherwise: `ready` issues that are not `epic`s, ordered `priority:high` → unlabeled → `priority:low`, then oldest issue number first.
3. **Trust.** An issue is worked only when its **author and whoever last applied `ready`** are the loop's own GitHub account or listed in `ready-approvers:` (`openspec/AUTOLOOP.md`). Anyone can open an issue on a public repo, and an issue form can auto-apply labels on its author's behalf — a label alone proves nothing. An outsider's issue is raw intake: re-file it as your own to queue it.
4. **Dependencies.** An issue waits while anything in its **Depends on** section — or GitHub's native "blocked by" relationship — is still open.
5. **Naming.** The change is `<issue>-<kebab>` (from the issue's **Change name**, else its title), reused from any earlier attempt — so a crashed increment resumes on the same `spec/` / `feat/` branches even if the title changed.

Issues follow the **Feature / backlog item** form (`.github/ISSUE_TEMPLATE/feature_request.yml`): **Problem** and **Acceptance criteria** (WHEN … THEN …, one per line) are the slice's goal; **Out of scope** is binding; **Depends on**, **Needs a human first** (preconditions checked before starting) and **Change name** are optional. Bug reports work too.

Per increment the loop adds `in-progress` when it starts, the docs PR says `Refs #<issue>`, the code PR `Fixes #<issue>` (merging closes the issue), and the loop then removes `in-progress`. Non-blocking findings worth keeping become one **follow-up issue** — filed without `ready`, so you decide. When no `ready` issue is left it prints the configured **queue-empty handoff** (from `openspec/AUTOLOOP.md`) with the issues it skipped and why, and stops. With `queue-empty-groom: on` (the install default) it first spawns the `kmp-product-owner` agent in gaps mode and files up to 3 drafted next slices from the MVP spec — without `ready`, so the next increment starts only when you approve one. It never labels anything `ready`.

## Installing

`/kmp-forge-add-autoloop` — checks preconditions (git, `gh` auth + a reachable GitHub `origin`, a PR CI workflow, `jq`, `python3`, `openspec` ≥ 1.14), runs `openspec init --tools claude` if needed (plus kmp-forge's `openspec/config.yaml` rules), seeds `openspec/AUTOLOOP.md`, creates the issue labels, files your first slices as issues (or migrates a legacy `openspec/backlog.md`), installs the merge guard + `.claude/settings.json` wiring (smoke-tested through the wired command), gitignores the audit log and the kill switch, and appends the CLAUDE.md section. The agents and the orchestrator command ship with the plugin — nothing per-project to copy, and plugin updates reach every project.

## Coexistence with supervised work

Projects scaffolded with OpenSpec (the `/kmp-forge-init` default) already work this way; installing the loop on a plain-docs project adds OpenSpec project-wide. Either way **OpenSpec takes priority once present**: supervised sessions route behavior changes through the same workflow the loop uses — `/opsx:propose` → (optionally `kmp-spec-critic`) → `/opsx:apply` — rather than editing behavior directly. `openspec/specs/**` is the record `kmp-spec-critic` judges dependency-safety against; a supervised edit that changes spec-covered behavior without a spec delta silently invalidates that record, and future loop proposals get judged against stale specs.

Direct edits remain right for: docs, formatting and build chores, and refactors with no spec-visible behavior change. If you must hot-fix spec-covered behavior directly, follow up with a spec delta so the record catches up.

## Limitations

- **The gates + CI are the only barrier** between a proposal and `main` — by design, and reversible via `git revert` of any squashed PR commit. Watch the first 1–2 increments live before leaving it unattended.
- **UI/UX slices should not auto-merge**: CI can't verify look and feel, and review agents can't judge UX unattended. Keep the loop on logic/state/data slices; gate UI slices for human review (open the PR, stop).
- **Branch protection:** "require approvals" blocks the loop (GitHub forbids self-approval; gates post comment-reviews). Supported: no protection + guard in `enforce`, or required status checks with zero required approvals.
- `/loop` and `/code-review` are Claude Code features the loop depends on; `kmp-loop-code-reviewer` falls back to reviewing the diff itself if `/code-review` is unavailable.
- The `### 🤖 <gate> — round r/3 — <VERDICT>` header is a contract shared by the orchestrator (posts it), its resume logic (parses it), and the merge guard (checks it) — change all three together. The guard only trusts reviews posted by the loop's own GitHub account, so another reviewer's `🤖` comment cannot pass (or block) a merge.
- **Least privilege.** The loop's worker agents declare explicit `tools:` (no MCP connectors; the code reviewer has no Write/Edit), because they read untrusted PR, CI and code text unattended. The guard blocks *subagents* from editing its files; the main conversation can still change its mode — that is the human's lever, and a downgrade shows up in `git diff` of the tracked mode file.
- The guard sees tool calls only. It cannot stop a human (or a CI workflow with write access) from merging, and it does not cover tools you add later under names it does not match.
