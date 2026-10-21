---
description: Install the autonomous build loop into an existing kmp-forge project — OpenSpec workflow, GitHub-issue work queue + runbook, merge-guard hook, and the /kmp-forge-next-increment entry point.
disable-model-invocation: true
---

# /kmp-forge-add-autoloop

Opt-in installer for the autonomous build loop described in [docs/autoloop.md](https://github.com/arthurnagy/kmp-forge/blob/main/docs/autoloop.md): `/loop /kmp-forge-next-increment` repeatedly takes the next `ready` GitHub issue, proposes it as an OpenSpec change (docs PR, spec-gated by `kmp-spec-critic`), implements it (code PR, gated by `kmp-loop-code-reviewer` + `kmp-reviewer` + `kmp-qa`), and auto-merges only when CI is green AND the posted gate verdict reads PASS — with a `PreToolUse` merge-guard hook enforcing that as code.

Everything lands on a branch; the loop itself runs from `main` after you merge. Execute steps **in order**. Stop and ask if anything is unclear.

## Conventions

- Quote paths and brace variables (`"${TARGET}"` — the Bash tool may run zsh; the folder may contain spaces).
- **Shell state doesn't survive between Bash calls.** Step 0 writes `TARGET` to
  `"${TMPDIR:-/tmp}/kmp-forge-add-autoloop.env"`; step 3 rewrites it with every later variable. Every later block
  starts by `source`-ing it.
- **Never blind-overwrite** an existing file. If a target exists, render to scratch (`"${TMPDIR:-/tmp}/kmpf-…"`), `git --no-index diff`, and merge with the Edit tool after showing the user.
- This command does NOT push to GitHub or enable branch protection. The user does both themselves.
- **An enforcing merge guard is off limits — to you too.** Once a project's guard runs in `enforce` or `enforce-ci` (or its mode file is missing, which means `enforce-ci`), it denies Claude writing `.claude/hooks/merge-guard.*`, `.claude/settings*.json` and `openspec/AUTOLOOP.md`, even from this command, and in this session if the hook is already wired. Then show the diff and give the user the exact commands to run themselves (in a terminal, or with `!` in front at the prompt). Never work around a denial.

---

### 0. Preconditions

The user must run this from the **root of a kmp-forge project**. All of these are hard requirements — if one fails, stop, tell the user the remediation, and go no further:

```bash
TARGET="${PWD}"
typeset -p TARGET > "${TMPDIR:-/tmp}/kmp-forge-add-autoloop.env"
[[ -f "${TARGET}/settings.gradle.kts" ]] || echo "✗ no settings.gradle.kts — run from project root"
git -C "${TARGET}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || echo "✗ not a git repository"
git -C "${TARGET}" diff --quiet && git -C "${TARGET}" diff --cached --quiet || echo "✗ working tree dirty — commit or stash first"
command -v jq >/dev/null || echo "✗ jq missing (brew install jq) — the install steps need it"
command -v gh >/dev/null || echo "✗ gh missing (brew install gh)"
gh auth status >/dev/null 2>&1 || echo "✗ gh not authenticated — run: gh auth login"
gh repo view "$(git -C "${TARGET}" remote get-url origin 2>/dev/null)" --json nameWithOwner -q .nameWithOwner >/dev/null 2>&1 \
  || echo "✗ origin is not a reachable GitHub repo — the loop opens and merges PRs there"
[[ -f "${TARGET}/.github/workflows/pr.yml" ]] \
  || echo "✗ no .github/workflows/pr.yml — the merge guard refuses PRs with no checks. Add the kmp-forge PR gate first (see below)"
python3 -c 'import sys; sys.exit(sys.version_info < (3, 8))' 2>/dev/null \
  || echo "✗ python3 >= 3.8 missing — the issue queue (scripts/issues.sh) and the merge guard need it"
v="$(openspec --version 2>/dev/null || true)"
[[ -n "${v}" && "$(printf '%s\n' 1.14.0 "${v}" | sort -V | head -1)" == 1.14.0 ]] \
  || echo "✗ openspec >= 1.14 needed (found: ${v:-none}) — brew install openspec / brew upgrade openspec, or npm install -g @fission-ai/openspec@latest"
# A legacy backlog file is migrated to issues in step 3 — but not mid-increment: its in-flight
# branches (spec/<slug>, feat/<slug>) would not match the issue-numbered names.
if [[ -f "${TARGET}/openspec/backlog.md" ]]; then
    gh pr list --state open --json number,headRefName \
      --jq '.[] | select(.headRefName | test("^(spec|feat)/")) | "✗ loop PR #\(.number) (\(.headRefName)) still open — finish or close it before migrating the backlog"'
fi
```

**No `pr.yml`?** `/kmp-forge-init` ships it. For an adopted or hand-built project, render the plugin's PR gate and commit it (merge by hand if a differently-named workflow already runs the same gate — the loop only needs *some* required checks on every PR):

```bash
source "${TMPDIR:-/tmp}/kmp-forge-add-autoloop.env"; : "${TARGET:?}"
export APP_NAME='<from the project CLAUDE.md>' BASE_PACKAGE='<base package>'
rm -rf "${TMPDIR:-/tmp}/kmpf-ci"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render "${CLAUDE_PLUGIN_ROOT}/overlay/ci" "${TMPDIR:-/tmp}/kmpf-ci"
mkdir -p "${TARGET}/.github/workflows" && cp "${TMPDIR:-/tmp}/kmpf-ci/pr.yml" "${TARGET}/.github/workflows/pr.yml"
```

Then create the branch:

```bash
source "${TMPDIR:-/tmp}/kmp-forge-add-autoloop.env"; git -C "${TARGET:?}" switch -c chore/add-autoloop
```

### 1. OpenSpec

The loop's spec workflow is OpenSpec's `/opsx:*` commands plus kmp-forge's project rules in
`openspec/config.yaml` (see `docs/product-workflow.md` — `/kmp-forge-init` sets this up by default;
this is the path for a project that chose plain docs, or predates it).

```bash
source "${TMPDIR:-/tmp}/kmp-forge-add-autoloop.env"; : "${TARGET:?}"
if [[ -d "${TARGET}/openspec" ]]; then
    (cd "${TARGET}" && openspec list)   # sanity: existing install responds
else
    openspec init --tools claude --no-animation "${TARGET}"   # non-interactive
fi
# The workers invoke these — verify they landed:
ls "${TARGET}/.claude/commands/opsx/propose.md" "${TARGET}/.claude/commands/opsx/apply.md" \
  || echo "✗ /opsx:propose or /opsx:apply missing — openspec init did not provision the Claude commands (openspec >= 1.14 required)"
```

### 2. Choices

Use `AskUserQuestion` to collect the following (it takes up to 4 questions per call — ask in two). Do NOT skip any:

1. **Merge-guard starting mode** — `log` (recommended: observe first, flip to `enforce` after the log agrees with the loop — the trust ramp), `enforce` (strict from the first merge), or `enforce-ci` (CI-green-only; for using the guard *without* the loop). In both enforce modes Claude can no longer edit the guard's own files — the user changes its mode by hand.
2. **Queue-empty handoff** — what the loop should print when no `ready` issue is left: the generic default ("Queue empty. Approve the drafted issues (or run /kmp-forge-refine) by labeling them `ready`, or stop here.") or a project-specific checkpoint the user dictates (e.g. "review the eval output and decide go/no-go before Phase 1"). This becomes `AUTOLOOP_HANDOFF`.
3. **Ready approvers** — whose issues and `ready` labels the loop trusts besides its own account: **just me** (default — empty) or a comma-separated list of GitHub logins (collaborators who triage). This becomes `READY_APPROVERS`.
4. **QA in the code gate** — `device` (recommended when `android emulator list` shows an AVD or a phone is connected: the `kmp-qa` reviewer runs each user-visible scenario as a journey on a running emulator, a connected physical device, or an AVD it boots — pin one later with `qa-device:` in the runbook), `tests-only` (it only checks every scenario has a `// Scenario:`-tagged test), or `off`. This becomes `AUTOLOOP_QA`.
5. **Issue labels** — create the work queue's labels on the GitHub repository now (`ready`, `in-progress`, `priority:high`, `priority:low`, `no-spec`, `chore`, `adr`; existing labels are left exactly as they are)? This writes to GitHub: **yes**, or **no** (the user runs `bash "${CLAUDE_PLUGIN_ROOT}/scripts/issues.sh" labels` later — the loop needs them).
6. **First work** — skip, or dictate the first slices now (filed as issues in step 3 — that writes to GitHub too; the user labels them `ready`). If `openspec/backlog.md` exists, this question is instead: migrate its unchecked items to issues (recommended), or keep the file for reference and start fresh.

### 3. Render and install the overlay

User-dictated text goes in single quotes (a `'` inside becomes `'\''`) so nothing in it expands:

```bash
source "${TMPDIR:-/tmp}/kmp-forge-add-autoloop.env"; : "${TARGET:?}"
OVERLAY="${CLAUDE_PLUGIN_ROOT}/overlay"
SH="${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh"
SCRATCH="${TMPDIR:-/tmp}/kmpf-autoloop"
GUARD_MODE='<log | enforce | enforce-ci — from step 2>'
LABELS='<yes | no — from step 2>'

export APP_NAME='<from the project CLAUDE.md Product section>'
export SCAFFOLD_DATE="$(date -u +%Y-%m-%d)"
export AUTOLOOP_HANDOFF='<from step 2>'
export READY_APPROVERS='<from step 2 — empty for just the loop account>'
export AUTOLOOP_QA='<device | tests-only | off — from step 2>'

rm -rf "${SCRATCH}" "${TMPDIR:-/tmp}/kmpf-openspec"
bash "${SH}" render "${OVERLAY}/autoloop" "${SCRATCH}"
bash "${SH}" render "${OVERLAY}/openspec" "${TMPDIR:-/tmp}/kmpf-openspec"     # kmp-forge's OpenSpec rules (needs APP_NAME)
typeset -p TARGET SCRATCH GUARD_MODE LABELS > "${TMPDIR:-/tmp}/kmp-forge-add-autoloop.env"
```

Place the rendered files — **diff + Edit-merge, never clobber, if a target already exists**:

```bash
source "${TMPDIR:-/tmp}/kmp-forge-add-autoloop.env"; : "${TARGET:?}" "${SCRATCH:?}" "${GUARD_MODE:?}" "${LABELS:?}"
# Runbook → openspec/
if [[ -f "${TARGET}/openspec/AUTOLOOP.md" ]]; then
    git --no-pager diff --no-index "${TARGET}/openspec/AUTOLOOP.md" "${SCRATCH}/AUTOLOOP.md" || true
    # merge with the Edit tool — the ## Loop configuration section must end up present verbatim
    # (an enforcing guard denies that edit: hand it to the user, as in Conventions).
    # A pre-0.5 runbook has `- backlog: …`: replace that line with `- ready-approvers: …`.
    # A 0.5.0 runbook says `queue-empty-groom`: rename the key (and its comment) to `queue-empty-refine`, keeping its value.
else
    cp "${SCRATCH}/AUTOLOOP.md" "${TARGET}/openspec/AUTOLOOP.md" && echo "added: openspec/AUTOLOOP.md"
fi

# kmp-forge's OpenSpec project rules (absent → add; present → diff, merge by hand)
RULES="${TMPDIR:-/tmp}/kmpf-openspec/config.yaml"
if grep -q "kmp-forge project rules" "${TARGET}/openspec/config.yaml" 2>/dev/null; then
    git --no-pager diff --no-index "${TARGET}/openspec/config.yaml" "${RULES}" || true
elif [[ -f "${TARGET}/openspec/config.yaml" ]] && grep -qvE '^[[:space:]]*(#|$|schema:)' "${TARGET}/openspec/config.yaml"; then
    git --no-pager diff --no-index "${TARGET}/openspec/config.yaml" "${RULES}" || true
    # the project has its own rules: merge ours in with the Edit tool
else
    cp "${RULES}" "${TARGET}/openspec/config.yaml" && echo "added: openspec/config.yaml"
fi

# The work queue's labels — only on a yes in step 2 (writes to GitHub; idempotent)
if [[ "${LABELS}" == yes ]]; then (cd "${TARGET}" && bash "${CLAUDE_PLUGIN_ROOT}/scripts/issues.sh" labels); fi

# Merge guard → .claude/hooks/
mkdir -p "${TARGET}/.claude/hooks"
if [[ -f "${TARGET}/.claude/hooks/merge-guard.sh" ]]; then
    # Already installed: compare the '# version:' headers (the plugin bumps it on every guard change),
    # show the diff. Never touch merge-guard.mode on a re-run.
    installed="$(sed -n 's/^# version: *//p' "${TARGET}/.claude/hooks/merge-guard.sh" | head -1)"
    shipped="$(sed -n 's/^# version: *//p' "${SCRATCH}/merge-guard.sh" | head -1)"
    mode="$(tr -d '[:space:]' < "${TARGET}/.claude/hooks/merge-guard.mode" 2>/dev/null)"
    echo "merge-guard: installed v${installed:-?}, plugin v${shipped}, mode ${mode:-<missing = enforce-ci>}"
    git --no-pager diff --no-index "${TARGET}/.claude/hooks/merge-guard.sh" "${SCRATCH}/merge-guard.sh" || true
else
    cp "${SCRATCH}/merge-guard.sh" "${TARGET}/.claude/hooks/merge-guard.sh"
    chmod +x "${TARGET}/.claude/hooks/merge-guard.sh"
    # Tracked on purpose: the mode is project policy, so a fresh clone keeps it. Changing it later is the
    # user's edit + commit, outside Claude.
    printf '%s\n' "${GUARD_MODE}" > "${TARGET}/.claude/hooks/merge-guard.mode"
fi

# Local-only files: the audit log, and the kill switch (a worker's commit must never pick it up).
# If AUTOLOOP.md's kill-switch: is customized, ignore that path instead of openspec/STOP.
for ignore in ".claude/hooks/merge-guard.log" "openspec/STOP"; do
    grep -qxF "${ignore}" "${TARGET}/.gitignore" 2>/dev/null || echo "${ignore}" >> "${TARGET}/.gitignore"
done
```

**A stale guard** (installed version below the plugin's): after showing the diff, update it with
`cp "${SCRATCH}/merge-guard.sh" "${TARGET}/.claude/hooks/merge-guard.sh"` — when the installed mode is `log` or `off`.
In an enforce mode (or with the mode file missing) the guard denies that write: print the command with both paths
resolved for the user to run (`! cp "<…>/kmpf-autoloop/merge-guard.sh" "<project>/.claude/hooks/merge-guard.sh"`),
and continue once they confirm.

**First work / backlog migration** (step 2, question 6). File each slice as an issue shaped like
the **Feature / backlog item** form — `### Problem`, `### Acceptance criteria` (WHEN … THEN …
lines; write them from the slice's goal), `### Out of scope`, `### Depends on`,
`### Needs a human first`, `### Change name`, `### Notes` — in queue order (issue numbers then
preserve it), and **without** the `ready` label, the body through a file written by a quoted heredoc:

```bash
cat > "${TMPDIR:-/tmp}/kmpf-slice-<k>.md" <<'SLICE_EOF'
<the issue body>
SLICE_EOF
gh issue create --title '<what the slice delivers>' --label enhancement --body-file "${TMPDIR:-/tmp}/kmpf-slice-<k>.md"
```

Migrating a legacy `openspec/backlog.md`: one issue per **unchecked** item, top to bottom, filed the same way —
`goal:` → Problem (and the acceptance criteria you derive from it), `boundaries:` → Out of scope,
`needs-human:` → Needs a human first, `slug:` → Change name, `carried-over:` → Notes. Checked
items stay in git history only. Then `git -C "${TARGET}" rm -q openspec/backlog.md` (after `source`-ing the env file).

Either way, finish by printing the one command that queues them — the user runs it; you never
apply `ready`:

```
gh issue edit <n1> <n2> … --add-label ready
```

### 4. Hook wiring — settings.json

The reference wiring is `"${TMPDIR:-/tmp}/kmpf-autoloop/settings.json"`. **Never blind-overwrite an existing settings file:**

- `"${TARGET}/.claude/settings.json"` **absent** → `cp "${SCRATCH}/settings.json" "${TARGET}/.claude/settings.json"` (after `source`-ing the env file).
- **Present** → show `git diff --no-index`, then merge with the Edit tool, additively: create the `hooks` / `PreToolUse` keys if missing; append the merge-guard matcher block to any existing `PreToolUse` array. If a merge-guard entry is already wired, make it match the reference **exactly** — `matcher` (`Bash|Write|Edit|MultiEdit|NotebookEdit|mcp__.*`), the quoted `command`, and `timeout` — and change nothing else. (Pre-v2 installs wired an unquoted `$CLAUDE_PROJECT_DIR/.claude/hooks/merge-guard.sh` — braced in the file; written
unbraced here because Claude Code expands the braced form in command text: on any path containing a space the shell splits it, the hook exits 127, Claude Code treats that as non-blocking, and the guard silently never runs.) An enforcing guard denies these edits — hand the user the change, as in Conventions.

Validate the result — a malformed settings.json disables ALL hooks:

```bash
source "${TMPDIR:-/tmp}/kmp-forge-add-autoloop.env"; jq . "${TARGET:?}/.claude/settings.json" >/dev/null && echo "settings.json valid"
```

### 5. CLAUDE.md

Append an `## Autonomous build loop` section to the project's `CLAUDE.md` via the Edit tool (skip if one exists — idempotent):

```markdown
## Autonomous build loop
Launch: `/loop /kmp-forge-next-increment`. Work queue + stop condition: open GitHub issues labeled
`ready` (only a human applies it; the loop stops when none is left). Runbook (config, gates, queue
rules, kill switch, escalation): `openspec/AUTOLOOP.md`.
Each increment auto-merges to `main` only when CI is green **and** its gate passes — spec gate =
`kmp-spec-critic`, code gate = `kmp-loop-code-reviewer` + `kmp-reviewer` + `kmp-qa` (unless
`qa: off`); otherwise it stops and escalates. Emergency stop: create the kill-switch file named in
`openspec/AUTOLOOP.md` (default `openspec/STOP`); delete it to resume. The merge guard's mode
(`.claude/hooks/merge-guard.mode`) is changed and committed by a human, never by Claude.

OpenSpec is this project's **primary change workflow, supervised sessions included**: propose
behavior changes via `/opsx:propose` (optionally review with `kmp-spec-critic`), implement via
`/opsx:apply`, and keep `openspec/specs/**` current. Direct edits are for non-behavioral work
only (docs, chores, behavior-neutral refactors) — spec-covered behavior changed without a spec
delta drifts the record the loop's gates judge against.
```

If the project has no `CLAUDE.md`, warn and point at `/kmp-forge-adopt`.

### 6. Smoke check

Prove the guard is wired before anything real happens:

Run the guard through the **exact command string wired in settings.json**, under `sh -c` with `CLAUDE_PROJECT_DIR` set — the way Claude Code runs it — so a quoting mistake in the wiring fails here instead of silently disabling the guard:

```bash
source "${TMPDIR:-/tmp}/kmp-forge-add-autoloop.env"; : "${TARGET:?}"
export CLAUDE_PROJECT_DIR="${TARGET}"
HOOK_CMD="$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.command | contains("merge-guard"))][0].command' "${TARGET}/.claude/settings.json")"
echo "wired: ${HOOK_CMD}"
# 1. Non-guarded command → exit 0, no output
echo '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}' | sh -c "${HOOK_CMD}"; echo "exit=$?"
# 2. Merge-shaped command → exit 0 and a new audit line (BLOCK is expected — PR 999 doesn't exist)
echo '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 999 --squash"}}' | sh -c "${HOOK_CMD}" >/dev/null; echo "exit=$?"
tail -1 "${TARGET}/.claude/hooks/merge-guard.log" | cut -f2,4,5,6
# 3. The same merge from a subagent → its audit line must say caller=<agent type>
echo '{"tool_name":"Bash","agent_id":"smoke","agent_type":"smoke-test","tool_input":{"command":"gh pr merge 999"}}' | sh -c "${HOOK_CMD}" >/dev/null
tail -1 "${TARGET}/.claude/hooks/merge-guard.log" | cut -f2,4,5,6
```

Expect `exit=0` twice, no output from (1), and two new log lines (`caller=main`, then `caller=smoke-test`). An `exit=127` or "No such file or directory" means the wiring is broken — fix step 4 before going further. (On a re-run in a session whose guard already enforces, the guard denies this block — it pipes into `sh -c` and names guard files; give it to the user to run with `!`.)

### 7. Report

```
✓ Branch: chore/add-autoloop
✓ OpenSpec: <initialized | already present> (/opsx:propose, /opsx:apply verified)
✓ openspec/AUTOLOOP.md: loop configuration + queue-empty handoff + ready-approvers
✓ openspec/config.yaml: kmp-forge project rules <added | merged | already present>
✓ Issue labels: <created/kept: ready, in-progress, priority:high|low, no-spec, chore, adr | skipped — run scripts/issues.sh labels>
✓ Work queue: <N issues filed | N backlog items migrated, backlog.md removed | none yet>
✓ Merge guard: .claude/hooks/merge-guard.sh v<version>, mode=<mode>, audit line verified
✓ Hook wiring: .claude/settings.json <created | merged> (jq-valid)
✓ CLAUDE.md: Autonomous build loop section

Next:
  1. Review the diff, commit, open a PR from chore/add-autoloop, merge it.
  2. Restart Claude Code — hooks register at session start.
  3. If main requires pull requests, give the account gh runs as the bypass for the loop's
     openspec/** bookkeeping pushes: docs/autoloop.md § Branch protection.
  4. Label the issues to build `ready` (gh issue edit <n…> --add-label ready).
  5. Launch: /loop /kmp-forge-next-increment
  6. After 1–2 increments: cut -f2,5,6 .claude/hooks/merge-guard.log — every loop
     merge should show ALLOW. Then switch on enforcement yourself, in a terminal (or with `!`
     at the prompt) — the mode is tracked, and Claude can't change it once it enforces:
       echo enforce > .claude/hooks/merge-guard.mode
       git commit -m "chore(autoloop): enforce merge guard" -- .claude/hooks/merge-guard.mode && git push
```

## Notes

- **Branch protection:** the loop merges its own PRs, and GitHub blocks self-approval — so "require approvals" on `main` makes the loop unable to merge. Supported setups: a required pull request with **zero** approvals plus required status checks, with the loop's account on the bypass list for its `openspec/**` bookkeeping pushes ([docs/autoloop.md § Branch protection](https://github.com/arthurnagy/kmp-forge/blob/main/docs/autoloop.md#branch-protection)); or no branch protection with the guard in `enforce`. Do NOT enable protection from this command.
- `/loop` and `/code-review` are Claude Code features, not plugin components — the loop depends on both being available in the user's CLI.
- Non-destructive by design: everything lands on `chore/add-autoloop`; existing files are diffed and hand-merged, never clobbered. Re-running is safe and acts as an updater: it compares the installed merge guard's `# version:` header with the plugin's (bumped on every guard change), shows the diff, and re-checks the settings.json wiring. An enforcing guard denies Claude every write to its files and to `openspec/AUTOLOOP.md` — the user applies those updates.
- The loop agents (`kmp-loop-*`, `kmp-spec-critic`) and the orchestrator command ship with the plugin itself — nothing to install per-project beyond this overlay, and plugin updates reach every project automatically.
