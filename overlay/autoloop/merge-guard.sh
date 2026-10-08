#!/usr/bin/env bash
# merge-guard.sh — PreToolUse guard for the kmp-forge autonomous build loop.
# version: 3
#
# Installed into a project's .claude/hooks/ by /kmp-forge-add-autoloop and wired in
# .claude/settings.json for the Bash, Write/Edit and mcp__* tools.
# Runbook: openspec/AUTOLOOP.md · theory: kmp-forge docs/autoloop.md.
#
# The loop's one irreversible action is landing code on `main`. /kmp-forge-next-increment
# states the preconditions as a model instruction; this hook enforces them as code,
# independently, for the main conversation AND every subagent (PreToolUse fires for both;
# a subagent's calls carry a non-empty `agent_id`).
#
# Guarded actions
#   merge   `gh pr merge` in any flag order (`gh pr --repo o/r merge 7`, `bash -c '…'`, …),
#           `gh api` writes to `…/pulls/<n>/merge`, and MCP tools whose name contains "merge".
#   push    `git push` that updates main/master (explicit refspec, `HEAD` while on main,
#           `--all`/`--mirror`, deletes, forces) — plus `gh api` writes to `…/merges` or
#           `git/refs/heads/main|master`, GraphQL merge/ref mutations, and MCP file writes to main.
#   tamper  a subagent writing this script, its mode file, or .claude/settings*.json.
#   promote applying the `ready` label to an issue — `gh issue create|edit` with `ready` among
#           its labels, `gh api` writes to an issue's labels that name it, GraphQL label
#           mutations (they carry label ids, not names, so they cannot be checked), and MCP
#           issue/label tools whose input names it. `ready` puts an issue in the loop's work queue;
#           only a human may apply it, so Claude never approves its own work.
#
# A merge passes only when
#   1. every check on the PR's head commit concluded successfully,
#   2. [enforce] the newest review posted by the loop's own GitHub account whose body starts
#      `### 🤖 ` has a first line whose last ` — ` field is the verdict `PASS`, AND it was
#      posted on the PR's current head commit (a PASS predating new commits is stale), and
#   3. [enforce] the caller is the main conversation — subagents never merge.
# Applying `ready` never passes [enforce], from any caller.
# A push to main passes [enforce] only from the main conversation, never forced or deleting,
# and only when every file it changes is loop bookkeeping: openspec/** (the queue-empty archive,
# runbook steering edits), a legacy pre-issue-queue backlog file, or the mode file.
#
# Modes — read fresh on every invocation from .claude/hooks/merge-guard.mode:
#   log         observe only; never denies. Appends a verdict line to merge-guard.log that
#               evaluates every precondition as `enforce` would — the trust-ramp signal.
#   enforce-ci  deny merges unless CI is green; deny --admin, force-pushes/deletes of main,
#               API ref writes, and subagent tampering. Gate reviews, the caller, push contents
#               and `ready` labels are not evaluated — for supervised projects where the human
#               is the gate.
#   enforce     everything. The loop's target mode.
#   off         no-op.
#   (unknown)   treated as `log`, with a warning line in the audit log.
#
# Fail-closed: every GitHub call is time-boxed (MERGE_GUARD_GH_TIMEOUT, default 15s) so the
# hook always finishes inside its settings.json timeout — Claude Code lets a tool call through
# when a hook times out or exits non-zero (other than 2). In the enforce modes any error while
# evaluating a guarded call (gh offline, unresolvable PR, internal failure) denies it.
#
# Exit 0 always. A deny is JSON on stdout, per the PreToolUse contract. Written for bash 3.2
# (macOS /bin/bash) — no ${x,,}, no empty-array expansion under set -u.

set -uo pipefail
export GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
HOOK_DIR="$PROJECT_DIR/.claude/hooks"
MODE_FILE="$HOOK_DIR/merge-guard.mode"
LOG_FILE="$HOOK_DIR/merge-guard.log"
GH_TIMEOUT="${MERGE_GUARD_GH_TIMEOUT:-15}"

MODE=log
BAD_MODE=""
[ -r "$MODE_FILE" ] && MODE=$(tr -d '[:space:]' < "$MODE_FILE")
case "$MODE" in
  off) exit 0 ;;
  log|enforce-ci|enforce) ;;
  *) BAD_MODE="$MODE"; MODE=log ;;
esac
ENFORCING=0
[ "$MODE" != log ] && ENFORCING=1

input=$(cat)

# PreToolUse deny, built without jq so it also works when jq is the thing that is missing.
deny_json() {
  local r=$1
  r=${r//\\/\\\\}; r=${r//\"/\\\"}
  r=$(printf '%s' "$r" | tr '\n\t\r' '   ')
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$r"
}

# Does this payload look like something the guard cares about? Used only on the error paths,
# where we can no longer parse it properly.
looks_guarded() {
  case "$input" in
    *merge*|*push*|*git/refs*|*.claude/settings*|*ready*) return 0 ;;
  esac
  return 1
}

if ! command -v jq >/dev/null 2>&1; then
  if [ "$ENFORCING" = 1 ] && looks_guarded; then
    deny_json "merge-guard: jq is not installed, so this call cannot be checked. Install jq (brew install jq)."
  fi
  exit 0
fi

# One jq pass. The separator is U+001F, not a tab: tab is IFS whitespace, so `read` would
# collapse an empty agent_id and shift every field after it.
IFS=$'\x1f' read -r tool agent_id agent cwd < <(jq -r '[
    (.tool_name // ""), (.agent_id // ""),
    (if (.agent_id // "") != "" then (.agent_type // "subagent") else "main" end),
    (.cwd // "") ] | map(tostring | gsub("[\u001f\n]"; " ")) | join("\u001f")' <<<"$input" 2>/dev/null)
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PROJECT_DIR"
is_sub=0
[ -n "$agent_id" ] && is_sub=1

SUMMARY=""
pr=""

# Record every decision, whether or not we act on it. This log is what tells you whether
# the guard agrees with the loop before you flip it to `enforce`.
# Columns: time, verdict, mode, caller, pr, detail, command  (cut -f2,5,6 → verdict/pr/detail)
audit() {
  mkdir -p "$HOOK_DIR" 2>/dev/null
  printf '%s\t%s\tmode=%s\tcaller=%s\tpr=%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$MODE" "$agent" "${pr:--}" "$2" "${SUMMARY:0:300}" \
    >> "$LOG_FILE" 2>/dev/null || true
}

# should_deny <scope>: `ci` rules apply in enforce-ci and enforce; `gate` rules only in enforce.
should_deny() {
  case "$1" in
    ci)   [ "$ENFORCING" = 1 ] ;;
    gate) [ "$MODE" = enforce ] ;;
    *)    return 1 ;;
  esac
}

# block <scope> <audit detail> <deny reason>. Returns 1 when it denied (caller must stop),
# 0 when it only logged (log mode / rule not active in this mode).
block() {
  audit BLOCK "$2"
  if should_deny "$1"; then
    deny_json "$3"
    return 1
  fi
  return 0
}

# Time-box a command (perl ships with macOS and virtually every Linux; without it, run as-is).
# The command runs in its own process group with a watchdog that kills the group after $1
# seconds, and its stdout goes to a temp file rather than the caller's $(…) pipe — a
# grandchild that outlives the kill (gh spawns git) can then never hold the hook open.
tmo() {
  local s=$1 f rc
  shift
  command -v perl >/dev/null 2>&1 || { "$@"; return; }
  f=$(mktemp "${TMPDIR:-/tmp}/merge-guard.XXXXXX" 2>/dev/null) || { "$@"; return; }
  perl -e '
    my $t = shift @ARGV;
    my $pid = fork; exit 127 unless defined $pid;
    if (!$pid) { setpgrp(0, 0); exec { $ARGV[0] } @ARGV or exit 127 }
    my $w = fork;
    if (defined $w && !$w) {
      close STDOUT; close STDERR; sleep $t;
      kill "TERM", -$pid; kill "TERM", $pid; select(undef, undef, undef, 0.5);
      kill "KILL", -$pid; kill "KILL", $pid; exit 0;
    }
    waitpid($pid, 0); my $st = $?;
    if (defined $w && $w) { kill "KILL", $w; waitpid($w, 0) }
    exit(($st & 127) ? 124 : ($st >> 8))' "$s" "$@" > "$f"
  rc=$?
  cat "$f"
  rm -f "$f"
  return "$rc"
}

# --- Command parsing ----------------------------------------------------------
# Split a shell string into simple-command segments at ; && || | & ( ) newlines, `…` and $(…),
# ignoring separators inside single quotes. Inside double quotes only command substitution
# splits (it still executes there).
split_segments() {
  printf '%s\n' "$1" | awk '
    { s = s $0 "\n" }
    END {
      n = length(s); q = ""; seg = ""
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1); c2 = substr(s, i, 2)
        if (q == "\047") { seg = seg c; if (c == "\047") q = ""; continue }
        if (q == "\"") {
          if (c == "\\") { seg = seg c substr(s, i + 1, 1); i++; continue }
          if (c == "\"") { q = ""; seg = seg c; continue }
          if (c2 == "$(" || c == "`") { print seg; seg = ""; if (c2 == "$(") i++; continue }
          seg = seg c; continue
        }
        if (c == "\047" || c == "\"") { q = c; seg = seg c; continue }
        if (c == "\\") { seg = seg c substr(s, i + 1, 1); i++; continue }
        if (c2 == "&&" || c2 == "||" || c2 == "$(") { print seg; seg = ""; i++; continue }
        if (c == ";" || c == "|" || c == "&" || c == "\n" || c == "(" || c == ")" || c == "`") { print seg; seg = ""; continue }
        seg = seg c
      }
      print seg
    }'
}

# One token per line. Quote-aware via xargs; naive whitespace split if quoting is unbalanced
# (e.g. a segment cut from inside a quoted string).
tokenize() {
  local out
  if out=$(printf '%s' "$1" | xargs printf '%s\n' 2>/dev/null); then
    printf '%s\n' "$out"
  else
    printf '%s' "$1" | tr -d "\"'" | tr -s ' \t' '\n\n'
  fi
}

ACTIONS=()
add_action() { ACTIONS[${#ACTIONS[@]}]="$1"; }

classify_cmd() { # <shell string> <depth>
  local depth=$2 seg
  [ "$depth" -gt 3 ] && return 0
  while IFS= read -r seg; do
    case "$seg" in *[![:space:]]*) classify_seg "$seg" "$depth" ;; esac
  done < <(split_segments "$1")
}

classify_seg() { # <segment> <depth>
  local seg=$1 depth=$2 line i=0 n from_xargs=0
  local -a t
  t=()
  while IFS= read -r line; do
    [ -n "$line" ] && t[${#t[@]}]="$line"
  done < <(tokenize "$seg")
  n=${#t[@]}
  # Skip env assignments, keywords and transparent wrappers (sudo, env, nohup, xargs, …).
  while [ "$i" -lt "$n" ]; do
    case "${t[$i]}" in
      [A-Za-z_]*=*) i=$((i + 1)) ;;
      command|builtin|exec|nohup|time|sudo|env|nice|caffeinate|if|then|else|elif|while|until|do|'!'|'{') i=$((i + 1)) ;;
      xargs)
        from_xargs=1; i=$((i + 1))
        while [ "$i" -lt "$n" ]; do case "${t[$i]}" in -*) i=$((i + 1)) ;; *) break ;; esac; done ;;
      -*) if [ "$i" -gt 0 ]; then i=$((i + 1)); else break; fi ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 0
  local cmd0=${t[$i]##*/} j
  case "$cmd0" in
    bash|sh|zsh|dash|ksh)
      for ((j = i + 1; j < n; j++)); do
        if [[ "${t[$j]}" =~ ^-[a-zA-Z]*c[a-zA-Z]*$ ]] && [ $((j + 1)) -lt "$n" ]; then
          classify_cmd "${t[$((j + 1))]}" $((depth + 1))
          return 0
        fi
      done ;;
    eval)
      classify_cmd "${t[*]:$((i + 1))}" $((depth + 1)) ;;
    gh)
      classify_gh "$seg" "$from_xargs" ${t[@]+"${t[@]:$((i + 1))}"} ;;
    git)
      classify_git ${t[@]+"${t[@]:$((i + 1))}"} ;;
  esac
  return 0
}

# owner/repo from a REST endpoint like repos/o/r/pulls/1/merge ({owner}/{repo} → gh resolves it).
api_repo() {
  if [[ "$1" =~ ^repos/([^/{}]+)/([^/{}]+)/ ]]; then
    printf '%s/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    printf '%s' "$2"
  fi
}

# `ready` as a whole label name inside a ,-joined list (case-insensitive; GitHub labels are).
has_ready_label() {
  case ",$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' ')," in
    *,ready,*) return 0 ;;
  esac
  return 1
}

# Does free text (a gh api call, an MCP tool input) name the `ready` label as a whole word?
names_ready() {
  printf '%s' "$1" | grep -qiE '(^|[^a-z0-9_-])ready([^a-z0-9_-]|$)'
}

classify_gh() { # <raw segment> <from_xargs> <args after gh>…
  local raw=$1 from_xargs=$2 a repo="" method="" fields=0 admin=0 disable_auto=0 labels=","
  shift 2
  local -a w
  w=()
  while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
      -R|--repo) repo=${1:-}; [ $# -gt 0 ] && shift ;;
      --repo=*) repo=${a#--repo=} ;;
      -X|--method) method=${1:-}; [ $# -gt 0 ] && shift ;;
      --method=*) method=${a#--method=} ;;
      -X?*) method=${a#-X} ;;
      -f|-F|--field|--raw-field|--input) fields=1; [ $# -gt 0 ] && shift ;;
      --field=*|--raw-field=*|--input=*) fields=1 ;;
      -t|--subject|-b|--body|--body-file|-A|--author-email|--match-head-commit|-H|--header|-q|--jq|--template|--hostname|-p|--preview|--cache)
        [ $# -gt 0 ] && shift ;;
      -l|--label|--add-label) labels="$labels${1:-},"; [ $# -gt 0 ] && shift ;;
      --label=*|--add-label=*) labels="$labels${a#*=}," ;;
      --admin) admin=1 ;;
      --disable-auto) disable_auto=1 ;;
      -*) ;;
      *) w[${#w[@]}]="$a" ;;
    esac
  done
  case "${w[0]:-}" in
    pr)
      [ "${w[1]:-}" = merge ] || return 0
      [ "$disable_auto" = 1 ] && return 0   # turning auto-merge OFF is always safe
      local target="${w[2]:-}"
      [ "$from_xargs" = 1 ] && target="?"
      add_action "merge|$target|$repo|admin=$admin" ;;
    issue)
      case "${w[1]:-}" in create|new|edit) ;; *) return 0 ;; esac
      if has_ready_label "$labels"; then add_action "promote|gh issue ${w[1]} --label ready"; fi ;;
    api)
      local ep=${w[1]:-} m
      ep=${ep#/}
      m=$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')
      if [ -z "$m" ]; then
        if [ "$fields" = 1 ]; then m=POST; else m=GET; fi
      fi
      if [ "$ep" = graphql ]; then
        case "$raw" in
          *mergePullRequest*|*enablePullRequestAutoMerge*|*mergeBranch*|*updateRef*|*deleteRef*)
            add_action "refwrite|gh api graphql merge/ref mutation" ;;
          *addLabelsToLabelable*|*labelIds*)
            add_action "promote|gh api graphql label mutation (label ids cannot be checked)" ;;
        esac
      elif [ "$m" != GET ]; then
        if [[ "$ep" =~ (^|/)pulls/([0-9]+)/merge$ ]]; then
          add_action "merge|${BASH_REMATCH[2]}|$(api_repo "$ep" "$repo")|admin=0"
        elif [[ "$ep" =~ (^|/)merges$ ]] || [[ "$ep" =~ (^|/)git/refs/heads/(main|master)$ ]]; then
          add_action "refwrite|gh api $m $ep"
        elif [[ "$ep" =~ (^|/)issues(/[0-9]+(/labels)?)?$ ]] && names_ready "$raw"; then
          add_action "promote|gh api $m $ep"
        fi
      fi ;;
  esac
  return 0
}

classify_git() { # <args after git>…
  local dir="$cwd" a sub="" force=0 destroy=0 all=0
  while [ $# -gt 0 ]; do
    a=$1
    case "$a" in
      -C) dir=$(cd "$cwd" 2>/dev/null && cd "${2:-.}" 2>/dev/null && pwd) || dir="${2:-$cwd}"
          shift; [ $# -gt 0 ] && shift ;;
      -c|--git-dir|--work-tree|--namespace) shift; [ $# -gt 0 ] && shift ;;
      -*) shift ;;
      *) sub=$a; shift; break ;;
    esac
  done
  [ "$sub" = push ] || return 0
  local -a pos
  pos=()
  while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
      -f|--force|--force-with-lease|--force-with-lease=*|--force-if-includes) force=1 ;;
      -d|--delete) destroy=1 ;;
      --mirror|--all|--prune) all=1 ;;
      -o|--push-option|--repo|--receive-pack|--exec) [ $# -gt 0 ] && shift ;;
      -*) ;;
      *) pos[${#pos[@]}]="$a" ;;
    esac
  done
  local remote="${pos[0]:-origin}" cur r src dst k hits=""
  cur=$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null)
  if [ "$all" = 1 ]; then
    hits="*all*:main"
  elif [ ${#pos[@]} -le 1 ]; then
    case "$cur" in main|master) hits="HEAD:$cur" ;; esac
  else
    for ((k = 1; k < ${#pos[@]}; k++)); do
      r=${pos[$k]}
      case "$r" in +*) force=1; r=${r#+} ;; esac
      case "$r" in
        *:*) src=${r%%:*}; dst=${r#*:} ;;
        *)   src=$r; dst=$r ;;
      esac
      [ -z "$src" ] && destroy=1
      [ "$dst" = HEAD ] && dst=$cur
      dst=${dst#refs/heads/}
      case "$dst" in
        main|master) hits="$hits ${src:-<delete>}:$dst" ;;
      esac
    done
  fi
  [ -n "$hits" ] || return 0
  add_action "push|$dir|$remote|$force|$destroy|$hits"
}

# --- Evaluation ---------------------------------------------------------------
eval_merge() { # <target> <repo> <flags>
  local target=$1 repo=$2 flags=$3 view ci login gate verdict head
  local -a rflag
  rflag=()
  pr=""
  if [ "$target" = "?" ]; then
    block ci "PR number piped in via xargs" \
      "merge-guard: cannot verify a merge whose PR number is piped in. Run gh pr merge <number> directly."
    return
  fi
  if [[ "$target" =~ ^[0-9]+$ ]]; then
    pr=$target
  elif [[ "$target" =~ github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
    pr=${BASH_REMATCH[3]}; repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  fi
  [ -n "$repo" ] && rflag=(--repo "$repo")
  if [ -z "$pr" ]; then
    # Bare `gh pr merge` or a branch name — resolve it the way gh will.
    pr=$(cd "$cwd" 2>/dev/null && tmo "$GH_TIMEOUT" gh pr view ${target:+"$target"} ${rflag[@]+"${rflag[@]}"} --json number --jq .number 2>/dev/null)
  fi
  if [ -z "$pr" ]; then
    block ci "could not determine PR number" \
      "merge-guard: could not determine which PR this merges. Pass the PR number explicitly."
    return
  fi
  if [ "$is_sub" = 1 ]; then
    block gate "subagent caller ($agent)" \
      "merge-guard: subagents never merge — merge authority belongs to the /kmp-forge-next-increment orchestrator." || return 1
  fi
  case "$flags" in
    *admin=1*)
      block ci "--admin bypasses branch protection" \
        "merge-guard: --admin force-merges past branch protection. Never force-merge."
      return ;;
  esac

  # --- Precondition 1: all checks on the head commit concluded successfully ---------
  view=$(cd "$cwd" 2>/dev/null && tmo "$GH_TIMEOUT" gh pr view "$pr" ${rflag[@]+"${rflag[@]}"} \
           --json number,state,headRefOid,statusCheckRollup,reviews 2>/dev/null)
  if [ -z "$view" ]; then
    block ci "gh pr view failed or timed out (offline? unauthenticated?)" \
      "merge-guard: could not read PR #$pr from GitHub. Failing closed."
    return
  fi
  ci=$(jq -r '
    [ .statusCheckRollup[]?
      | { s: (.status // ""), c: (.conclusion // ""), st: (.state // "") } ] as $n
    | if   ($n | length) == 0 then "NONE"
      elif ($n | any(.c == "FAILURE" or .c == "TIMED_OUT" or .c == "CANCELLED"
                     or .c == "ACTION_REQUIRED" or .c == "STARTUP_FAILURE" or .c == "STALE"
                     or .st == "FAILURE" or .st == "ERROR")) then "RED"
      elif ($n | any(.st == "PENDING" or .st == "EXPECTED" or (.s != "" and .s != "COMPLETED"))) then "PENDING"
      else "GREEN" end' <<<"$view" 2>/dev/null)
  case "$ci" in
    GREEN) ;;
    RED)
      block ci "CI red" \
        "merge-guard: PR #$pr has failing checks. Fix CI before merging (max 2 fix cycles), or escalate."
      return ;;
    PENDING)
      block ci "CI pending" \
        "merge-guard: PR #$pr still has checks in flight. Wait for green before merging."
      return ;;
    *)
      block ci "no checks reported" \
        "merge-guard: PR #$pr reports no checks. Refusing to merge unverified code."
      return ;;
  esac

  # In enforce-ci mode the human is the gate — CI green is the whole contract.
  if [ "$MODE" = enforce-ci ]; then
    audit ALLOW "CI green (enforce-ci; gate review not evaluated)"
    return 0
  fi

  # --- Precondition 2: the loop account's newest 🤖 review is PASS on the head commit ---
  login=$(cd "$cwd" 2>/dev/null && tmo "$GH_TIMEOUT" gh api user --jq .login 2>/dev/null)
  if [ -z "$login" ]; then
    block gate "could not resolve the authenticated GitHub login" \
      "merge-guard: could not resolve which GitHub account posts the gate reviews. Failing closed."
    return
  fi
  gate=$(jq -r --arg me "$login" '
    .headRefOid as $head
    | [ .reviews[]?
        | select((.author.login // "") == $me and ((.body // "") | startswith("### 🤖 "))) ]
    | sort_by(.submittedAt) | last
    | if . == null then "NONE\t"
      else ((.body | split("\n")[0] | rtrimstr("\r")) as $h
            | if (.commit.oid // "") != $head then "STALE\t" + $h
              elif (($h | split(" — ") | last) | test("^PASS([: ]|$)")) then "PASS\t" + $h
              else "NOTPASS\t" + $h end)
      end' <<<"$view" 2>/dev/null)
  verdict=${gate%%$'\t'*}
  head=${gate#*$'\t'}
  case "$verdict" in
    PASS)
      audit ALLOW "CI green + gate PASS on head"
      return 0 ;;
    NONE)
      block gate "no 🤖 gate review from $login" \
        "merge-guard: PR #$pr has no '### 🤖' gate review posted by $login. The spec gate (docs PR) or the code gate (code PR) must post its verdict before merge."
      return ;;
    STALE)
      block gate "newest gate review predates the PR head" \
        "merge-guard: the newest gate review on PR #$pr was posted on an older commit — commits were pushed after it. Re-run the gate on the current head."
      return ;;
    NOTPASS)
      block gate "newest gate review is not PASS" \
        "merge-guard: the newest gate review on PR #$pr is not PASS — it reads: ${head:0:120}. Resolve the findings and re-run the gate."
      return ;;
    *)
      block gate "could not evaluate gate reviews" \
        "merge-guard: could not evaluate the gate reviews on PR #$pr. Failing closed."
      return ;;
  esac
}

# Paths the loop may push straight to main: openspec/**, the mode file, and — for projects that
# predate the GitHub-issue queue — the backlog file their runbook still configures.
bookkeeping_backlog() {
  local f="$PROJECT_DIR/openspec/AUTOLOOP.md" b=""
  [ -r "$f" ] && b=$(sed -n 's/^- backlog:[[:space:]]*//p' "$f" | head -1 | tr -d '`' | tr -d '[:space:]')
  printf '%s' "${b:-openspec/backlog.md}"
}

eval_push() { # <dir> <remote> <force> <destroy> <hits>
  local dir=$1 remote=$2 force=$3 destroy=$4 hits=$5 h src dst files bad backlog
  pr="-"
  if [ "$force" = 1 ] || [ "$destroy" = 1 ]; then
    block ci "force-push/delete of main" \
      "merge-guard: refusing to force-push to or delete main/master."
    return
  fi
  if [ "$is_sub" = 1 ]; then
    block gate "subagent push to main" \
      "merge-guard: subagents may not push to main — land changes through a PR that the orchestrator merges."
    return
  fi
  backlog=$(bookkeeping_backlog)
  for h in $hits; do
    src=${h%%:*}; dst=${h#*:}
    if [ "$src" = "*all*" ]; then
      block gate "push --all/--mirror/--prune" \
        "merge-guard: --all/--mirror/--prune can rewrite main. Push the specific branch instead."
      return
    fi
    if ! git -C "$dir" rev-parse -q --verify "refs/remotes/$remote/$dst" >/dev/null 2>&1; then
      block gate "no remote-tracking ref $remote/$dst to diff against" \
        "merge-guard: cannot tell what this push changes on $dst (no refs/remotes/$remote/$dst). Run git fetch $remote, or land it through a PR."
      return
    fi
    if ! files=$(git -C "$dir" diff --name-only "refs/remotes/$remote/$dst...$src" 2>/dev/null); then
      block gate "git diff failed for $remote/$dst...$src" \
        "merge-guard: cannot tell what this push changes on $dst. Failing closed."
      return
    fi
    bad=$(printf '%s\n' "$files" | awk -v b="$backlog" \
      'NF && index($0, "openspec/") != 1 && $0 != b && $0 != ".claude/hooks/merge-guard.mode"' | head -3 | tr '\n' ' ')
    if [ -n "$bad" ]; then
      block gate "push to $dst touches non-bookkeeping files: $bad" \
        "merge-guard: only loop bookkeeping (openspec/**, $backlog, the guard mode file) may be pushed straight to $dst — $bad must go through a PR."
      return
    fi
  done
  audit ALLOW "bookkeeping-only push to main"
  return 0
}

evaluate() {
  [ -n "$BAD_MODE" ] && audit WARN "unknown mode '$BAD_MODE' in merge-guard.mode — treating as log"
  local act kind f1 f2 f3 f4 f5
  for act in ${ACTIONS[@]+"${ACTIONS[@]}"}; do
    IFS='|' read -r kind f1 f2 f3 f4 f5 <<<"$act"
    case "$kind" in
      merge)    eval_merge "$f1" "$f2" "$f3" || return 1 ;;
      push)     eval_push "$f1" "$f2" "$f3" "$f4" "$f5" || return 1 ;;
      refwrite) pr="-"
                block ci "direct ref write: $f1" \
                  "merge-guard: writing main through the API ($f1) bypasses every gate. Merge through gh pr merge <number>." || return 1 ;;
      promote)  pr="-"
                block gate "applying the ready label ($f1)" \
                  "merge-guard: only a human applies the 'ready' label — it puts an issue in the build loop's work queue. Create or edit the issue without it and tell the human which issues to promote." || return 1 ;;
      tamper)   pr="-"
                block ci "subagent writing guard files ($f1)" \
                  "merge-guard: subagents may not modify the merge guard, its mode file, or .claude/settings*.json." || return 1 ;;
    esac
  done
  return 0
}

run_all() {
  case "$tool" in
    Bash)
      local cmd
      cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
      [ -n "$cmd" ] || return 0
      SUMMARY=$(printf '%s' "$cmd" | tr '\n\t' '  ' | tr -s ' ')
      case "$cmd" in
        *gh*|*git*|*merge-guard*|*.claude/settings*) ;;
        *) return 0 ;;
      esac
      classify_cmd "$cmd" 0
      if [ "$is_sub" = 1 ] && [[ "$cmd" =~ merge-guard\.(mode|sh)|\.claude/settings ]] \
         && [[ "$cmd" =~ (^|[^0-9\&\>])\>{1,2}[[:space:]]*[^\&[:space:]]|tee[[:space:]]|sed[[:space:]]+-i|perl[[:space:]]+-[a-zA-Z]*i|(^|[^a-zA-Z_])(rm|mv|cp|ln|chmod|truncate|install|dd)[[:space:]] ]]; then
        add_action "tamper|bash"
      fi ;;
    Write|Edit|MultiEdit|NotebookEdit)
      local path
      path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")
      SUMMARY="$tool $path"
      if [ "$is_sub" = 1 ]; then
        case "$path" in
          *.claude/hooks/merge-guard.sh|*.claude/hooks/merge-guard.mode|*.claude/settings.json|*.claude/settings.local.json)
            add_action "tamper|$tool" ;;
        esac
      fi ;;
    mcp__*)
      local lname num owner repo branch
      lname=$(printf '%s' "$tool" | tr '[:upper:]' '[:lower:]')
      SUMMARY="$tool $(jq -c '.tool_input' <<<"$input" 2>/dev/null | cut -c1-200)"
      case "$lname" in
        *merge*)
          num=$(jq -r '.tool_input | (.pullNumber // .pull_number // .number // .pr // "") | tostring' <<<"$input")
          owner=$(jq -r '.tool_input.owner // ""' <<<"$input")
          repo=$(jq -r '.tool_input.repo // ""' <<<"$input")
          [ -n "$owner" ] && [ -n "$repo" ] && repo="$owner/$repo" || repo=""
          case "$num" in ''|*[!0-9]*) num="" ;; esac
          add_action "merge|${num:-?}|$repo|admin=0" ;;
        *push_files*|*create_or_update_file*|*delete_file*|*update_ref*|*create_ref*)
          branch=$(jq -r '.tool_input.branch // .tool_input.ref // ""' <<<"$input")
          case "${branch#refs/heads/}" in
            main|master) add_action "refwrite|$tool on $branch" ;;
          esac ;;
        *label*|*issue*)
          # Only label-named fields (`labels`, `add_labels`, …): a title or body saying "ready" is fine.
          if jq -e '[.tool_input | objects | to_entries[] | select(.key | test("label"; "i")) | .value
                     | .. | strings | ascii_downcase | gsub("^\\s+|\\s+$"; "")] | any(. == "ready")' \
               <<<"$input" >/dev/null 2>&1; then
            add_action "promote|$tool"
          fi ;;
      esac ;;
    *) return 0 ;;
  esac
  [ ${#ACTIONS[@]} -gt 0 ] || return 0
  evaluate
}

out=$(run_all)
rc=$?
if [ -n "$out" ]; then
  printf '%s\n' "$out"
elif [ "$rc" -ne 0 ] && looks_guarded; then
  audit ERROR "internal error (rc=$rc)"
  [ "$ENFORCING" = 1 ] && deny_json "merge-guard: internal error while checking this call (rc=$rc). Failing closed — see .claude/hooks/merge-guard.log."
fi
exit 0
