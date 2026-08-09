#!/usr/bin/env bash
# merge-guard.sh — PreToolUse guard on `gh pr merge` for the kmp-forge autonomous build loop.
# version: 1
#
# Installed into a project's .claude/hooks/ by /kmp-forge-add-autoloop.
# Runbook: openspec/AUTOLOOP.md · theory: kmp-forge docs/autoloop.md.
#
# The loop's one irreversible action is merging to `main`. /kmp-forge-next-increment
# states the merge preconditions as a model instruction; this hook enforces them as
# code, independently, for the main conversation AND for every subagent (PreToolUse
# fires for both).
#
# Preconditions for a merge:
#   1. Every check on the PR has concluded successfully.
#   2. The most recent `### 🤖 …` gate review posted to the PR reads PASS.
#
# Modes — read fresh on every invocation from .claude/hooks/merge-guard.mode:
#   log         observe only; never denies. Appends a verdict line to merge-guard.log
#               evaluating BOTH preconditions — this is the trust-ramp signal.
#   enforce-ci  deny the merge unless CI is green. Gate reviews are not evaluated —
#               for supervised projects where the human is the gate.
#   enforce     deny the merge unless both preconditions hold. Fails closed.
#   off         no-op.
#   (unknown)   treated as `log`, with a warning line in the audit log.
#
# Exit 0 always. A deny is expressed as JSON on stdout, per the PreToolUse contract.
# stderr on exit 0 is transcript-only and never enters the model's context.

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
HOOK_DIR="$PROJECT_DIR/.claude/hooks"
MODE_FILE="$HOOK_DIR/merge-guard.mode"
LOG_FILE="$HOOK_DIR/merge-guard.log"

MODE=log
BAD_MODE=""
[ -r "$MODE_FILE" ] && MODE=$(tr -d '[:space:]' < "$MODE_FILE")
case "$MODE" in
  off) exit 0 ;;
  log|enforce-ci|enforce) ;;
  *) BAD_MODE="$MODE"; MODE=log ;;
esac

ENFORCE_CI=0
ENFORCE_GATE=0
case "$MODE" in
  enforce)    ENFORCE_CI=1; ENFORCE_GATE=1 ;;
  enforce-ci) ENFORCE_CI=1 ;;
esac

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Normalise whitespace so `gh  pr   merge` cannot slip past the match.
norm=$(printf '%s' "$cmd" | tr '\n\t' '  ' | tr -s ' ')
case "$norm" in
  *"gh pr merge"*) ;;
  *) exit 0 ;;
esac

agent=$(printf '%s' "$input" | jq -r '.agent_type // "main"' 2>/dev/null)

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
}

# Record every decision, whether or not we act on it. This log is what tells you
# whether the guard agrees with the loop before you flip it to `enforce`.
audit() { # verdict, detail
  mkdir -p "$HOOK_DIR"
  printf '%s\t%s\tmode=%s\tcaller=%s\tpr=%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$MODE" "$agent" "${pr:--}" "$2" "$norm" \
    >> "$LOG_FILE"
}

[ -n "$BAD_MODE" ] && audit WARN "unknown mode '$BAD_MODE' in merge-guard.mode — treating as log"

# --- Resolve the PR number -------------------------------------------------
rest=${norm#*gh pr merge}
pr=$(printf '%s' "$rest" | tr ' ' '\n' | grep -Ex '[0-9]+' | head -1)
if [ -z "$pr" ]; then
  pr=$(printf '%s' "$rest" | grep -oE 'pull/[0-9]+' | grep -oE '[0-9]+' | head -1)
fi
if [ -z "$pr" ]; then
  # Bare `gh pr merge` — resolves to the PR for the current branch.
  pr=$(gh pr view --json number --jq .number 2>/dev/null)
fi
if [ -z "$pr" ]; then
  audit UNRESOLVED "could not determine PR number"
  [ "$ENFORCE_CI" = 1 ] && deny "merge-guard: could not determine which PR this merges. Pass the PR number explicitly."
  exit 0
fi

# --- Precondition 1: all checks concluded successfully ----------------------
rollup=$(gh pr view "$pr" --json statusCheckRollup 2>/dev/null)
if [ -z "$rollup" ]; then
  audit CHECK_ERROR "gh pr view failed (offline? unauthenticated?)"
  [ "$ENFORCE_CI" = 1 ] && deny "merge-guard: could not read CI status for PR #$pr. Failing closed."
  exit 0
fi

ci=$(printf '%s' "$rollup" | jq -r '
  [ .statusCheckRollup[]?
    | { s: (.status // ""), c: (.conclusion // ""), st: (.state // "") } ] as $n
  | if   ($n | length) == 0 then "NONE"
    elif ($n | any(.c == "FAILURE" or .c == "TIMED_OUT" or .c == "CANCELLED"
                   or .c == "ACTION_REQUIRED" or .c == "STARTUP_FAILURE"
                   or .st == "FAILURE" or .st == "ERROR")) then "RED"
    elif ($n | any(.st == "PENDING" or (.s != "" and .s != "COMPLETED"))) then "PENDING"
    else "GREEN" end' 2>/dev/null)

case "$ci" in
  GREEN) ;;
  RED)
    audit BLOCK "CI red"
    [ "$ENFORCE_CI" = 1 ] && deny "merge-guard: PR #$pr has failing checks. The loop must fix CI before merging (max 2 cycles), or escalate."
    exit 0 ;;
  PENDING)
    audit BLOCK "CI pending"
    [ "$ENFORCE_CI" = 1 ] && deny "merge-guard: PR #$pr still has checks in flight. Wait for green before merging."
    exit 0 ;;
  *)
    audit BLOCK "no checks reported"
    [ "$ENFORCE_CI" = 1 ] && deny "merge-guard: PR #$pr reports no checks. Refusing to merge unverified code."
    exit 0 ;;
esac

# In enforce-ci mode the human is the gate — CI green is the whole contract.
if [ "$MODE" = enforce-ci ]; then
  audit ALLOW "CI green (enforce-ci; gate review not evaluated)"
  exit 0
fi

# --- Precondition 2: the newest 🤖 gate review reads PASS --------------------
verdict_line=$(gh pr view "$pr" --json reviews 2>/dev/null | jq -r '
  [ .reviews[]? | select(.body != null and (.body | contains("🤖"))) ]
  | sort_by(.submittedAt) | last | .body // ""
' 2>/dev/null | head -1)

if [ -z "$verdict_line" ]; then
  audit BLOCK "no 🤖 gate review posted"
  [ "$ENFORCE_GATE" = 1 ] && deny "merge-guard: PR #$pr has no posted 🤖 gate review. spec-critic (docs PR) or the code gate (code PR) must post its verdict before merge."
  exit 0
fi

if printf '%s' "$verdict_line" | grep -q 'PASS'; then
  audit ALLOW "CI green + gate PASS"
  exit 0
fi

audit BLOCK "latest gate review is not PASS"
[ "$ENFORCE_GATE" = 1 ] && deny "merge-guard: the newest 🤖 gate review on PR #$pr is not PASS — it reads: ${verdict_line:0:120}. Resolve the findings and re-run the gate."
exit 0
