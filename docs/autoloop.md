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

One `/kmp-forge-next-increment` invocation = one full increment. `/loop` (self-paced) re-fires it after each increment. Stops on: empty queue, the kill-switch file (default `openspec/STOP`), or escalation. Per-project configuration (local gate command, ready approvers, QA, kill switch, queue-empty handoff) lives in `openspec/AUTOLOOP.md`'s `## Loop configuration` section, which the orchestrator reads at Phase 0.

## Why every phase runs in a subagent

`/loop` re-fires the orchestrator in the **same conversation**, so context accumulates across increments. Implementing Kotlin, running gradle, reading CI logs, and reviewing a full diff would fill the window within two or three increments — and then auto-compaction would summarize the loop's own merge rules. A loop that auto-merges to `main` must never be running on a *paraphrase* of "never force-merge".

So the orchestrator is a thin state machine: it asks the queue for the next issue, decides, posts verdicts, and merges. Everything expensive happens in a worker whose context dies when its phase ends:

| Phase | Worker | What stays inside it |
|---|---|---|
| Propose | `kmp-loop-proposer` | proposal drafting, `openspec validate`, CI logs |
| Spec gate | `kmp-spec-critic` | the whole proposal |
| Implement | `kmp-loop-implementer` | all code, every gradle run, CI logs |
| Code gate | `kmp-loop-code-reviewer` + `kmp-reviewer` + `kmp-qa` | the full diff; the app on a device — layout dumps, screenshots, logcat |
| Fix | `kmp-loop-fixer` | edit/build/fix churn |

The orchestrator keeps only each worker's structured result block — a few hundred tokens per phase, roughly 3–5k per increment.

This also makes the loop **crash-resumable**: no phase state is held in the conversation. The orchestrator re-derives where it is from `openspec list`, the docs and code PRs found **by head branch in every state** (`gh pr list --head spec/<slug> --state all` — so a PR merged just before a crash is seen as merged, not re-run), and the 🤖 verdict reviews already posted to the open PR, including which commit each was posted on. It checks out the open PR's branch before re-running a gate (the spec gate reads the proposal from the working tree). Interrupt it anywhere and re-launch; it picks up at the right phase.

## The two gates

| Gate | Who | Checks |
|---|---|---|
| Spec (docs PR) | `kmp-spec-critic` | scope vs the issue (every acceptance criterion → a scenario, Out of scope respected), layer placement per [architecture.md](architecture.md), locked project invariants (project CLAUDE.md), dependency safety, `openspec validate`, task executability |
| Code (code PR) | `kmp-loop-code-reviewer` (correctness, via `/code-review high --comment <pr>`) + `kmp-reviewer` (locked-stack conventions, on `origin/main...origin/feat/<slug>`) + `kmp-qa` (acceptance, per `qa:` in the runbook) | blocking = correctness bugs, locked-invariant violations, missing tests, layer violations, secrets, a scenario without a `// Scenario:`-tagged test, a scenario journey that fails on the device, a crash |

Both gates **post their verdict to the PR** (`### 🤖 <gate> — round r/3 — VERDICT`) — the audit trail, the resume mechanism, and what the merge guard checks.

The code gate **fails closed**: it is always given the PR number and the exact diff range (without a target, `/code-review` reviews the empty local diff of a pushed branch — which would read as "no findings"). If the reviewer cannot establish a non-empty diff matching the PR head, it returns `ERROR`, and the loop escalates rather than passing. The loop runs as the user's own GitHub account and GitHub blocks self-*approval*, so verdicts post as Comment-style reviews; the merge decision is the orchestrator's, gated on "no blocking findings".

A merge to `main` happens **only** when CI is green **and** the posted verdict is PASS. Otherwise the loop auto-fixes (≤2 tries) or stops and escalates — it never force-merges.

## Fix cycles

Each gate run on a PR is a **round** (at most 3). A non-PASS verdict (`REVISE`/`CHANGES`) in round 1 or 2 is handed to `kmp-loop-fixer` — a **fix cycle** — and followed by another round; a non-PASS verdict in round 3 escalates. So a legal PR carries at most two non-PASS 🤖 reviews before its PASS. On resume the round is recovered from the 🤖 reviews the loop's account posted, and whether the newest one was posted on the current head tells the orchestrator if its fix was already pushed.

## The merge guard

Merging to `main` is the loop's one irreversible act, so "never force-merge" is also **code**: `.claude/hooks/merge-guard.sh` (installed by `/kmp-forge-add-autoloop`, source in `overlay/autoloop/`) runs as a `PreToolUse` hook on every Bash, Write/Edit and `mcp__*` call — the orchestrator's and every subagent's (a subagent's calls carry an `agent_id`). Independently of the model it:

- **re-checks every merge** — `gh pr merge` in any flag order or wrapper (`gh pr --repo o/r merge 7`, `bash -c '…'`, `timeout 60 …`, `$'gh' …`, gh aliases), `gh api` writes to `…/pulls/<n>/merge` (query strings and trailing slashes included), GraphQL merge mutations, MCP tools named `*merge*` — against GitHub: (1) every check on the head commit concluded successfully; (2) the newest review **posted by the loop's own GitHub account** whose body starts `### 🤖 ` has `PASS` as its verdict field, **and was posted on the PR's current head commit** (a PASS that predates later pushes is stale). It checks the PR and repository the command will really merge — `--repo`, `GH_REPO`, a literal `cd` — and refuses a target it cannot pin down (`gh pr merge "$(…)"`, a variable, xargs/find input);
- **denies** merges by subagents, `--admin`, force-pushes or deletes of `main` however spelled (`-fu`, `--force-w`, `+refspec`, `--mirror`, `--prune`, or a bare `git push` that `push.default`, `remote.<r>.push` or a git alias aims at `main`), `gh api` / MCP / curl writes that update `main` directly, and any push to `main` from the orchestrator that changes more than `openspec/**` — the queue-empty archive and the human's runbook edits (a rename counts as a delete plus an add, so moving code under `openspec/` does not pass);
- **denies applying the `ready` label** — `gh issue create|edit --label/--add-label ready`, `gh label edit … --name ready`, `gh api` writes to an issue's labels, GraphQL label mutations (they carry ids, not names), MCP issue/label tools — from the orchestrator and every subagent. `ready` is how a human approves work; the loop never approves its own;
- **denies writing the guard itself or the runbook** — the script, its mode file, `.claude/settings*.json`, and `openspec/AUTOLOOP.md` (its `ready-approvers` decide whose issues the loop trusts, and the loop commits an uncommitted edit of it as the human's) — from **any** caller in the enforce modes, the main conversation included: through Write/Edit (paths normalised — `..`, `//`, symlinks, letter case) or Bash (redirects, `cp`/`mv`/`rm`/`chmod`/`sed -i`/…, git pathspecs such as `git restore .` or `git checkout <ref> -- openspec`, the paths of a patch `git apply`/`git am` would apply, interpreters), and a wholesale revert (`git stash`, `git reset --hard`, `git switch -f`) while the human's edit of one of them is uncommitted. Mode and runbook are policy: only the human changes them, outside Claude;
- **denies a subagent posting a gate verdict** — a review or comment whose body starts `### 🤖`, or a review whose body it cannot read — so only the orchestrator's verdicts exist;
- **denies what it cannot parse**: in the enforce modes a Bash command that mentions a merge, a push or ref, the GitHub API or token, a guard file or the `ready` label, but does not parse into a form the guard can check — a variable as the command (`G=gh; $G …`), code piped into a shell, inline interpreter code (`python3 -c`), an unknown wrapper around gh/git — is denied by default, as are a gh/git subcommand built at run time, `gh auth token` and `gh alias set`;
- **fails closed**: every GitHub call is time-boxed so the hook always finishes inside its `timeout` (Claude Code lets a tool call through when a hook times out or exits non-zero other than 2), and in the enforce modes an unreachable GitHub, an unresolvable PR, non-JSON hook input, a missing `python3`, or an internal error denies the call.

The guard is a bash launcher around a stdlib-only `python3` program (a shell lexer that understands quoting, `$(…)`, heredocs and the common wrappers); it needs `python3` ≥ 3.8 and `git`, and nothing else.

Mode lives in `.claude/hooks/merge-guard.mode` (tracked — project policy), re-read on every invocation:

| Mode | Behavior |
|---|---|
| `log` | Observe only; record a verdict line to `merge-guard.log` that evaluates every precondition as `enforce` would. **Install default.** |
| `enforce-ci` | Deny any merge whose CI is not green, `--admin`, force-pushes/deletes of `main`, API ref writes, token exposure, commands it cannot parse, and writes to the guard's files. Gate reviews, callers, push contents and `ready` labels are not evaluated — the guard as a general "Claude never merges a red PR" rule, usable without the loop. |
| `enforce` | Everything above. Fails closed. **The loop's target mode.** |
| `off` | Disabled. |
| *(missing, empty or unknown)* | `enforce-ci`, with a `WARN` line in the audit log — deleting or garbling the mode file never switches the guard off. |

**Trust ramp:** it installs in `log` so it cannot block a real merge before you have seen it agree with the loop. After an increment or two, `cut -f2,5,6 .claude/hooks/merge-guard.log` — every merge the loop performed should show `ALLOW`. Then switch it yourself, in a terminal (or with `!` in front of the command at the Claude Code prompt) — once it enforces, Claude can no longer write the mode file, and the loop never commits it:

```bash
echo enforce > .claude/hooks/merge-guard.mode
git commit -m "chore(autoloop): enforce merge guard" -- .claude/hooks/merge-guard.mode && git push
```

From then on the rule is enforced by the harness rather than trusted to the model — immune to compaction, to a confused subagent, and to future edits of the command body.

**Wiring matters.** The hook command is `bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/merge-guard.sh"`, quoted: an unquoted path splits on spaces, the hook exits 127, and Claude Code treats that as a non-blocking error — the guard would silently never run. `/kmp-forge-add-autoloop`'s smoke check runs the guard through the exact wired command string to catch this. The script's `# version:` header is bumped on every change, so a re-run of the installer can tell a stale project copy.

## Steering

All work steering happens on GitHub, where you already triage:

- **Add work:** file an issue and label it `ready`. **Reorder:** `priority:high` / `priority:low` (then oldest first). **Pause one:** remove `ready`. On the `in-progress` issue that pauses the whole loop (`⏸ LOOP PAUSED` — it never starts another slice meanwhile); relabel it to resume, or remove `in-progress` to drop it. **Keep a big one out:** split it into sub-issues — a parent issue is never worked, its sub-issues are.
- **Runbook:** edit `openspec/AUTOLOOP.md` any time, outside Claude. With the guard enforcing — Claude can't have written it — the loop commits your uncommitted edit to `main` at its next Phase 0; in `log` it can't tell your edit from a worker's, so it stops and asks you to commit it yourself.
- **Guard mode:** edit `.claude/hooks/merge-guard.mode` any time, outside Claude; it applies to the next tool call. Commit it yourself — the loop leaves it uncommitted and says so in its report.
- **Emergency stop:** create the kill-switch file (`kill-switch:` in `openspec/AUTOLOOP.md`, default `touch openspec/STOP`, gitignored); the loop checks it before every phase and every merge. Delete it to resume.
- **Hard stop now:** interrupt `/loop` (Esc) or tell it to stop.

## When it escalates

The loop prints a `⛔ ESCALATION` block (what failed, what was tried, repo state, the one decision needed) and stops when: CI is still red after 2 fix cycles; a gate returns BLOCK, or is still not PASS in round 3; the code gate returns ERROR (no verifiable diff); a worker returns `RESULT: FAILED`; the next issue has an unmet **Needs a human first** precondition (credentials, a URL — checked *before* proposing, never stubbed past); the queue reports a conflict (two `in-progress` issues, or one issue with two change names in flight); the merge guard denies a merge the loop believed was ready; a human closed one of the slice's PRs; or the tree has uncommitted changes other than steering edits.

## Work queue: GitHub issues

The queue is the repo's open issues labeled **`ready`** — the same issues you triage by hand; there is no second backlog file. `scripts/issues.sh next` (in the plugin) picks the next one, so the rules are code, not model judgment:

1. An open `in-progress` issue (the loop's current slice) is resumed first. Two at once is a conflict → escalate. One that can't be worked right now (`ready` removed, a dependency reopened) **pauses** the loop — it never starts another slice beside a half-done one.
2. Otherwise: `ready` issues that are not parent issues (an issue with sub-issues is skipped — its sub-issues are the work), ordered `priority:high` → unlabeled → `priority:low`, then oldest issue number first.
3. **Trust.** An issue is worked only when its **author and whoever last applied `ready`** are the loop's own GitHub account or listed in `ready-approvers:` (`openspec/AUTOLOOP.md`). Anyone can open an issue on a public repo, and an issue form can auto-apply labels on its author's behalf — a label alone proves nothing. An outsider's issue is raw intake: re-file it as your own to queue it.
4. **Dependencies.** An issue waits while anything in its **Depends on** section — or GitHub's native "blocked by" relationship — is still open.
5. **Naming.** The change is `<issue>-<kebab>` (from the issue's **Change name**, else its title), reused from any earlier attempt — an open change dir, a branch on `origin`, or a same-repo PR by an approver (fork PRs and outsiders' branch names are ignored) — so a crashed increment resumes on the same `spec/` / `feat/` branches even if the title changed.
6. **Done is done.** A `ready` issue whose `feat/` PR already merged (a finished issue someone reopened) is skipped: further changes need a new issue.

Issues follow the **Feature / backlog item** form (`.github/ISSUE_TEMPLATE/feature_request.yml`): **Problem** and **Acceptance criteria** (WHEN … THEN …, one per line) are the slice's goal; **Out of scope** is binding; **Depends on**, **Needs a human first** (preconditions checked before starting), **Change name** and **Notes** are optional — the proposer passes Notes to `/opsx:propose` as design guidance (an issue `/kmp-forge-refine` designed carries the `kmp-architect` agent's technical notes there; the loop itself never runs the architect). Bug reports (the **Bug report** form) work too: **What happened?** (steps, expected vs actual) plus optional **Acceptance criteria** are the goal, and the code PR is titled `fix(…)`.

Per increment the loop adds `in-progress` when it starts, the docs PR says `Refs #<issue>`, the code PR `Fixes #<issue>` (merging closes the issue), and the loop then removes `in-progress`. Non-blocking findings worth keeping become one **follow-up issue** — filed without `ready`, so you decide. When no `ready` issue is left it prints the configured **queue-empty handoff** (from `openspec/AUTOLOOP.md`) with the issues it skipped and why, and stops. With `queue-empty-refine: on` (the install default) it first spawns the `kmp-product-owner` agent in gaps mode and files up to 3 drafted next slices from the MVP spec — without `ready`, so the next increment starts only when you approve one. It never labels anything `ready`.

## Installing

`/kmp-forge-add-autoloop` — checks preconditions (git, `gh` auth + a reachable GitHub `origin`, a PR CI workflow, `jq`, `python3` ≥ 3.8 — the issue queue and the merge guard both need it — and `openspec` ≥ 1.14), runs `openspec init --tools claude` if needed (plus kmp-forge's `openspec/config.yaml` rules), seeds `openspec/AUTOLOOP.md`, creates the issue labels (after asking), files your first slices as issues (or migrates a legacy `openspec/backlog.md`), installs the merge guard + `.claude/settings.json` wiring (smoke-tested through the wired command), gitignores the audit log and the kill switch, and appends the CLAUDE.md section. The agents and the orchestrator command ship with the plugin — nothing per-project to copy, and plugin updates reach every project. Re-running it updates a stale guard (`# version:` header); once the guard enforces, it shows you the commands to apply the update yourself, since Claude may not write the guard's files.

## Branch protection

Keep **"Require a pull request before merging"** on `main` — but the loop also pushes its own bookkeeping straight to `main` (the runbook edits it commits for you at Phase 0, and the queue-empty archive of finished OpenSpec changes), so the GitHub account `gh` is authenticated as (`gh api user --jq .login`) needs to bypass that rule. Without the bypass those pushes are rejected and the loop escalates.

With a **ruleset** (Settings → Rules → Rulesets → New branch ruleset, targeting the default branch):

- enable *Require a pull request before merging* with **0** required approvals — the loop runs as your account, gates post comment reviews, and GitHub forbids approving your own PR;
- enable *Require status checks to pass* (the PR gate's jobs), *Block force pushes* and *Restrict deletions*;
- under **Bypass list**, add the role or app that account acts as — on a personal repository *Repository admin* (the owner); on an organization repository the team or role the account has — set to **Always** (*For pull requests only* still rejects the direct pushes).

With **classic branch protection**, leave *Do not allow bypassing the above settings* unchecked so the repository admin can push.

The bypass is not a hole for Claude: in `enforce` the merge guard lets the orchestrator push to `main` only changes confined to `openspec/**`, never forced or deleting, and never from a subagent; everything else reaches `main` through a PR with green checks and a PASS gate. It does let *you* push anything — that account is yours.

## Coexistence with supervised work

Projects scaffolded with OpenSpec (the `/kmp-forge-init` default) already work this way; installing the loop on a plain-docs project adds OpenSpec project-wide. Either way **OpenSpec takes priority once present**: supervised sessions route behavior changes through the same workflow the loop uses — `/opsx:propose` → (optionally `kmp-spec-critic`) → `/opsx:apply` — rather than editing behavior directly. `openspec/specs/**` is the record `kmp-spec-critic` judges dependency-safety against; a supervised edit that changes spec-covered behavior without a spec delta silently invalidates that record, and future loop proposals get judged against stale specs.

Direct edits remain right for: docs, formatting and build chores, and refactors with no spec-visible behavior change. If you must hot-fix spec-covered behavior directly, follow up with a spec delta so the record catches up.

## Limitations

- **The gates + CI are the only barrier** between a proposal and `main` — by design, and reversible via `git revert` of any squashed PR commit. Watch the first 1–2 increments live before leaving it unattended.
- **UI/UX slices should not auto-merge**: with `qa: device` the `kmp-qa` reviewer proves UI scenarios *work* on a device (journeys + screenshots), but nothing judges look and feel unattended. Keep the loop on logic/state/data slices plus functional UI; gate visual/UX slices for human review (open the PR, stop).
- **QA covers Android only.** Journeys run on an Android device through Google's Android CLI — a running emulator, else a connected physical device, else an AVD it boots (`qa-device:` pins one); iOS, desktop and web behavior is covered by the tagged tests alone. On a physical device it touches only the app under test, never removes a differently-signed install and skips a locked phone. It drives devices through the Android CLI (adb only to list devices and to tap / type). With no usable device it fails the gate (`ERROR`) rather than passing.
- **Branch protection:** "require approvals" blocks the loop (GitHub forbids self-approval; gates post comment-reviews). Supported: a required PR with zero approvals plus required checks and the bypass in [Branch protection](#branch-protection), or no protection with the guard in `enforce`.
- `/loop` and `/code-review` are Claude Code features the loop depends on; `kmp-loop-code-reviewer` falls back to reviewing the diff itself if `/code-review` is unavailable.
- The `### 🤖 <gate> — round r/3 — <VERDICT>` header is a contract shared by the orchestrator (posts it), its resume logic (parses it), and the merge guard (checks it) — change all three together. The guard only trusts reviews posted by the loop's own GitHub account, so another reviewer's `🤖` comment cannot pass (or block) a merge.
- **Least privilege.** The loop's worker agents declare explicit `tools:` (no MCP connectors; the code reviewer has no Write/Edit), because they read untrusted PR, CI and code text unattended. In the enforce modes nothing Claude runs may change the guard's files — the mode is the human's lever, changed outside Claude, and a downgrade shows up in `git diff` of the tracked mode file.
- The guard sees tool calls only, and reads command text: it cannot see inside a script file a command runs (`bash x.sh`, `./gradlew`), it does not stop committed changes from reaching its files through branch operations (`git switch <branch>`, `git pull`, `git merge`), and a PR that changes `.claude/**` or `openspec/AUTOLOOP.md` (whose `ready-approvers` decides whose issues are trusted) is judged by the gates like any other — review such diffs yourself. It cannot stop a human (or a CI workflow with write access) from merging, and it does not cover tools you add later under names it does not match.
