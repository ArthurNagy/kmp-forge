---
description: Install the autonomous build loop into an existing kmp-forge project — OpenSpec workflow, backlog + runbook, merge-guard hook, and the /kmp-forge-next-increment entry point.
---

# /kmp-forge-add-autoloop

Opt-in installer for the autonomous build loop described in [docs/autoloop.md](https://github.com/arthurnagy/kmp-forge/blob/main/docs/autoloop.md): `/loop /kmp-forge-next-increment` repeatedly pops a backlog slice, proposes it as an OpenSpec change (docs PR, spec-gated by `kmp-spec-critic`), implements it (code PR, gated by `kmp-loop-code-reviewer` + `kmp-reviewer`), and auto-merges only when CI is green AND the posted gate verdict reads PASS — with a `PreToolUse` merge-guard hook enforcing that as code.

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
command -v openspec >/dev/null || echo "✗ openspec missing — npm install -g @fission-ai/openspec"
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

The loop's spec workflow is OpenSpec's `/opsx:*` commands (see `docs/product-workflow.md` — OpenSpec is opt-in, and this is the path that opts in).

```bash
if [[ -d "$TARGET/openspec" ]]; then
    openspec list   # sanity: existing install responds
else
    (cd "$TARGET" && openspec init --tools claude)   # non-interactive
fi
# The workers invoke these — verify they landed:
ls "$TARGET/.claude/commands/opsx/propose.md" "$TARGET/.claude/commands/opsx/apply.md" \
  || echo "✗ /opsx:propose or /opsx:apply missing — openspec init did not provision the Claude commands (openspec >= 1.3 required)"
```

### 2. Choices

Use `AskUserQuestion` to collect the following. Do NOT skip any:

1. **Merge-guard starting mode** — `log` (recommended: observe first, flip to `enforce` after the log agrees with the loop — the trust ramp), `enforce` (strict from the first merge), or `enforce-ci` (CI-green-only; for using the guard *without* the loop).
2. **Queue-empty handoff** — what the loop should print when the backlog empties: the generic default ("Queue empty. Extend openspec/backlog.md with the next phase's slices, or stop here.") or a project-specific checkpoint the user dictates (e.g. "review the eval output and decide go/no-go before Phase 1"). This becomes `AUTOLOOP_HANDOFF`.
3. **Seed the backlog** — template with the commented example only, or dictate the first real slices now (write them in the item format: `slug:` / `goal:` / `boundaries:` / optional `needs-human:`).

### 3. Render and install the overlay

```bash
OVERLAY="${CLAUDE_PLUGIN_ROOT}/overlay"
SH="${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh"

export APP_NAME="<from the project CLAUDE.md Product section>"
export SCAFFOLD_DATE="$(date -u +%Y-%m-%d)"
export AUTOLOOP_HANDOFF="<from step 2>"

bash "$SH" render "$OVERLAY/autoloop" /tmp/kmpf-autoloop
```

Place the rendered files — **diff + Edit-merge, never clobber, if a target already exists**:

```bash
# Runbook + backlog → openspec/
for f in AUTOLOOP.md backlog.md; do
    if [[ -f "$TARGET/openspec/$f" ]]; then
        git --no-pager diff --no-index "$TARGET/openspec/$f" "/tmp/kmpf-autoloop/$f" || true
        # merge with the Edit tool — the ## Loop configuration section must end up present verbatim
    else
        cp "/tmp/kmpf-autoloop/$f" "$TARGET/openspec/$f" && echo "added: openspec/$f"
    fi
done

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

If the user dictated backlog slices in step 2, write them into `openspec/backlog.md`'s `## Queue` now (Edit tool, item format).

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
Launch: `/loop /kmp-forge-next-increment`. Work queue + stop condition: `openspec/backlog.md`
(loop stops when empty). Runbook (config, gates, kill switch, escalation): `openspec/AUTOLOOP.md`.
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
✓ openspec/AUTOLOOP.md: loop configuration + queue-empty handoff
✓ openspec/backlog.md: <template | N slices seeded>
✓ Merge guard: .claude/hooks/merge-guard.sh, mode=<mode>, audit line verified
✓ Hook wiring: .claude/settings.json <created | merged> (jq-valid)
✓ CLAUDE.md: Autonomous build loop section

Next:
  1. Review the diff, commit, open a PR from chore/add-autoloop, merge it.
  2. Restart Claude Code — hooks register at session start.
  3. Fill openspec/backlog.md's Queue with real slices.
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
