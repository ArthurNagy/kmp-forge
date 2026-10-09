---
description: Install the autonomous build loop into an existing kmp-forge project — OpenSpec workflow, GitHub-issue work queue + runbook, merge-guard hook, and the /kmp-forge-next-increment entry point.
---

# /kmp-forge-add-autoloop

Opt-in installer for the autonomous build loop described in [docs/autoloop.md](https://github.com/arthurnagy/kmp-forge/blob/main/docs/autoloop.md): `/loop /kmp-forge-next-increment` repeatedly takes the next `ready` GitHub issue, proposes it as an OpenSpec change (docs PR, spec-gated by `kmp-spec-critic`), implements it (code PR, gated by `kmp-loop-code-reviewer` + `kmp-reviewer`), and auto-merges only when CI is green AND the posted gate verdict reads PASS — with a `PreToolUse` merge-guard hook enforcing that as code.

Everything lands on a branch; the loop itself runs from `main` after you merge. Execute steps **in order**. Stop and ask if anything is unclear.

## Conventions

- **Always quote paths** (`"$TARGET"`) — the user's Personal projects directory contains a space.
- **Never blind-overwrite** an existing file. If a target exists, render to scratch, `git diff --no-index`, and merge with the Edit tool after showing the user.
- The plugin does NOT push to GitHub or enable branch protection. The user opts into both manually.

---

### 0. Preconditions

The user must run this from the **root of a kmp-forge project**. All of these are hard requirements — if one fails, stop, tell the user the remediation, and go no further:

```bash
TARGET="$PWD"
[[ -f "$TARGET/settings.gradle.kts" ]] || echo "✗ no settings.gradle.kts — run from project root"
git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 || echo "✗ not a git repository"
git -C "$TARGET" diff --quiet && git -C "$TARGET" diff --cached --quiet || echo "✗ working tree dirty — commit or stash first"
command -v jq >/dev/null || echo "✗ jq missing (brew install jq) — the merge guard needs it"
command -v gh >/dev/null || echo "✗ gh missing (brew install gh)"
gh auth status >/dev/null 2>&1 || echo "✗ gh not authenticated — run: gh auth login"
gh repo view "$(git -C "$TARGET" remote get-url origin 2>/dev/null)" --json nameWithOwner -q .nameWithOwner >/dev/null 2>&1 \
  || echo "✗ origin is not a reachable GitHub repo — the loop opens and merges PRs there"
[[ -f "$TARGET/.github/workflows/pr.yml" ]] \
  || echo "✗ no .github/workflows/pr.yml — the merge guard refuses PRs with no checks. Add the kmp-forge PR gate first (see below)"
command -v python3 >/dev/null || echo "✗ python3 missing — the issue queue (scripts/issues.sh) needs it"
v="$(openspec --version 2>/dev/null || true)"
[[ -n "$v" && "$(printf '%s\n' 1.14.0 "$v" | sort -V | head -1)" == 1.14.0 ]] \
  || echo "✗ openspec >= 1.14 needed (found: ${v:-none}) — brew install openspec / brew upgrade openspec, or npm install -g @fission-ai/openspec@latest"
# A legacy backlog file is migrated to issues in step 3 — but not mid-increment: its in-flight
# branches (spec/<slug>, feat/<slug>) would not match the issue-numbered names.
if [[ -f "$TARGET/openspec/backlog.md" ]]; then
    gh pr list --state open --json number,headRefName \
      --jq '.[] | select(.headRefName | test("^(spec|feat)/")) | "✗ loop PR #\(.number) (\(.headRefName)) still open — finish or close it before migrating the backlog"'
fi
```

**No `pr.yml`?** `/kmp-forge-init` ships it. For an adopted or hand-built project, render the plugin's PR gate and commit it (merge by hand if a differently-named workflow already runs the same gate — the loop only needs *some* required checks on every PR):

```bash
export APP_NAME="<from the project CLAUDE.md>" BASE_PACKAGE="<base package>"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render "${CLAUDE_PLUGIN_ROOT}/overlay/ci" /tmp/kmpf-ci
mkdir -p "$TARGET/.github/workflows" && cp /tmp/kmpf-ci/pr.yml "$TARGET/.github/workflows/pr.yml"
```

Then create the branch:

```bash
git -C "$TARGET" switch -c chore/add-autoloop
```

### 1. OpenSpec

The loop's spec workflow is OpenSpec's `/opsx:*` commands plus kmp-forge's project rules in
`openspec/config.yaml` (see `docs/product-workflow.md` — `/kmp-forge-init` sets this up by default;
this is the path for a project that chose plain docs, or predates it).

```bash
if [[ -d "$TARGET/openspec" ]]; then
    openspec list   # sanity: existing install responds
else
    openspec init --tools claude --no-animation "$TARGET"   # non-interactive
fi
# The workers invoke these — verify they landed:
ls "$TARGET/.claude/commands/opsx/propose.md" "$TARGET/.claude/commands/opsx/apply.md" \
  || echo "✗ /opsx:propose or /opsx:apply missing — openspec init did not provision the Claude commands (openspec >= 1.3 required)"
```

### 2. Choices

Use `AskUserQuestion` to collect the following (it takes up to 4 questions per call — ask in two). Do NOT skip any:

1. **Merge-guard starting mode** — `log` (recommended: observe first, flip to `enforce` after the log agrees with the loop — the trust ramp), `enforce` (strict from the first merge), or `enforce-ci` (CI-green-only; for using the guard *without* the loop).
2. **Queue-empty handoff** — what the loop should print when no `ready` issue is left: the generic default ("Queue empty. Approve the drafted issues (or run /kmp-forge-refine) by labeling them `ready`, or stop here.") or a project-specific checkpoint the user dictates (e.g. "review the eval output and decide go/no-go before Phase 1"). This becomes `AUTOLOOP_HANDOFF`.
3. **Ready approvers** — whose issues and `ready` labels the loop trusts besides its own account: **just me** (default — empty) or a comma-separated list of GitHub logins (collaborators who triage). This becomes `READY_APPROVERS`.
4. **QA in the code gate** — `device` (recommended when `android emulator list` shows an AVD or a phone is connected: the `kmp-qa` reviewer runs each user-visible scenario as a journey on a running emulator, a connected physical device, or an AVD it boots — pin one later with `qa-device:` in the runbook), `tests-only` (it only checks every scenario has a `// Scenario:`-tagged test), or `off`. This becomes `AUTOLOOP_QA`.
5. **First work** — skip, or dictate the first slices now (filed as issues in step 3; the user labels them `ready`). If `openspec/backlog.md` exists, this question is instead: migrate its unchecked items to issues (recommended), or keep the file for reference and start fresh.

### 3. Render and install the overlay

```bash
OVERLAY="${CLAUDE_PLUGIN_ROOT}/overlay"
SH="${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh"

export APP_NAME="<from the project CLAUDE.md Product section>"
export SCAFFOLD_DATE="$(date -u +%Y-%m-%d)"
export AUTOLOOP_HANDOFF="<from step 2>"
export READY_APPROVERS="<from step 2 — empty for just the loop's account>"
export AUTOLOOP_QA="<device | tests-only | off — from step 2>"

bash "$SH" render "$OVERLAY/autoloop" /tmp/kmpf-autoloop
bash "$SH" render "$OVERLAY/openspec" /tmp/kmpf-openspec     # kmp-forge's OpenSpec rules (needs APP_NAME)
```

Bash tool calls don't share variables: start each block below with `TARGET="$PWD"` (step 0) and
reuse only the rendered files under `/tmp/kmpf-*`.

Place the rendered files — **diff + Edit-merge, never clobber, if a target already exists**:

```bash
TARGET="$PWD"
# Runbook → openspec/
if [[ -f "$TARGET/openspec/AUTOLOOP.md" ]]; then
    git --no-pager diff --no-index "$TARGET/openspec/AUTOLOOP.md" /tmp/kmpf-autoloop/AUTOLOOP.md || true
    # merge with the Edit tool — the ## Loop configuration section must end up present verbatim.
    # A pre-0.5 runbook has `- backlog: …`: replace that line with `- ready-approvers: …`.
    # A 0.5.0 runbook says `queue-empty-groom`: rename the key (and its comment) to `queue-empty-refine`, keeping its value.
else
    cp /tmp/kmpf-autoloop/AUTOLOOP.md "$TARGET/openspec/AUTOLOOP.md" && echo "added: openspec/AUTOLOOP.md"
fi

# kmp-forge's OpenSpec project rules (absent → add; present → diff, merge by hand)
if grep -q "kmp-forge project rules" "$TARGET/openspec/config.yaml" 2>/dev/null; then
    git --no-pager diff --no-index "$TARGET/openspec/config.yaml" /tmp/kmpf-openspec/config.yaml || true
elif [[ -f "$TARGET/openspec/config.yaml" ]] && grep -qvE '^[[:space:]]*(#|$|schema:)' "$TARGET/openspec/config.yaml"; then
    git --no-pager diff --no-index "$TARGET/openspec/config.yaml" /tmp/kmpf-openspec/config.yaml || true
    # the project has its own rules: merge ours in with the Edit tool
else
    cp /tmp/kmpf-openspec/config.yaml "$TARGET/openspec/config.yaml" && echo "added: openspec/config.yaml"
fi

# The work queue's labels (ready, in-progress, epic, priority:*, no-spec, chore, adr) — idempotent
(cd "$TARGET" && bash "${CLAUDE_PLUGIN_ROOT}/scripts/issues.sh" labels)

# Merge guard → .claude/hooks/
mkdir -p "$TARGET/.claude/hooks"
if [[ -f "$TARGET/.claude/hooks/merge-guard.sh" ]]; then
    # Already installed — compare versions (the '# version:' header line) and show the diff;
    # offer to update via Edit. Do not touch merge-guard.mode on re-run.
    git --no-pager diff --no-index "$TARGET/.claude/hooks/merge-guard.sh" /tmp/kmpf-autoloop/merge-guard.sh || true
else
    cp /tmp/kmpf-autoloop/merge-guard.sh "$TARGET/.claude/hooks/merge-guard.sh"
    chmod +x "$TARGET/.claude/hooks/merge-guard.sh"
    # Tracked on purpose: the mode is project policy, so a fresh clone keeps it. Changing it
    # later = edit + commit (the loop also commits an uncommitted mode change as a steering edit).
    echo "<mode from step 2>" > "$TARGET/.claude/hooks/merge-guard.mode"
fi

# Local-only files: the audit log, and the kill switch (a worker's commit must never pick it up).
# If AUTOLOOP.md's kill-switch: is customized, ignore that path instead of openspec/STOP.
for ignore in ".claude/hooks/merge-guard.log" "openspec/STOP"; do
    grep -qxF "$ignore" "$TARGET/.gitignore" 2>/dev/null || echo "$ignore" >> "$TARGET/.gitignore"
done
```

**First work / backlog migration** (step 2, question 5). File each slice as an issue shaped like
the **Feature / backlog item** form — `### Problem`, `### Acceptance criteria` (WHEN … THEN …
lines; write them from the slice's goal), `### Out of scope`, `### Depends on`,
`### Needs a human first`, `### Change name`, `### Notes` — in queue order (issue numbers then
preserve it), and **without** the `ready` label:

```bash
gh issue create --title "<what the slice delivers>" --label enhancement --body-file <body.md>
```

Migrating a legacy `openspec/backlog.md`: one issue per **unchecked** item, top to bottom —
`goal:` → Problem (and the acceptance criteria you derive from it), `boundaries:` → Out of scope,
`needs-human:` → Needs a human first, `slug:` → Change name, `carried-over:` → Notes. Checked
items stay in git history only. Then `git rm "$TARGET/openspec/backlog.md"`.

Either way, finish by printing the one command that queues them — the user runs it; you never
apply `ready`:

```
gh issue edit <n1> <n2> … --add-label ready
```

### 4. Hook wiring — settings.json

The reference wiring is `/tmp/kmpf-autoloop/settings.json`. **Never blind-overwrite an existing settings file:**

- `"$TARGET/.claude/settings.json"` **absent** → `cp /tmp/kmpf-autoloop/settings.json "$TARGET/.claude/settings.json"`.
- **Present** → show `git diff --no-index`, then merge with the Edit tool, additively: create the `hooks` / `PreToolUse` keys if missing; append the merge-guard matcher block to any existing `PreToolUse` array. If a merge-guard entry is already wired, make it match the reference **exactly** — `matcher` (`Bash|Write|Edit|MultiEdit|NotebookEdit|mcp__.*`), the quoted `command`, and `timeout` — and change nothing else. (Pre-v2 installs wired an unquoted `${CLAUDE_PROJECT_DIR}/.claude/hooks/merge-guard.sh`: on any path containing a space the shell splits it, the hook exits 127, Claude Code treats that as non-blocking, and the guard silently never runs.)

Validate the result — a malformed settings.json disables ALL hooks:

```bash
jq . "$TARGET/.claude/settings.json" >/dev/null && echo "settings.json valid"
```

### 5. CLAUDE.md

Append an `## Autonomous build loop` section to the project's `CLAUDE.md` via the Edit tool (skip if one exists — idempotent):

```markdown
## Autonomous build loop
Launch: `/loop /kmp-forge-next-increment`. Work queue + stop condition: open GitHub issues labeled
`ready` (only a human applies it; the loop stops when none is left). Runbook (config, gates, queue
rules, kill switch, escalation): `openspec/AUTOLOOP.md`.
Each increment auto-merges to `main` only when CI is green **and** its gate passes — spec gate =
`kmp-spec-critic`, code gate = `kmp-loop-code-reviewer` + `kmp-reviewer`; otherwise it stops and
escalates. Emergency stop: create the kill-switch file named in `openspec/AUTOLOOP.md`
(default `openspec/STOP`); delete it to resume.

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
export CLAUDE_PROJECT_DIR="$TARGET"
HOOK_CMD="$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.command | contains("merge-guard"))][0].command' "$TARGET/.claude/settings.json")"
echo "wired: $HOOK_CMD"
# 1. Non-guarded command → exit 0, no output
echo '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}' | sh -c "$HOOK_CMD"; echo "exit=$?"
# 2. Merge-shaped command → exit 0 and a new audit line (BLOCK is expected — PR 999 doesn't exist)
echo '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 999 --squash"}}' | sh -c "$HOOK_CMD" >/dev/null; echo "exit=$?"
tail -1 "$TARGET/.claude/hooks/merge-guard.log" | cut -f2,4,5,6
# 3. The same merge from a subagent → its audit line must say caller=<agent type>
echo '{"tool_name":"Bash","agent_id":"smoke","agent_type":"smoke-test","tool_input":{"command":"gh pr merge 999"}}' | sh -c "$HOOK_CMD" >/dev/null
tail -1 "$TARGET/.claude/hooks/merge-guard.log" | cut -f2,4,5,6
```

Expect `exit=0` twice, no output from (1), and two new log lines (`caller=main`, then `caller=smoke-test`). An `exit=127` or "No such file or directory" means the wiring is broken — fix step 4 before going further.

### 7. Report

```
✓ Branch: chore/add-autoloop
✓ OpenSpec: <initialized | already present> (/opsx:propose, /opsx:apply verified)
✓ openspec/AUTOLOOP.md: loop configuration + queue-empty handoff + ready-approvers
✓ openspec/config.yaml: kmp-forge project rules <added | merged | already present>
✓ Issue labels: ready, in-progress, epic, priority:high|low, no-spec, chore, adr
✓ Work queue: <N issues filed | N backlog items migrated, backlog.md removed | none yet>
✓ Merge guard: .claude/hooks/merge-guard.sh, mode=<mode>, audit line verified
✓ Hook wiring: .claude/settings.json <created | merged> (jq-valid)
✓ CLAUDE.md: Autonomous build loop section

Next:
  1. Review the diff, commit, open a PR from chore/add-autoloop, merge it.
  2. Restart Claude Code — hooks register at session start.
  3. Label the issues to build `ready` (gh issue edit <n…> --add-label ready).
  4. Launch: /loop /kmp-forge-next-increment
  5. After 1–2 increments: cut -f2,5,6 .claude/hooks/merge-guard.log — every loop
     merge should show ALLOW. Then switch on enforcement and commit it (the mode is tracked):
       echo enforce > .claude/hooks/merge-guard.mode
       git commit -m "chore(autoloop): enforce merge guard" -- .claude/hooks/merge-guard.mode && git push
```

## Notes

- **Branch protection:** the loop merges its own PRs, and GitHub blocks self-approval — so "require approvals" on `main` makes the loop unable to merge. Supported setups: no branch protection + guard in `enforce`, or protection with required status checks but zero required approvals. Do NOT enable protection from this command.
- `/loop` and `/code-review` are Claude Code features, not plugin components — the loop depends on both being available in the user's CLI.
- Non-destructive by design: everything lands on `chore/add-autoloop`; existing files are diffed and hand-merged, never clobbered. Re-running is safe and acts as an updater: it diffs the installed merge-guard against the plugin's copy (compare the `# version:` header lines — the plugin bumps it on every guard change) and re-checks the settings.json wiring. Re-run it from the main conversation — the guard denies a **subagent** that edits its files.
- The loop agents (`kmp-loop-*`, `kmp-spec-critic`) and the orchestrator command ship with the plugin itself — nothing to install per-project beyond this overlay, and plugin updates reach every project automatically.
