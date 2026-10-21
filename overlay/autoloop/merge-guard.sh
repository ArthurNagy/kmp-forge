#!/usr/bin/env bash
# merge-guard.sh — PreToolUse guard for the kmp-forge autonomous build loop.
# version: 5
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
#   merge   `gh pr merge` in any flag order or wrapper (`gh pr --repo o/r merge 7`, `bash -c '…'`,
#           `timeout 60 …`, `$'gh' …`), `gh api` writes to `…/pulls/<n>/merge`, and MCP tools whose
#           name contains "merge". The PR and the repository must be literal: a target built by
#           `$(…)` or a variable, xargs/find/parallel input, a non-literal GH_REPO or an earlier
#           `cd` the guard cannot follow is denied (it would otherwise check the wrong PR).
#   push    `git push` that updates main/master: explicit refspecs, `HEAD` while on main, what a
#           bare push sends per push.default / remote.<r>.push / remote.<r>.mirror (also set via
#           `git -c` and git aliases), `--all`/`--mirror`/`--prune`, deletes and forces (bundled
#           `-fu`, abbreviated `--force-w`, `+refspec`) — plus `gh api` writes to `…/merges`,
#           `git/refs/heads/main|master`, `contents/…`, branch protection and rulesets, GraphQL
#           merge/ref mutations, curl/wget/httpie writes to the GitHub API, and MCP writes to main.
#   tamper  writing this script, its mode file, .claude/settings*.json or the loop's runbook
#           (openspec/AUTOLOOP.md: its ready-approvers decide whose issues are trusted, and the loop
#           commits an uncommitted edit of it as the human's steering) — from ANY caller in the
#           enforce modes. Write/Edit paths are normalised (`..`, `//`, `./`, symlinks, letter
#           case); Bash writers are checked (redirects, tee, cp/mv/ln/rm/chmod/…, sed -i, git
#           pathspecs such as `git checkout -- .` or `git restore openspec`, the paths in a patch
#           `git apply`/`git am` would apply); a wholesale revert (`git stash`, `reset --hard`,
#           `switch -f`) is denied while one of those files has an uncommitted (the human's) edit;
#           and a Bash command that mentions them in a form the guard cannot resolve (a variable,
#           an interpreter, a patch it cannot read) is denied.
#   promote applying the `ready` label to an issue — `gh issue create|edit` with `ready` among
#           its labels, renaming a label to `ready`, `gh api` writes to an issue's labels that name
#           it (or whose fields cannot be read), GraphQL label mutations (they carry ids, not
#           names), and MCP issue/label tools whose input names it. `ready` puts an issue in the
#           loop's work queue; only a human may apply it, so Claude never approves its own work.
#   forge   a subagent posting a review or comment whose body starts `### 🤖` (the gate header the
#           merge check trusts), or posting a review whose body the guard cannot read.
#   token   `gh auth token`, `gh auth status --show-token`, `git credential fill`, `gh alias
#           set|import` — ways to act on GitHub out of the guard's sight.
#   opaque  [enforce modes] a Bash command that mentions a merge, push, ref, the GitHub API or
#           token, a guard file, or the `ready` label, but does not parse into forms the guard can
#           check — a non-literal command name (`G=gh; $G …`), code piped into a shell (`… | sh`),
#           inline interpreter code (`python3 -c`), an unknown wrapper around gh/git
#           (`strace gh …`), an unterminated quote — and, with or without such text, a gh/git
#           subcommand or option built at run time. Run the gh/git command directly, literally.
#
# A merge passes only when
#   1. every check on the PR's head commit concluded successfully,
#   2. [enforce] the newest review posted by the loop's own GitHub account whose body starts
#      `### 🤖 ` has a first line whose last ` — ` field is the verdict `PASS`, AND it was
#      posted on the PR's current head commit (a PASS predating new commits is stale), and
#   3. [enforce] the caller is the main conversation — subagents never merge.
# Applying `ready` never passes [enforce], from any caller.
# A push to main passes [enforce] only from the main conversation, never forced or deleting,
# and only when every file it changes (renames counted as delete + add) is under openspec/** —
# the queue-empty archive and runbook steering edits. The mode file is not bookkeeping: only a
# human changes it, and commits it — a push to main that changes any guard file is denied in both
# enforce modes.
#
# Modes — read fresh on every invocation from .claude/hooks/merge-guard.mode:
#   log         observe only; never denies. Appends a verdict line to merge-guard.log that
#               evaluates every precondition as `enforce` would — the trust-ramp signal.
#   enforce-ci  deny merges unless CI is green; deny --admin, force-pushes/deletes of main, API
#               ref writes, token exposure, opaque commands and writes to the guard's files.
#               Gate reviews, the caller, push contents and `ready` labels are not evaluated —
#               for supervised projects where the human is the gate.
#   enforce     everything. The loop's target mode.
#   off         no-op.
#   (missing, empty or unknown) `enforce-ci` while this script sits in .claude/hooks/ — deleting
#               or garbling the mode file never turns the guard off — with a WARN audit line.
#
# Fail-closed: every GitHub call is time-boxed (MERGE_GUARD_GH_TIMEOUT, default 15s; all of them
# together within 75s) so the hook always finishes inside its settings.json timeout — Claude Code
# lets a tool call through when a hook times out or exits non-zero (other than 2). In the enforce
# modes any error while evaluating a guarded call (gh offline, unresolvable PR, non-JSON hook
# input, python3 missing, internal failure) denies it.
#
# Exit 0 always. A deny is JSON on stdout, per the PreToolUse contract. The launcher is bash 3.2
# (macOS /bin/bash); the parser and the checks are python3 (stdlib only, 3.8+), embedded below.

set -uo pipefail
export GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
HOOK_DIR="${PROJECT_DIR}/.claude/hooks"
MODE_FILE="${HOOK_DIR}/merge-guard.mode"

# The mode, as the fail-closed path at the bottom needs it (python3 re-reads it and logs a WARN).
MODE=""
[ -r "${MODE_FILE}" ] && MODE=$(tr -d '[:space:]' < "${MODE_FILE}" 2>/dev/null)
case "${MODE}" in
  off) exit 0 ;;
  log|enforce-ci|enforce) ;;
  *) if [ -f "${HOOK_DIR}/merge-guard.sh" ]; then MODE=enforce-ci; else MODE=log; fi ;;
esac

input=$(cat)

deny_json() {
  local r=$1
  r=${r//\\/\\\\}; r=${r//\"/\\\"}
  r=$(printf '%s' "${r}" | tr '\n\t\r' '   ')
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "${r}"
}

# Could this payload matter to the guard? Used only when python3 is missing or crashed.
looks_guarded() {
  case "${input}" in
    *merge*|*push*|*refs*|*.claude*|*settings*|*label*|*ready*|*token*|*credential*|*alias*|*github*) return 0 ;;
  esac
  return 1
}

IFS= read -r -d '' GUARD_PY <<'PY' || true
import fnmatch, json, os, re, sys, time

PROJECT_DIR = sys.argv[1]
HOOK_DIR = os.path.join(PROJECT_DIR, ".claude", "hooks")
MODE_FILE = os.path.join(HOOK_DIR, "merge-guard.mode")
LOG_FILE = os.path.join(HOOK_DIR, "merge-guard.log")
try:
    GH_TIMEOUT = max(1.0, float(os.environ.get("MERGE_GUARD_GH_TIMEOUT") or 15))
except ValueError:
    GH_TIMEOUT = 15.0
DEADLINE = time.time() + 75                  # settings.json gives the hook 90 s
ROBOT = "\U0001F916"
GATE_PREFIX = "### " + ROBOT
DASH = chr(0x2014)


def read_mode():
    try:
        with open(MODE_FILE, encoding="utf-8", errors="replace") as f:
            raw = "".join(f.read().split())
    except OSError:
        raw = None
    if raw in ("off", "log", "enforce-ci", "enforce"):
        return raw, ""
    mode = "enforce-ci" if os.path.isfile(os.path.join(HOOK_DIR, "merge-guard.sh")) else "log"
    what = "missing" if raw is None else ("empty" if raw == "" else "unknown mode '%s' in" % raw[:40])
    return mode, "%s merge-guard.mode %s treating as %s" % (what, DASH, mode)


MODE, MODE_NOTE = read_mode()
if MODE == "off":
    sys.exit(0)
ENFORCING = MODE != "log"
AGENT, IS_SUB, PR, SUMMARY, RAW_INPUT = "main", False, "-", "", ""


class Denied(Exception):
    pass


def clean(s):
    return re.sub(r"[\t\r\n]+", " ", str(s))


def audit(verdict, detail):
    """Columns: time, verdict, mode, caller, pr, detail, command (cut -f2,5,6 = verdict/pr/detail)."""
    try:
        os.makedirs(HOOK_DIR, exist_ok=True)
        line = "\t".join([time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), verdict, "mode=" + MODE,
                          "caller=" + AGENT, "pr=" + (PR or "-"), clean(detail),
                          re.sub(r" +", " ", clean(SUMMARY))[:300]])
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                             "permissionDecisionReason": clean(reason)}}, separators=(",", ":")))
    raise Denied()


def block(scope, detail, reason):
    """Audit a BLOCK, and deny when the rule is active: `ci` rules in enforce-ci and enforce,
    `gate` rules only in enforce. Returns (instead of raising) when it only logged."""
    audit("BLOCK", detail)
    if (scope == "ci" and ENFORCING) or (scope == "gate" and MODE == "enforce"):
        deny(reason)


def run(argv, cwd=None, env_extra=None, timeout=None, stdin_text=None):
    """Time-boxed command → (rc, stdout); rc 124 on timeout, 127 when it cannot start. Its own
    process group and a temp-file stdout, so a grandchild (gh spawns git) can't hold the hook."""
    import signal, subprocess, tempfile          # only calls that need gh/git pay for these
    t = min(timeout or GH_TIMEOUT, DEADLINE - time.time())
    if t <= 0:
        return 124, ""
    env = dict(os.environ)
    for k, v in (env_extra or {}).items():
        if v is None:
            env.pop(k, None)
        else:
            env[k] = v
    try:
        with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as inp:
            if stdin_text is not None:
                inp.write(stdin_text.encode("utf-8", "replace"))
                inp.seek(0)
            p = subprocess.Popen(argv, cwd=cwd or None, env=env, stdin=inp if stdin_text is not None else
                                 subprocess.DEVNULL, stdout=out, stderr=subprocess.DEVNULL, start_new_session=True)
            try:
                rc = p.wait(timeout=t)
            except subprocess.TimeoutExpired:
                for sig in (signal.SIGTERM, signal.SIGKILL):
                    try:
                        os.killpg(p.pid, sig)
                    except OSError:
                        pass
                    time.sleep(0.3)
                p.wait()
                return 124, ""
            out.seek(0)
            return rc, out.read().decode("utf-8", "replace")
    except (OSError, ValueError):
        return 127, ""


# --- Shell parsing ------------------------------------------------------------------------------
# A small bash/zsh lexer: '…', $'…' (decoded), "…", ${…}, $(…), `…`, $((…)), <(…), heredocs
# (a quoted body is data, an unquoted one expands), comments, subshells, case, [[ ]], (( )),
# functions and redirections. It yields every simple command — those inside substitutions too —
# with each word kept as parts, so the checks know which arguments are literal.

SPECIAL_RE = re.compile(r"[*?\[]|\{[^{}]*(,|\.\.)[^{}]*\}")
OPS = ["&&", "||", ";;&", ";;", ";&", "|&", "&>>", "&>", ">>", "<<<", "<<-", "<<", ">&", "<&", "<>",
       ">|", ";", "&", "|", "(", ")", "<", ">"]
REDIR_OPS = {"<", ">", ">>", ">|", "<>", "&>", "&>>", ">&", "<&", "<<", "<<-", "<<<"}
WRITE_REDIRS = {">", ">>", ">|", "<>", "&>", "&>>", ">&"}
SKIP_KEYWORDS = {"if", "then", "else", "elif", "fi", "do", "done", "while", "until", "{", "}", "!",
                 "coproc"}


class ParseError(Exception):
    pass


class Word(object):
    """parts: ("lit", text, quoted) | ("exp", raw, [programs inside]) | ("sub", raw, program)."""
    __slots__ = ("parts",)

    def __init__(self, text=None):
        self.parts = [] if text is None else [("lit", text, True)]

    def add_lit(self, s, quoted):
        if self.parts and self.parts[-1][0] == "lit" and self.parts[-1][2] == quoted:
            self.parts[-1] = ("lit", self.parts[-1][1] + s, quoted)
        else:
            self.parts.append(("lit", s, quoted))

    def literal(self, strict=True):
        """The word's value when nothing in it expands. strict also refuses an unquoted glob,
        brace, or a leading ~ / = (zsh) — words whose value depends on the file system."""
        out = []
        for k, p in enumerate(self.parts):
            if p[0] != "lit":
                return None
            if strict and not p[2] and (SPECIAL_RE.search(p[1]) or (k == 0 and p[1][:1] in ("~", "="))):
                return None
            out.append(p[1])
        return "".join(out)

    def text(self):
        return "".join(p[1] for p in self.parts)

    def dynamic(self):
        return any(p[0] != "lit" for p in self.parts)

    def has_sub(self):
        return any(p[0] == "sub" for p in self.parts)

    def tail(self):
        """The literal text after the last expansion — the part of a path the guard can know."""
        out = []
        for p in self.parts:
            out = out + [p[1]] if p[0] == "lit" else []
        return "".join(out)


class Cmd(object):
    __slots__ = ("words", "redirs", "piped", "data", "scope")

    def __init__(self, scope):
        self.words, self.redirs, self.piped, self.data, self.scope = [], [], False, False, scope

    def empty(self):
        return not self.words and not self.redirs


def ansi_c(body):
    """Decode the inside of $'…' (bytes from \\x/\\NNN escapes are UTF-8 decoded)."""
    simple = {"a": 7, "b": 8, "e": 27, "E": 27, "f": 12, "n": 10, "r": 13, "t": 9, "v": 11, "\\": 92,
              "'": 39, '"': 34, "?": 63}
    out, i, n = bytearray(), 0, len(body)
    while i < n:
        c = body[i]
        if c != "\\" or i + 1 >= n:
            out += c.encode("utf-8", "surrogatepass")
            i += 1
            continue
        e = body[i + 1]
        i += 2
        if e in simple:
            out.append(simple[e])
        elif e == "x" and re.match(r"[0-9a-fA-F]", body[i:i + 1]):
            m = re.match(r"[0-9a-fA-F]{1,2}", body[i:])
            out.append(int(m.group(), 16))
            i += len(m.group())
        elif e in "uU" and re.match(r"[0-9a-fA-F]", body[i:i + 1]):
            m = re.match(r"[0-9a-fA-F]{1,%d}" % (4 if e == "u" else 8), body[i:])
            try:
                out += chr(int(m.group(), 16)).encode("utf-8", "surrogatepass")
            except (ValueError, OverflowError):
                pass
            i += len(m.group())
        elif e in "01234567":
            m = re.match(r"[0-7]{1,3}", body[i - 1:])
            out.append(int(m.group(), 8) & 0xFF)
            i += len(m.group()) - 1
        elif e == "c" and i < n:
            out.append(ord(body[i]) & 0x1F)
            i += 1
        else:
            out += ("\\" + e).encode("utf-8", "surrogatepass")
    return out.decode("utf-8", "replace")


class Lexer(object):
    def __init__(self, src, depth=0):
        if depth > 12:
            raise ParseError("nested too deeply")
        self.s, self.n, self.i, self.depth, self.pending = src, len(src), 0, depth, []

    def fail(self, why):
        raise ParseError(why)

    def at(self, t, k=0):
        return self.s.startswith(t, self.i + k)

    def blanks(self):
        while self.i < self.n:
            if self.s[self.i] in " \t\r":
                self.i += 1
            elif self.at("\\\n"):
                self.i += 2
            else:
                break

    def operator(self):
        if self.at("<(") or self.at(">("):
            return None
        for op in OPS:
            if self.at(op):
                self.i += len(op)
                return op
        return None

    def program(self, closer=None, scope=0):
        cmds, cur = [], Cmd(scope)
        case_stack, dbracket = [], False

        def finish(c):
            if not c.empty():
                cmds.append(c)
            return Cmd(scope)

        while True:
            self.blanks()
            if self.i >= self.n:
                if closer:
                    self.fail("unterminated substitution or subshell")
                break
            c = self.s[self.i]
            if c == "#":
                while self.i < self.n and self.s[self.i] != "\n":
                    self.i += 1
                continue
            if c == "\n":
                self.i += 1
                cur = finish(cur)
                self.heredoc_bodies()
                continue
            if dbracket and c in "&|<>()!":
                w = Word()
                w.add_lit(c, False)
                self.i += 1
                cur.words.append(w)
                continue
            if c == ")" and case_stack and case_stack[-1] == "pat":
                self.i += 1
                case_stack[-1] = "body"
                cur = Cmd(scope)
                continue
            if c == ")" and closer == ")":
                self.i += 1
                finish(cur)
                return cmds
            if self.at("((") and (cur.data or cur.empty()):       # (( … )) and for (( … ))
                self.i += 2
                w = Word()
                self.arith_into(w, self.i - 2)
                cur.words.append(w)
                cur.data = True
                continue
            op = self.operator()
            if op:
                if op in REDIR_OPS:
                    self.redirect(cur, op)
                elif op == "(":
                    if case_stack and case_stack[-1] == "pat":
                        continue
                    if len(cur.words) == 1 and not cur.redirs:    # name () { … }
                        self.blanks()
                        if self.at(")"):
                            self.i += 1
                            cur.data = True
                            cur = finish(cur)
                            continue
                    if not cur.empty():
                        self.fail("unexpected (")
                    cmds.extend(self.program(")", scope + 1))
                elif op == ")":
                    self.fail("unexpected )")
                elif op == "|" and case_stack and case_stack[-1] == "pat":
                    continue
                else:
                    cur = finish(cur)
                    cur.piped = op in ("|", "|&")
                    if op in (";;", ";&", ";;&") and case_stack:
                        case_stack[-1] = "pat"
                continue
            before = self.i
            w = self.word()
            if w is None:
                if self.i == before:
                    self.fail("unexpected character")
                continue
            lit = None if w.dynamic() else w.literal(strict=False)
            if dbracket:
                cur.words.append(w)
                dbracket = lit != "]]"
                continue
            if case_stack and case_stack[-1] in ("subject", "in", "pat"):
                st = case_stack[-1]
                if st == "pat" and lit == "esac":
                    case_stack.pop()
                    continue
                if st == "subject":
                    case_stack[-1] = "in"
                elif st == "in" and lit == "in":
                    case_stack[-1] = "pat"
                d = Cmd(scope)                       # the subject and the patterns are data, but
                d.data = True                        # their substitutions still run
                d.words.append(w)
                cmds.append(d)
                continue
            if cur.data and lit == "{":              # function f { … }
                cur = finish(cur)
                continue
            if not cur.words and not cur.data and lit is not None:
                if lit == "esac" and case_stack:
                    case_stack.pop()
                    continue
                if lit in SKIP_KEYWORDS:
                    continue
                if lit == "case":
                    case_stack.append("subject")
                    continue
                if lit in ("for", "select", "function"):
                    cur.data = True
                    continue
                dbracket = lit == "[["
            cur.words.append(w)
        for e in self.pending:                       # a heredoc whose body never started
            e["body"], e["text"] = Word(""), ""
        self.pending = []
        finish(cur)
        return cmds

    def redirect(self, cur, op):
        self.blanks()
        w = self.word()
        if w is None:
            self.fail("redirection without a target")
        if op in ("<<", "<<-"):
            e = {"op": op, "target": None, "delim": w.literal(strict=False) or w.text(),
                 "quoted": any(p[0] != "lit" or p[2] for p in w.parts), "strip": op == "<<-",
                 "body": None, "text": None}
            cur.redirs.append(e)
            self.pending.append(e)
        else:
            cur.redirs.append({"op": op, "target": w})

    def heredoc_bodies(self):
        while self.pending:
            e = self.pending.pop(0)
            lines = []
            while self.i < self.n:
                j = self.s.find("\n", self.i)
                end = j if j >= 0 else self.n
                line = self.s[self.i:end]
                self.i = end + 1 if j >= 0 else self.n
                if e["strip"]:
                    line = line.lstrip("\t")
                if line == e["delim"]:
                    break
                lines.append(line)
            e["text"] = "\n".join(lines) + ("\n" if lines else "")
            if e["quoted"]:
                e["body"] = Word(e["text"])
            else:
                e["body"] = Word()
                Lexer(e["text"], self.depth + 1).dq_into(e["body"], None)

    def word(self):
        w, start = Word(), self.i
        while self.i < self.n:
            c = self.s[self.i]
            if c in "<>" and self.at("(", 1) and self.i == start:           # <(…) >(…)
                self.i += 2
                prog = self.program(")", 1)
                w.parts.append(("sub", self.s[start:self.i], prog))
                continue
            if c in " \t\r\n;&|<>()":
                if c == "(" and w.parts and w.parts[-1][0] == "lit" and not w.parts[-1][2] \
                        and w.parts[-1][1][-1:] in ("@", "!", "+", "*", "?"):   # extglob @(…)
                    depth, j = 0, self.i
                    while j < self.n:
                        depth += {"(": 1, ")": -1}.get(self.s[j], 0)
                        if depth == 0:
                            break
                        j += 1
                    w.add_lit(self.s[self.i:j + 1], False)
                    self.i = j + 1
                    continue
                break
            if c == "\\":
                if self.at("\\\n"):
                    self.i += 2
                else:
                    w.add_lit(self.s[self.i + 1:self.i + 2] or "\\", True)
                    self.i += 2
                continue
            if c == "'":
                j = self.s.find("'", self.i + 1)
                if j < 0:
                    self.fail("unterminated '")
                w.add_lit(self.s[self.i + 1:j], True)
                self.i = j + 1
                continue
            if c == '"':
                self.i += 1
                n0 = len(w.parts)
                self.dq_into(w, '"')
                if len(w.parts) == n0:
                    w.add_lit("", True)
                continue
            if c == "$":
                self.dollar_into(w, False)
                continue
            if c == "`":
                self.backtick_into(w, False)
                continue
            w.add_lit(c, False)
            self.i += 1
        if self.i == start:
            return None
        lit = w.literal(strict=False)
        if lit is not None and lit.isdigit() and not w.parts[0][2] and self.s[self.i:self.i + 1] in ("<", ">"):
            return None                               # `2>file`: an fd number, not a word
        return w

    def dq_into(self, w, term):
        """Double-quoted text (term '"'), or a heredoc body / ${…} inside (term None)."""
        buf = []

        def flush():
            if buf:
                w.add_lit("".join(buf), True)
                del buf[:]

        while self.i < self.n:
            c = self.s[self.i]
            if term and c == term:
                self.i += 1
                flush()
                return
            if c == "\\" and self.s[self.i + 1:self.i + 2] in ("$", "`", '"', "\\", "\n") and self.i + 1 < self.n:
                if self.s[self.i + 1] != "\n":
                    buf.append(self.s[self.i + 1])
                self.i += 2
            elif c == "$":
                flush()
                self.dollar_into(w, True)
            elif c == "`":
                flush()
                self.backtick_into(w, True)
            else:
                buf.append(c)
                self.i += 1
        if term:
            self.fail('unterminated "')
        flush()

    def balanced(self, open_ch, close_ch, depth=1):
        start = self.i
        while self.i < self.n:
            c = self.s[self.i]
            if c == "\\":
                self.i += 2
                continue
            if c == "'" and open_ch == "{":
                j = self.s.find("'", self.i + 1)
                self.i = j + 1 if j >= 0 else self.n
                continue
            if c == '"':
                j = self.i + 1
                while j < self.n and self.s[j] != '"':
                    j += 2 if self.s[j] == "\\" else 1
                self.i = j + 1
                continue
            if c == "`":
                j = self.s.find("`", self.i + 1)
                self.i = j + 1 if j >= 0 else self.n
                continue
            depth += 1 if c == open_ch else (-1 if c == close_ch else 0)
            if depth == 0:
                inner = self.s[start:self.i]
                self.i += 1
                return inner
            self.i += 1
        self.fail("unterminated " + open_ch)

    def arith_into(self, w, start):
        inner = self.balanced("(", ")", 2)
        inner = inner[:-1] if inner.endswith(")") else inner
        # Over-approximate: bash may read `$((gh …))` as a subshell in a substitution.
        w.parts.append(("exp", self.s[start:self.i], [Lexer(inner, self.depth + 1).program()]))

    def dollar_into(self, w, in_dq):
        s, i = self.s, self.i
        nxt = s[i + 1:i + 2]
        if nxt == "'" and not in_dq:
            j = i + 2
            while j < self.n and s[j] != "'":
                j += 2 if s[j] == "\\" else 1
            if j >= self.n:
                self.fail("unterminated $'")
            w.add_lit(ansi_c(s[i + 2:j]), True)
            self.i = j + 1
        elif nxt == '"' and not in_dq:
            self.i += 2
            self.dq_into(w, '"')
        elif s.startswith("$((", i):
            self.i += 3
            self.arith_into(w, i)
        elif nxt == "(":
            self.i += 2
            prog = self.program(")", 1)
            w.parts.append(("sub", s[i:self.i], prog))
        elif nxt == "{":
            self.i += 2
            inner = Word()
            Lexer(self.balanced("{", "}"), self.depth + 1).dq_into(inner, None)
            progs = [p[2] for p in inner.parts if p[0] == "sub"] + \
                    [q for p in inner.parts if p[0] == "exp" for q in p[2]]
            w.parts.append(("exp", s[i:self.i], progs))
        elif nxt and (nxt.isalnum() or nxt == "_"):
            m = re.match(r"[0-9]|[A-Za-z_][A-Za-z0-9_]*", s[i + 1:])
            self.i = i + 1 + len(m.group())
            w.parts.append(("exp", s[i:self.i], []))
        elif nxt and nxt in "@*#?$!-":
            self.i = i + 2
            w.parts.append(("exp", s[i:self.i], []))
        else:
            w.add_lit("$", in_dq)
            self.i = i + 1

    def backtick_into(self, w, in_dq):
        j, buf, esc = self.i + 1, [], "`\\$" + ('"' if in_dq else "")
        while j < self.n and self.s[j] != "`":
            if self.s[j] == "\\" and j + 1 < self.n and self.s[j + 1] in esc:
                j += 1
            buf.append(self.s[j])
            j += 1
        if j >= self.n:
            self.fail("unterminated `")
        raw = self.s[self.i:j + 1]
        self.i = j + 1
        w.parts.append(("sub", raw, Lexer("".join(buf), self.depth + 1).program(None, 1)))


def parse(src, depth=0):
    return Lexer(src, depth).program()


def flatten(prog, depth=0, out=None):
    """Every simple command, depth-first, including substitutions and unquoted heredoc bodies."""
    out = [] if out is None else out
    for cmd in prog:
        out.append((cmd, depth))
        words = list(cmd.words) + [r["target"] for r in cmd.redirs if r.get("target") is not None] + \
            [r["body"] for r in cmd.redirs if r.get("body") is not None]
        for w in words:
            for p in w.parts:
                if p[0] == "sub":
                    flatten(p[2], depth + 1, out)
                elif p[0] == "exp":
                    for sp in p[2]:
                        flatten(sp, depth + 1, out)
    return out


# --- Markers ------------------------------------------------------------------------------------
# What makes a command the guard cannot parse worth denying. Matched case-insensitively against
# the raw command and every decoded literal in it ($'\x67\x68' is matched as "gh").
MARKERS = [
    ("ci", "a merge", re.compile(r"merge", re.I)),
    ("ci", "a push or ref", re.compile(r"push|send-pack|git/refs|refs/heads|updateref|deleteref|createref|"
                                       r"createcommitonbranch|/contents/|/protection|rulesets", re.I)),
    ("ci", "the GitHub API or token", re.compile(r"auth\s+token|show-token|credential|api\.github\.com|"
                                                 r"/api/v3|graphql", re.I)),
    ("ci", "a guard file", re.compile(r"\.claude|merge-guard|settings(\.local)?\.json|hooks|autoloop", re.I)),
    ("gate", "the ready label", re.compile(r"(^|[^a-z0-9_])ready($|[^a-z0-9_])", re.I)),
]
TAMPER_RE = MARKERS[3][2]
ROBOT_RE = re.compile("\U0001F916" + r"|\\ud83e\\udd16|\\U0001f916|\\xf0\\x9f\\xa4\\x96|1f916", re.I)


# --- Paths --------------------------------------------------------------------------------------
def canon(path, base):
    """Absolute, with `.`, `..`, `//` and symlinks resolved, lower-cased (APFS ignores case)."""
    if path.startswith("~"):
        path = os.path.expanduser(path)
    if not os.path.isabs(path):
        path = os.path.join(base or "/", path)
    stack, cur, hops = [p for p in path.split("/") if p not in ("", ".")], "/", 0
    while stack:
        p = stack.pop(0)
        if p == "..":
            cur = os.path.dirname(cur) or "/"
            continue
        nxt = os.path.join(cur, p)
        if hops < 40 and os.path.islink(nxt):
            hops += 1
            try:
                target = os.readlink(nxt)
            except OSError:
                cur = nxt
                continue
            if os.path.isabs(target):
                cur = "/"
            stack = [q for q in target.split("/") if q not in ("", ".")] + stack
            continue
        cur = nxt
    return cur.lower()


# The guard's own files, and the runbook: human-steered — its ready-approvers decide whose issues the
# loop trusts, and the loop commits an uncommitted edit of it to main as the human's steering.
GUARD_FILE_REL = [".claude/hooks/merge-guard.sh", ".claude/hooks/merge-guard.mode", ".claude/settings.json",
                  ".claude/settings.local.json"]
PROT_FILE_REL = GUARD_FILE_REL + ["openspec/AUTOLOOP.md"]
PROT_DIR_REL = [".claude/hooks", ".claude"]          # nothing may be written inside these
PROT_PARENT_REL = ["openspec"]                       # holds a protected file: not to be removed or reverted
PROT_FILES = set(canon(p, PROJECT_DIR) for p in PROT_FILE_REL)
PROT_DIRS = set(canon(p, PROJECT_DIR) for p in PROT_DIR_REL)
PROT_PARENTS = set(canon(p, PROJECT_DIR) for p in PROT_PARENT_REL)
PROJECT_CANON = canon(PROJECT_DIR, "/")
PROT_SPELLINGS = set(PROT_FILES | PROT_DIRS | PROT_PARENTS) | \
    set(os.path.normpath(os.path.join(PROJECT_DIR, p)).lower() for p in PROT_FILE_REL + PROT_DIR_REL + PROT_PARENT_REL)


def protected(path, base, kind="file"):
    """Does a literal path name a protected file? kind "file": a protected file or directory is written,
    moved or removed; "exact": only a protected file itself; "tree": a git pathspec, which covers
    everything below it; "into": something is written inside the path, so the project directory and
    its parents count too."""
    c = canon(path, base)
    if c in PROT_FILES:
        return True
    if kind == "exact":
        return False
    if c in PROT_DIRS or (kind in ("file", "tree") and c in PROT_PARENTS):
        return True
    if kind == "tree":
        return any(f.startswith(c.rstrip("/") + "/") for f in PROT_FILES)
    return kind == "into" and (c in PROT_PARENTS or c == PROJECT_CANON or PROJECT_CANON.startswith(c.rstrip("/") + "/"))


def brace_alternatives(t):
    m = re.search(r"\{([^{}]*,[^{}]*)\}", t)
    if not m:
        return [t]
    return [t[:m.start()] + alt + t[m.end():] for alt in m.group(1).split(",")]


def maybe_protected(tail, partial):
    """A path whose start is an expansion (or a pattern): could it name a guard file, whatever the
    unknown part is? `partial`: the first component may continue an expansion (`"$D"settings.json`)."""
    for t in brace_alternatives(tail.lower()):
        comps = [c for c in re.split(r"/+", t) if c not in ("", ".")]
        if not comps or ".." in comps:
            return True
        for full in PROT_SPELLINGS:
            fc = [c for c in full.split("/") if c]
            if len(comps) > len(fc):
                continue
            ok = True
            for k, (pat, real) in enumerate(zip(comps, fc[len(fc) - len(comps):])):
                if not fnmatch.fnmatchcase(real, ("*" + pat) if (k == 0 and partial) else pat):
                    ok = False
                    break
            if ok:
                return True
    return False


# --- Classification -----------------------------------------------------------------------------
SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "mksh", "ash", "rbash", "yash", "posh", "fish", "csh",
          "tcsh", "busybox"}
INTERP_RE = re.compile(r"^(python|pypy|perl|ruby|php|lua|luajit|node|nodejs|deno|bun|tclsh|wish|expect|"
                       r"osascript|rscript|julia|pwsh|powershell|groovy|jshell|swift|irb|[gnm]?awk)[0-9.]*$")
# Wrappers that run their arguments as a command: name -> (short options taking a value, long ones).
WRAPPERS = {
    "command": ("", ()), "builtin": ("", ()), "exec": ("a", ()), "nohup": ("", ()), "time": ("", ()),
    "chronic": ("", ()), "unbuffer": ("", ()), "setsid": ("", ()), "caffeinate": ("tw", ()),
    "stdbuf": ("ioe", ("input", "output", "error")), "nice": ("n", ("adjustment",)),
    "ionice": ("cnpPu", ("class", "classdata", "pid", "pgid", "uid")), "doas": ("uC", ()),
    "sudo": ("ughpCDRTUrt", ("user", "group", "host", "prompt", "close-from", "chdir", "chroot",
                              "command-timeout", "other-user", "role", "type")),
    "torsocks": ("upaP", ()), "proxychains": ("f", ()), "proxychains4": ("f", ()),
    "timeout": ("sk", ("signal", "kill-after")), "gtimeout": ("sk", ("signal", "kill-after")),
}
READONLY = set("""cat head tail less more grep egrep fgrep rg ag ack ls stat file wc diff cmp comm md5 md5sum
 shasum sha1sum sha256sum sha512sum cksum b2sum readlink realpath basename dirname test [ [[ jq cut tr nl od
 hexdump strings column fold fmt rev tac paste join expand unexpand true false : echo printf pwd type which
 whence whereis date printenv id whoami uname hostname sleep wait exit return set shopt tput yes seq tree du
 df bat man help let shift getopts umask ulimit hash unalias jobs fg bg disown kill read mapfile readarray
 sort uniq mkdir mktemp""".split())
# Build and device tools whose arguments are not commands. Not xcrun: it runs any developer tool, git included.
PROJECT_TOOLS = set("""gradlew gradle openspec android adb emulator sdkmanager avdmanager java javac kotlin
 kotlinc xcodebuild npm pnpm yarn brew make gitleaks git-cliff yq xxd plutil defaults open pbcopy pbpaste""".split())
WRITERS_DEST = {"cp", "gcp", "install", "rsync", "ditto", "scp"}
WRITERS_ALL = {"mv", "gmv", "ln", "rm", "rmdir", "unlink", "shred", "srm", "trash", "touch", "truncate",
               "chmod", "chown", "chgrp", "chflags", "xattr", "setfacl", "mkfifo", "mknod", "tee", "sponge",
               "vi", "vim", "nvim", "nano", "emacs", "ed", "ex", "code", "subl", "sudoedit"}
WRITERS_UNKNOWN = {"patch", "tar", "bsdtar", "gtar", "unzip", "cpio", "7z"}
STASH_SUBS = {"list", "show", "drop", "clear", "pop", "apply", "branch", "create", "store"}
GIT_BUILTINS = set("""add am annotate apply archive bisect blame branch bugreport bundle cat-file check-attr
 check-ignore check-mailmap check-ref-format checkout checkout-index cherry cherry-pick citool clean clone
 column commit commit-graph commit-tree config count-objects credential credential-cache credential-store
 credential-osxkeychain credential-manager describe diagnose diff diff-files diff-index diff-tree difftool
 fast-export fast-import fetch fetch-pack filter-branch fmt-merge-msg for-each-ref for-each-repo format-patch
 fsck gc get-tar-commit-id grep gui hash-object help hook http-backend index-pack init instaweb
 interpret-trailers lfs log ls-files ls-remote ls-tree mailinfo mailsplit maintenance merge merge-base
 merge-file merge-index merge-one-file merge-tree mergetool mktag mktree multi-pack-index mv notes
 pack-objects pack-redundant pack-refs patch-id prune prune-packed pull push range-diff read-tree rebase
 receive-pack reflog remote repack replace replay rerere reset restore rev-list rev-parse revert rm
 send-email send-pack shortlog show show-branch show-index show-ref sparse-checkout stage stash status
 stripspace submodule subtree switch symbolic-ref tag unpack-file unpack-objects update-index update-ref
 update-server-info upload-archive upload-pack var verify-commit verify-pack verify-tag version
 whatchanged worktree write-tree""".split())
GH_TOP = set("""alias api attestation auth browse cache co codespace completion config copilot extension
 ext extensions gist gpg-key help issue label org pr project release repo ruleset rs run search secret
 ssh-key status variable workflow preview agent-task accessibility licenses version""".split())
GH_VALUE = {
    "*": {"-R", "--repo"},
    "pr merge": {"-t", "--subject", "-b", "--body", "-F", "--body-file", "-A", "--author-email",
                 "--match-head-commit"},
    "pr review": {"-b", "--body", "-F", "--body-file"},
    "pr comment": {"-b", "--body", "-F", "--body-file"},
    "issue comment": {"-b", "--body", "-F", "--body-file"},
    "issue create": {"-t", "--title", "-b", "--body", "-F", "--body-file", "-l", "--label", "-a", "--assignee",
                     "-m", "--milestone", "-p", "--project", "-T", "--template", "--recover", "--parent"},
    "issue edit": {"-t", "--title", "-b", "--body", "-F", "--body-file", "--add-label", "--remove-label",
                   "--add-assignee", "--remove-assignee", "--add-project", "--remove-project", "-m",
                   "--milestone", "--parent"},
    "label edit": {"-n", "--name", "-c", "--color", "-d", "--description"},
    "api": {"-X", "--method", "-f", "--raw-field", "-F", "--field", "-H", "--header", "--input", "-q", "--jq",
            "-t", "--template", "-p", "--preview", "--cache", "--hostname"},
    "auth token": {"-h", "--hostname", "-u", "--user"},
    "auth status": {"-h", "--hostname"},
}
GH_VALUE["issue new"] = GH_VALUE["issue create"]
PUSH_LONG = ["all", "branches", "mirror", "delete", "tags", "dry-run", "porcelain", "force", "force-with-lease",
             "force-if-includes", "recurse-submodules", "thin", "receive-pack", "exec", "set-upstream",
             "progress", "prune", "verify", "follow-tags", "signed", "atomic", "push-option", "ipv4", "ipv6",
             "repo", "quiet", "verbose"]
EXEC_CONFIG_RE = re.compile(r"^(core\.(pager|editor|sshcommand|fsmonitor|hookspath|askpass)|sequence\.editor|"
                            r"diff\.external|pager\..*|credential\..*helper|gpg\.program|"
                            r"(merge|diff|filter)\..*\.(driver|command|textconv|clean|smudge|process))$", re.I)
GITHUB_URL_RE = re.compile(r"(^|[/@.])(api\.)?github\.com(/|:|$)|/api/(v3|graphql)", re.I)
TRACKED_ENV = ("GH_REPO", "GH_HOST", "GH_CONFIG_DIR", "GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG",
               "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS")


def lit_of(w, strict=False):
    return None if w is None else w.literal(strict)


def is_assignment(w):
    if not w.parts or w.parts[0][0] != "lit" or w.parts[0][2]:
        return None
    m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)(\[[^\]]*\])?\+?=", w.parts[0][1])
    return m.group(1) if m else None


def assignment_value(w):
    v = Word()
    v.parts = [("lit", w.parts[0][1].split("=", 1)[1], True)] + list(w.parts[1:])
    return v


def cmd_name(w):
    """The command's literal basename, lower-cased (APFS also finds `GH` as gh), else None."""
    t = w.literal(strict=False)
    if t is None:
        last = w.parts[-1] if w.parts else None
        if not last or last[0] != "lit" or "/" not in last[1]:
            return None
        t = last[1]
    base = t.rsplit("/", 1)[-1].lstrip("=")
    if base in ("[", "[["):
        return base
    if not base or (SPECIAL_RE.search(base) and any(p[0] == "lit" and not p[2] for p in w.parts)):
        return None
    return base.lower()


def stdin_of(cmd):
    """→ ("text", str) | ("dynamic"|"pipe"|"file"|None, None)."""
    for r in cmd.redirs:
        if r["op"] in ("<<", "<<-"):
            if r.get("body") is None:
                return "text", ""
            return "text", (r["text"] or "") if r["quoted"] else r["body"].text()
        if r["op"] == "<<<":
            t = lit_of(r["target"])
            return ("text", t) if t is not None else ("dynamic", None)
        if r["op"] == "<":
            return "file", None
    return ("pipe", None) if cmd.piped else (None, None)


def skip_opts(args, short_val="", long_val=()):
    """Index of the first argument after the options (a `--` is consumed; a non-literal word ends
    them). short_val/long_val: options whose value is the next argument."""
    i = 0
    while i < len(args):
        t = lit_of(args[i])
        if t is None:
            return i
        if t == "--":
            return i + 1
        if t.startswith("--") and len(t) > 2:
            i += 2 if ("=" not in t and t[2:] in long_val) else 1
            continue
        if t.startswith("-") and len(t) > 1:
            if not t[1:].isdigit():
                for k, ch in enumerate(t[1:]):
                    if ch in short_val:
                        i += 1 if k == len(t) - 2 else 0
                        break
            i += 1
            continue
        return i
    return i


class Ctx(object):
    """What one Bash command does, as far as the guard can tell."""

    def __init__(self, raw, cwd):
        self.raw, self.cwd, self.cwd_known = raw, cwd, True
        self.env = {}                     # tracked variable -> Word, or None when unset
        self.actions, self.opaque, self.touched, self.lits = [], [], [], []
        self.structural = False           # gh/git whose subcommand or options are not literal

    def act(self, kind, detail):
        self.actions.append((kind, detail))

    def dark(self, why, structural=False):
        self.opaque.append(why)
        self.structural = self.structural or structural

    def touch(self, w, kind, base=""):
        """base: the directory a relative path resolves in ("" = the shell's cwd, None = unknown)."""
        self.touched.append((w, kind, (self.cwd if self.cwd_known else None) if base == "" else base))

    def git_touch(self, w, kind, d):
        """A path a git command writes resolves in the directory git runs in (`-C`). When that directory
        is unknown, check it from the shell's cwd and as a path in an unknown place."""
        if d is not None:
            return self.touch(w, kind, d)
        self.touch(w, kind)
        self.touch(w, kind, None)


class Classifier(object):
    def __init__(self, ctx):
        self.ctx = ctx

    def string(self, src, depth, input_args=False):
        """Classify a command string another command runs (bash -c, eval, an alias, …)."""
        if depth > 8:
            self.ctx.dark("commands nested too deeply")
            return
        try:
            prog = parse(src, depth)
        except ParseError as e:
            self.ctx.dark("unparseable command string (%s)" % e)
            return
        for cmd, d in flatten(prog):
            self.cmd(cmd, depth + d, input_args)

    def cmd(self, cmd, depth, input_args=False):
        ctx = self.ctx
        for w in cmd.words:
            t = w.literal(strict=False)
            if t is not None:
                ctx.lits.append(t)
        for r in cmd.redirs:
            if r.get("target") is not None and r["op"] in WRITE_REDIRS:
                t = lit_of(r["target"])
                if not (r["op"] == ">&" and t is not None and (t == "-" or t.isdigit())):
                    ctx.touch(r["target"], "file")
            elif r.get("text"):
                ctx.lits.append(r["text"])
        if cmd.data:
            return
        words, prefix = list(cmd.words), {}
        while words and is_assignment(words[0]):
            w = words.pop(0)
            if is_assignment(w) in TRACKED_ENV:
                prefix[is_assignment(w)] = assignment_value(w)
        if not words:
            ctx.env.update(prefix)        # a bare `GH_REPO=x`: later commands may see it
            return
        self.run_words(words, cmd, depth, prefix, input_args)

    def run_words(self, words, cmd, depth, prefix, input_args):
        ctx = self.ctx
        if not words:
            return
        name = cmd_name(words[0])
        if name is None:
            ctx.dark("the command name is not literal (%s)" % words[0].text()[:60])
            return
        args = words[1:]

        def again(k, inp=input_args, pre=prefix):
            return self.run_words(args[k:], cmd, depth, pre, inp)

        if name in WRAPPERS:
            short_val, long_val = WRAPPERS[name]
            k = skip_opts(args, short_val, long_val)
            opts = [lit_of(a) for a in args[:k]]
            if name in ("command", "builtin") and ("-v" in opts or "-V" in opts):
                return
            if name == "sudo" and ("-e" in opts or "--edit" in opts):
                for a in args[k:]:
                    ctx.touch(a, "file")
                return
            return again(k + 1 if name in ("timeout", "gtimeout") else k)
        if name == "env":
            return self.env_cmd(args, cmd, depth, prefix, input_args)
        if name == "xargs":
            k = skip_opts(args, "ILnPsdEa", ("max-lines", "max-args", "max-procs", "max-chars", "delimiter",
                                             "arg-file", "process-slot-var"))
            return again(k, True) if k < len(args) else None
        if name == "parallel":
            k = skip_opts(args, "jSINnLEad", ("jobs", "sshlogin", "arg-file", "delimiter", "colsep", "joblog",
                                              "results", "tmpdir", "workdir", "env"))
            tmpl = []
            for a in args[k:]:
                if lit_of(a) in (":::", "::::", ":::+", "::::+"):
                    break
                tmpl.append(a)
            if len(tmpl) == 1 and " " in (lit_of(tmpl[0]) or ""):
                return self.string(lit_of(tmpl[0]), depth + 1, True)
            return self.run_words(tmpl, cmd, depth, prefix, True)
        if name == "find":
            return self.find(args, cmd, depth, prefix)
        if name == "watch":
            k = skip_opts(args, "nq", ("interval",))
            if any(lit_of(a) in ("-x", "--exec") for a in args[:k]):
                return again(k)
            parts = [lit_of(a) for a in args[k:]]
            return ctx.dark("watch runs a non-literal command") if None in parts else \
                self.string(" ".join(parts), depth + 1, input_args)
        if name == "trap":
            code = lit_of(args[0]) if args else ""
            if code is None:
                ctx.dark("trap with non-literal code")
            elif code and not code.startswith("-"):
                self.string(code, depth + 1)
            return
        if name == "eval":
            parts = [lit_of(a) for a in args]
            return ctx.dark("eval of a non-literal string") if None in parts else \
                self.string(" ".join(parts), depth + 1, input_args)
        if name in ("source", "."):
            t = lit_of(args[0]) if args else None
            if t in ("/dev/stdin", "-", "/dev/fd/0", "/proc/self/fd/0"):
                kind, text = stdin_of(cmd)
                return self.string(text, depth + 1) if kind == "text" else ctx.dark("source of stdin")
            if args and args[0].has_sub():
                ctx.dark("source of a substitution")
            return
        if name in SHELLS:
            return self.shell(name, args, cmd, depth, prefix, input_args)
        if INTERP_RE.match(name):
            return self.interp(name, args, cmd)
        if name == "gh":
            return self.gh(args, cmd, depth, prefix, input_args)
        if name == "git":
            return self.git(args, cmd, depth, prefix, input_args)
        if name in ("curl", "wget", "http", "https", "xh", "xhs"):
            return self.http(name, args)
        if name in ("cd", "pushd", "popd", "chdir"):
            k = skip_opts(args)
            t = (lit_of(args[k], True) if k < len(args) else "~") if name != "popd" else None
            if t is None or t == "-" or cmd.scope > 0 or depth > 0 or not ctx.cwd_known:
                ctx.cwd_known = False
            else:
                ctx.cwd = os.path.normpath(os.path.join(ctx.cwd, os.path.expanduser(t)))
            return
        if name in ("export", "declare", "typeset", "local", "readonly"):
            for a in args:
                if is_assignment(a) in TRACKED_ENV:
                    ctx.env[is_assignment(a)] = assignment_value(a)
            return
        if name == "unset":
            for a in args:
                if lit_of(a) in TRACKED_ENV:
                    ctx.env[lit_of(a)] = None
            return
        if name == "sed":
            for a in args:
                t = lit_of(a)
                if t is not None and re.search(r"(^|[;\n}])\s*e(\s|$)|s(.).*\1.*\1[gpIiMm0-9]*e", t):
                    ctx.dark("a sed script that runs commands")
            if any(re.match(r"^(-[a-zA-Z]*i|--in-place)", lit_of(a) or "") for a in args):
                for a in args:
                    if not (lit_of(a) or "x").startswith("-"):
                        ctx.touch(a, "file")
            return
        if name == "dd":
            for a in args:
                if a.text().startswith("of="):
                    t = lit_of(a)
                    v = Word(t[3:]) if t is not None else Word()
                    if t is None:
                        v.parts = [("lit", a.parts[0][1][3:], True)] + list(a.parts[1:])
                    ctx.touch(v, "file")
            return
        if name in WRITERS_ALL:
            for a in args:
                t = lit_of(a)
                if t is None or not t.startswith("-") or t == "-":
                    ctx.touch(a, "file")
            return
        if name in WRITERS_DEST:
            pos, tdir, i = [], None, 0
            while i < len(args):
                t = lit_of(args[i])
                if t in ("-t", "--target-directory") and i + 1 < len(args):
                    tdir = args[i + 1]
                    i += 1
                elif t is not None and t.startswith("--target-directory="):
                    tdir = Word(t.split("=", 1)[1])
                elif t is None or not t.startswith("-"):
                    pos.append(args[i])
                i += 1
            dest = tdir or (pos[-1] if len(pos) > 1 else None)
            if dest is not None:
                ctx.touch(dest, "into")
            return
        if name in WRITERS_UNKNOWN:
            ctx.touch(None, "unknown")
            return
        if name in READONLY or name in PROJECT_TOOLS:
            return
        # An unknown command: a wrapper around gh/git or a shell, or one that takes a command string?
        for k, a in enumerate(args):
            t = lit_of(a)
            if t is None:
                continue
            b = t.rsplit("/", 1)[-1].lower()
            if b in ("gh", "git", "eval", "xargs", "env", "sudo") or b in SHELLS or INTERP_RE.match(b):
                ctx.dark("%s runs %s" % (name, b))
                return again(k)
            if re.search(r"\s", t) and any(m[2].search(t) for m in MARKERS):
                ctx.dark("%s takes a command string" % name)
                return self.string(t, depth + 1, input_args)
            if not t.startswith("-"):
                ctx.touch(a, "exact")

    def env_cmd(self, args, cmd, depth, prefix, input_args):
        ctx, sub, i = self.ctx, dict(prefix), 0
        while i < len(args):
            t = lit_of(args[i])
            if t is None:
                break
            if t in ("-i", "--ignore-environment", "-"):
                sub.update((v, None) for v in TRACKED_ENV)
            elif t in ("-u", "--unset"):
                sub[lit_of(args[i + 1]) if i + 1 < len(args) else ""] = None
                i += 1
            elif t.startswith("--unset=") or (t.startswith("-u") and len(t) > 2):
                sub[t.split("=", 1)[1] if "=" in t else t[2:]] = None
            elif t in ("-S", "--split-string") or t.startswith("--split-string=") or (t.startswith("-S") and len(t) > 2):
                if t in ("-S", "--split-string"):
                    s, nxt = lit_of(args[i + 1]) if i + 1 < len(args) else "", i + 2
                else:
                    s, nxt = (t.split("=", 1)[1] if "=" in t else t[2:]), i + 1
                if s is None:
                    return ctx.dark("env -S with a non-literal string")
                try:
                    words = [w for c in parse(s, depth + 1) for w in c.words]
                except ParseError:
                    return ctx.dark("unparseable env -S string")
                return self.run_words(words + args[nxt:], cmd, depth, sub, input_args)
            elif t in ("-C", "--chdir", "-P"):
                i += 1
            elif t.startswith("-"):
                pass
            elif is_assignment(args[i]):
                if is_assignment(args[i]) in TRACKED_ENV:
                    sub[is_assignment(args[i])] = assignment_value(args[i])
            else:
                break
            i += 1
        return self.run_words(args[i:], cmd, depth, sub, input_args)

    def find(self, args, cmd, depth, prefix):
        ctx, i, starts = self.ctx, 0, []
        while i < len(args) and not (lit_of(args[i]) or "x").startswith(("-", "(", "!")):
            starts.append(args[i])
            i += 1
        while i < len(args):
            t = lit_of(args[i])
            if t in ("-exec", "-execdir", "-ok", "-okdir"):
                j = i + 1
                while j < len(args) and lit_of(args[j]) not in (";", "+"):
                    j += 1
                self.run_words(args[i + 1:j], cmd, depth, prefix, True)
                i = j
            elif t == "-delete":
                for s in starts or [Word(".")]:
                    ctx.touch(s, "into")
            elif t in ("-fprint", "-fprint0", "-fprintf", "-fls") and i + 1 < len(args):
                ctx.touch(args[i + 1], "file")
            i += 1

    def shell(self, name, args, cmd, depth, prefix, input_args):
        ctx = self.ctx
        if name == "busybox":
            return self.run_words(args, cmd, depth, prefix, input_args)
        i, cmode, smode = 0, False, False
        while i < len(args):
            t = lit_of(args[i])
            if t is None:
                break
            if t == "--":
                i += 1
                break
            if t in ("-o", "+o", "-O", "+O", "--rcfile", "--init-file"):
                i += 2
                continue
            if t[:1] in ("-", "+") and len(t) > 1:
                if not t.startswith("--"):
                    cmode = cmode or "c" in t[1:]
                    smode = smode or "s" in t[1:]
                i += 1
                continue
            break
        if cmode:
            s = lit_of(args[i]) if i < len(args) else None
            return ctx.dark("%s -c runs a non-literal command" % name) if s is None else \
                self.string(s, depth + 1, input_args)
        if i < len(args) and not smode:
            if args[i].has_sub():
                ctx.dark("%s runs the output of a substitution" % name)
            return                                          # runs a script file
        kind, text = stdin_of(cmd)
        if kind == "text":
            return self.string(text, depth + 1)
        if kind in ("pipe", "dynamic"):
            ctx.dark("commands piped into %s" % name)

    def interp(self, name, args, cmd):
        ctx = self.ctx
        if re.match(r"^[gnm]?awk", name):
            k = skip_opts(args, "fvF")
            if any(lit_of(a) == "-f" or (lit_of(a) or "").startswith("--file") for a in args[:k]):
                return
            prog = lit_of(args[k]) if k < len(args) else None
            if prog is None or re.search(r"system|\||>|getline", prog):
                ctx.dark("an awk program that runs commands or writes files")
            return
        base = re.sub(r"[0-9.]+$", "", name)
        flags = {"python": "c", "pypy": "c", "perl": "eE", "ruby": "e", "irb": "e", "node": "ep", "nodejs": "ep",
                 "bun": "e", "php": "r", "osascript": "e", "expect": "c", "rscript": "e", "julia": "e",
                 "pwsh": "c", "powershell": "c"}.get(base, "ce")
        for a in args:
            t = lit_of(a)
            if t is None:
                return ctx.dark("%s with a non-literal argument" % name)
            if t in ("--eval", "--print", "-Command", "eval") or \
                    (t.startswith("-") and not t.startswith("--") and any(ch in flags for ch in t[1:])):
                return ctx.dark("inline %s code" % name)
            if t == "-m" and base in ("python", "pypy"):
                return
            if t == "-":
                break
            if not t.startswith("-"):
                if base in ("perl", "ruby") and any(re.match(r"^-[a-zA-Z]*i", lit_of(x) or "") for x in args):
                    for x in args:
                        if not (lit_of(x) or "-").startswith("-"):
                            ctx.touch(x, "file")
                return                                       # a script file
        if stdin_of(cmd)[0] in ("text", "pipe", "dynamic"):
            ctx.dark("%s code from stdin" % name)

    # -- gh -------------------------------------------------------------------------------------
    def gh_parse(self, args, valset):
        flags, pos, dyn, i = [], [], [], 0
        while i < len(args):
            a = args[i]
            t = lit_of(a)
            if t is None:
                pos.append(a)
                dyn.append(a)
            elif t == "--":
                pos.extend(args[i + 1:])
                break
            elif t.startswith("--") and len(t) > 2:
                nm, eq, val = t.partition("=")
                if eq:
                    flags.append((nm, Word(val)))
                elif nm in valset:
                    flags.append((nm, args[i + 1] if i + 1 < len(args) else None))
                    i += 1
                else:
                    flags.append((nm, None))
            elif t.startswith("-") and len(t) > 1 and not t[1:].isdigit():
                if "-" + t[1] in valset:
                    if len(t) > 2:
                        flags.append(("-" + t[1], Word(t[3:] if t[2] == "=" else t[2:])))
                    else:
                        flags.append(("-" + t[1], args[i + 1] if i + 1 < len(args) else None))
                        i += 1
                else:
                    flags.extend(("-" + ch, None) for ch in t[1:])
            else:
                pos.append(a)
            i += 1
        return flags, pos, dyn

    def gh(self, args, cmd, depth, prefix, input_args, alias_depth=0):
        ctx = self.ctx
        env = dict(ctx.env)
        env.update(prefix)
        _, pos0, _ = self.gh_parse(args, GH_VALUE["*"])
        if not pos0:
            return
        top = lit_of(pos0[0])
        if top is None or (len(pos0) > 1 and lit_of(pos0[1]) is None):
            return ctx.dark("the gh subcommand is not literal", True)
        top = top.lower()
        if top not in GH_TOP:
            exp = self.gh_alias(top, env)
            if exp is None or alias_depth > 3:
                return ctx.dark("gh %s is an extension, an unknown command or an alias loop" % top)
            rest = [a for a in args if a is not pos0[0]]
            if exp.startswith("!"):
                return self.string(exp[1:] + " " + " ".join(a.text() for a in rest), depth + 1, input_args)
            try:
                words = [w for c in parse(exp, depth + 1) for w in c.words]
            except ParseError:
                return ctx.dark("unparseable gh alias")
            out, used = [], set()
            for w in words:
                m = re.match(r"^\$(\d+)$", w.text())
                if m:
                    used.add(int(m.group(1)) - 1)
                    out.append(rest[int(m.group(1)) - 1] if int(m.group(1)) - 1 < len(rest) else Word(""))
                else:
                    out.append(w)
            out += [r for k, r in enumerate(rest) if k not in used]
            return self.gh(out, cmd, depth, prefix, input_args, alias_depth + 1)
        sub = (lit_of(pos0[1]) or "").lower() if len(pos0) > 1 else ""
        key = "api" if top == "api" else "%s %s" % (top, sub)
        flags, pos, dyn = self.gh_parse(args, GH_VALUE["*"] | GH_VALUE.get(key, set()))

        def fl(*names):
            return [v for n, v in flags if n in names]

        if top == "alias" and sub in ("set", "import"):
            return ctx.act("token", "gh alias %s" % sub)
        if top == "auth" and (sub in ("token", "git-credential") or (sub == "status" and fl("-t", "--show-token"))):
            return ctx.act("token", "gh auth %s" % sub)
        if top == "pr" and sub == "merge":
            if fl("--disable-auto"):
                return
            target = pos[2] if len(pos) > 2 else None
            why = []
            if input_args:
                why.append("its arguments come from xargs/find/parallel input")
            if target is not None and lit_of(target, True) is None:
                why.append("the PR (%s) is not literal" % target.text()[:40])
            if any(d is not target for d in dyn):
                why.append("an argument is not literal")
            repo, extra = None, {}
            if fl("-R", "--repo"):
                repo = lit_of(fl("-R", "--repo")[-1], True)
                if repo is None:
                    why.append("--repo is not literal")
            elif "GH_REPO" in env:
                if env["GH_REPO"] is None:
                    extra["GH_REPO"] = None
                else:
                    repo = lit_of(env["GH_REPO"], True)
                    if repo is None:
                        why.append("GH_REPO is not literal")
            if not ctx.cwd_known and not repo:
                why.append("an earlier `cd` makes the repository unknown")
            if env.get("GH_HOST") is not None:
                extra["GH_HOST"] = lit_of(env["GH_HOST"], True)
                if extra["GH_HOST"] is None:
                    why.append("GH_HOST is not literal")
            admin = any(v is None or (lit_of(v) or "true").lower() not in ("false", "0") for v in fl("--admin"))
            return ctx.act("merge", {"target": lit_of(target, True) if target is not None else "", "repo": repo,
                                     "admin": admin, "cwd": ctx.cwd, "why": "; ".join(why), "env": extra})
        if (top, sub) in (("pr", "review"), ("pr", "comment"), ("issue", "comment")):
            return self.gh_forge("%s %s" % (top, sub), fl("-b", "--body"), fl("-F", "--body-file"), cmd,
                                 review=sub == "review")
        if top == "issue" and sub in ("create", "new", "edit"):
            for v in fl("-l", "--label", "--add-label"):
                t = lit_of(v)
                if t is None:
                    return ctx.act("promote", "gh issue %s with a label that is not literal" % sub)
                if any(x.strip().lower() == "ready" for x in t.split(",")):
                    return ctx.act("promote", "gh issue %s --label ready" % sub)
            return
        if top == "label" and sub == "edit":
            for v in fl("-n", "--name"):
                t = lit_of(v)
                if t is None or t.strip().lower() == "ready":
                    return ctx.act("promote", "gh label edit --name %s" % (t or "<not literal>"))
            return
        if top == "api":
            return self.gh_api(flags, pos, cmd, input_args, env)

    def gh_alias(self, name, env):
        extra = {}
        if env.get("GH_CONFIG_DIR") is not None:
            extra["GH_CONFIG_DIR"] = lit_of(env["GH_CONFIG_DIR"], True)
            if extra["GH_CONFIG_DIR"] is None:
                return None
        rc, out = run(["gh", "alias", "list"], cwd=self.ctx.cwd, env_extra=extra, timeout=8)
        for line in out.splitlines() if rc != 124 else []:
            k, sep, v = line.partition(":")
            if sep and k.strip().lower() == name:
                v = v.strip()
                return v[1:-1] if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"" else v
        return None

    def read_file(self, p, limit=262144):
        try:
            with open(os.path.join(self.ctx.cwd or PROJECT_DIR, os.path.expanduser(p)), encoding="utf-8",
                      errors="replace") as f:
                return f.read(limit)
        except OSError:
            return None

    def gh_forge(self, what, bodies, files, cmd, review):
        """A subagent's review or comment: does its body carry the gate header?"""
        if not IS_SUB:
            return
        text, why = "", None
        for v in bodies:
            text = lit_of(v)
            why = None if text is not None else "the body is not literal"
        for v in files:
            p = lit_of(v, True)
            if p == "-":
                kind, text = stdin_of(cmd)
                text = text if kind == "text" else None
            else:
                text = self.read_file(p) if p is not None else None
            why = None if text is not None else "the body file cannot be read"
        if text is not None:
            if text.lstrip().startswith(GATE_PREFIX):
                self.ctx.act("forge", "gh %s with the gate header" % what)
        elif review or ROBOT_RE.search(self.ctx.raw):
            self.ctx.act("forge", "gh %s: %s" % (what, why))

    def gh_api(self, flags, pos, cmd, input_args, env):
        ctx = self.ctx
        ep_w = pos[1] if len(pos) > 1 else None
        if ep_w is None:
            return
        methods = [v for n, v in flags if n in ("-X", "--method")]
        fields = [(n, v) for n, v in flags if n in ("-f", "--raw-field", "-F", "--field")]
        inputs = [v for n, v in flags if n == "--input"]
        if methods:
            method = (lit_of(methods[-1], True) or "?").upper()
        else:
            method = "POST" if (fields or inputs) else "GET"
        write = method not in ("GET", "HEAD")
        if ep_w.parts and ep_w.parts[0][0] != "lit":
            if write:
                ctx.dark("gh api writes to a non-literal endpoint")
            return
        ep = "".join(p[1] if p[0] == "lit" else "\0" for p in ep_w.parts)    # \0 = not literal
        ep = re.sub(r"^https?://[^/]+/(api/v3/)?", "", ep)
        ep = re.sub(r"%([0-9a-fA-F]{2})", lambda m: chr(int(m.group(1), 16)), ep)
        ep = re.sub(r"/+", "/", re.sub(r"[?#].*$", "", ep)).strip("/").lower()
        if "{branch}" in ep:
            ep = ep.replace("{branch}", run(["git", "symbolic-ref", "--short", "-q", "HEAD"], cwd=ctx.cwd,
                                            timeout=5)[1].strip().lower() or "\0")
        m = re.match(r"^repos/([^/{}\0]+)/([^/{}\0]+)/", ep)
        repo = "%s/%s" % (m.group(1), m.group(2)) if m else \
            (lit_of(env["GH_REPO"], True) if env.get("GH_REPO") is not None else None)

        def field_texts():
            """(key, text) of every field and --input; None when one cannot be read."""
            out = []
            for n, v in fields:
                t = lit_of(v)
                if t is None:
                    return None
                key, _, val = t.partition("=")
                if n in ("-F", "--field") and val.startswith("@"):
                    val = stdin_of(cmd)[1] if val == "@-" else self.read_file(val[1:])
                    if val is None:
                        return None
                out.append((key, val))
            for v in inputs:
                p = lit_of(v, True)
                text = (stdin_of(cmd)[1] if p == "-" else self.read_file(p)) if p is not None else None
                if text is None:
                    return None
                try:
                    obj = json.loads(text)
                except ValueError:
                    obj = None
                if isinstance(obj, dict):
                    out += [(str(k), json.dumps(v) if not isinstance(v, str) else v) for k, v in obj.items()]
                else:
                    out.append(("<input>", text))
            return out

        if ep == "graphql":
            texts = field_texts()
            if texts is None:
                return ctx.act("refwrite", "gh api graphql whose query cannot be read")
            q = "\n".join(v for _, v in texts)
            if re.search(r"mergePullRequest|enablePullRequestAutoMerge|mergeBranch|updateRefs?\b|deleteRef|createRef|"
                         r"createCommitOnBranch|(update|delete)BranchProtectionRule|(update|delete)Ruleset", q, re.I):
                ctx.act("refwrite", "gh api graphql merge/ref mutation")
            if re.search(r"addLabelsToLabelable|labelIds|updateLabel", q, re.I):
                ctx.act("promote", "gh api graphql label mutation (label ids cannot be checked)")
            if IS_SUB and re.search(r"PullRequestReview|addComment|IssueComment", q, re.I) and ROBOT_RE.search(q):
                ctx.act("forge", "gh api graphql review or comment with the gate header")
            return
        if not write:
            return
        if input_args:
            return ctx.act("refwrite", "gh api %s %s with xargs/find/parallel input" % (method, ep))
        m = re.search(r"(^|/)pulls/([^/]+)/merge$", ep)
        if m:
            num = m.group(2)
            return ctx.act("merge", {"target": num if num.isdigit() else "", "repo": repo, "admin": False,
                                     "cwd": ctx.cwd, "env": {},
                                     "why": "" if num.isdigit() else "the PR in the endpoint is not a literal number"})
        if re.search(r"(^|/)(merges|merge-upstream)$|(^|/)git/refs/heads/(main|master|[^/]*\0[^/]*)$|"
                     r"(^|/)branches/[^/]+/(protection(/.*)?|rename)$|(^|/)rulesets(/|$)", ep):
            return ctx.act("refwrite", "gh api %s %s" % (method, ep.replace("\0", "<?>")))
        if re.search(r"(^|/)git/refs$", ep):
            texts = field_texts()
            if texts is None or any(k == "ref" and re.search(r"(^|/)(main|master)$", v) for k, v in texts):
                ctx.act("refwrite", "gh api %s %s" % (method, ep))
            return
        if re.search(r"(^|/)contents/", ep):
            texts = field_texts()
            branch = None if texts is None else next((v for k, v in texts if k == "branch"), "")
            if branch is None or re.sub(r"^refs/heads/", "", branch.lower()) in ("", "main", "master"):
                ctx.act("refwrite", "gh api %s %s (a commit on the default branch)" % (method, ep))
            return
        if re.search(r"(^|/)issues(/[^/]+(/labels(/[^/]+)?)?)?$|(^|/)labels/[^/]+$", ep):
            if method == "DELETE":
                return
            texts = field_texts()
            if texts is None:
                return ctx.act("promote", "gh api %s %s whose fields cannot be read" % (method, ep))
            names = [v for k, v in texts if "label" in k.lower() or k in ("name", "new_name", "<input>")]
            if re.search(r"/labels/ready$", ep) or any(re.search(r"(^|[^a-z0-9_-])ready([^a-z0-9_-]|$)", v, re.I)
                                                      for v in names):
                ctx.act("promote", "gh api %s %s" % (method, ep))
            return
        if IS_SUB and re.search(r"(^|/)(pulls/[^/]+/reviews(/[^/]+(/events)?)?|issues/[^/]+/comments|"
                                r"issues/comments/[^/]+|pulls/[^/]+/comments|pulls/comments/[^/]+)$", ep):
            texts = field_texts()
            if texts is None:
                if "/reviews" in ep or ROBOT_RE.search(ctx.raw):
                    ctx.act("forge", "gh api %s %s whose body cannot be read" % (method, ep))
            elif any(k in ("body", "<input>") and v.lstrip().startswith(GATE_PREFIX) for k, v in texts):
                ctx.act("forge", "gh api %s %s with the gate header" % (method, ep))

    # -- git ------------------------------------------------------------------------------------
    def git(self, args, cmd, depth, prefix, input_args, alias_depth=0):
        ctx = self.ctx
        env = dict(ctx.env)
        env.update(prefix)
        gitenv = {}
        for v in TRACKED_ENV:
            if v.startswith("GIT_") and v in env:
                gitenv[v] = lit_of(env[v], True) if env[v] is not None else None
                if env[v] is not None and gitenv[v] is None:
                    return ctx.dark("git with a non-literal %s" % v)
        d = ctx.cwd if ctx.cwd_known else None
        glob, overrides, i, sub = [], [], 0, None
        while i < len(args):
            t = lit_of(args[i])
            if t is None:
                return ctx.dark("a git option or subcommand is not literal", True)
            if t == "-C" or (t.startswith("-C") and len(t) > 2):
                v = (lit_of(args[i + 1], True) if i + 1 < len(args) else None) if t == "-C" else t[2:]
                d = os.path.normpath(os.path.join(d, os.path.expanduser(v))) if (v is not None and d) else None
                i += 2 if t == "-C" else 1
                continue
            if t == "-c":
                v = lit_of(args[i + 1]) if i + 1 < len(args) else None
                if v is None:
                    return ctx.dark("git -c with a non-literal value", True)
                overrides.append(v)
                i += 2
                continue
            if t.startswith("--config-env"):
                ctx.dark("git --config-env")
                i += 1 if "=" in t else 2
                continue
            if t in ("--git-dir", "--work-tree", "--namespace", "--super-prefix", "--exec-path", "--attr-source"):
                v = lit_of(args[i + 1], True) if i + 1 < len(args) else None
                if v is None:
                    return ctx.dark("git %s is not literal" % t)
                glob.append(t + "=" + v)
                i += 2
                continue
            if t.startswith(("--git-dir=", "--work-tree=", "--namespace=")):
                glob.append(t)
            elif not t.startswith("-"):
                sub = t
                i += 1
                break
            i += 1
        if sub is None:
            return
        rest = args[i:]
        for ov in overrides:
            key, _, val = ov.partition("=")
            if EXEC_CONFIG_RE.match(key):
                self.string(val.lstrip("!"), depth + 1)
        cfg = ["git"] + glob
        for ov in overrides:
            if re.match(r"^(alias|remote|push|branch|url)\.", ov, re.I):
                cfg += ["-c", ov]
        base = {"dir": d, "cfg": cfg, "env": gitenv}
        if sub not in GIT_BUILTINS:
            if alias_depth > 3 or d is None:
                return ctx.dark("git %s in an unknown directory, or an alias loop" % sub)
            rc, out = run(cfg + ["config", "--get", "alias." + sub], cwd=d, env_extra=gitenv, timeout=5)
            exp = out.strip() if rc == 0 else ""
            if not exp:
                return ctx.dark("git %s is not a git command or alias" % sub)
            if exp.startswith("!"):
                return self.string(exp[1:] + " " + " ".join(a.text() for a in rest), depth + 1, input_args)
            try:
                words = [w for c in parse(exp, depth + 1) for w in c.words]
            except ParseError:
                return ctx.dark("unparseable git alias")
            return self.git(args[:i - 1] + words + rest, cmd, depth, prefix, input_args, alias_depth + 1)
        lits = [lit_of(a) for a in rest]
        if sub == "push":
            return self.git_push(rest, base, input_args)
        if sub == "send-pack":
            return ctx.act("refwrite", "git send-pack")
        if (sub == "credential" and "fill" in lits) or (sub.startswith("credential-") and "get" in lits):
            return ctx.act("token", "git %s" % sub)
        if sub == "rebase":
            for k, t in enumerate(lits):
                code = lits[k + 1] if t in ("-x", "--exec") and k + 1 < len(lits) else \
                    (t[7:] if t is not None and t.startswith("--exec=") else False)
                if code is None:
                    ctx.dark("git rebase --exec with a non-literal command")
                elif code:
                    self.string(code, depth + 1)
        if sub == "bisect" and lits[:1] == ["run"]:
            self.run_words(rest[1:], cmd, depth, prefix, input_args)
        if sub == "submodule" and "foreach" in lits:
            parts = [t for t in lits[lits.index("foreach") + 1:] if t is None or not t.startswith("--")]
            if None in parts:
                ctx.dark("git submodule foreach with a non-literal command")
            else:
                self.string(" ".join(parts), depth + 1)
        if sub == "filter-branch" or (sub == "difftool" and any((t or "-x").startswith(("-x", "--extcmd"))
                                                                for t in lits)):
            ctx.dark("git %s runs commands" % sub)
        if sub == "config":
            for k, t in enumerate(lits):
                if t in ("-f", "--file") and k + 1 < len(rest):
                    ctx.git_touch(rest[k + 1], "file", d)
                elif t is not None and t.startswith("--file="):
                    ctx.git_touch(Word(t[7:]), "file", d)
        if sub in ("diff", "log", "show", "archive", "format-patch", "bundle"):
            for k, t in enumerate(lits):
                if t in ("-o", "--output", "--output-directory") and k + 1 < len(rest):
                    ctx.git_touch(rest[k + 1], "into", d)
                elif t is not None and t.startswith(("--output=", "--output-directory=")):
                    ctx.git_touch(Word(t.split("=", 1)[1]), "into", d)
        self.git_tree(sub, rest, lits, base, cmd)

    def git_tree(self, sub, rest, lits, base, cmd):
        """git commands that write the working tree: by pathspec (checked as covering the protected
        files), wholesale (denied while a protected file has an uncommitted — the human's — edit),
        or from a patch (whose paths `git apply --numstat` lists)."""
        ctx = self.ctx
        pos = [a for a, t in zip(rest, lits) if t is None or not t.startswith("-")]
        if sub in ("worktree", "clone", "init"):
            for a in pos:
                ctx.git_touch(a, "file", base["dir"])
            return
        if sub == "sparse-checkout" and lits[:1] and lits[0] in ("set", "add", "init", "reapply", "disable"):
            return ctx.act("tamper", "git sparse-checkout can remove protected files from the working tree")
        wholesale = False
        if sub == "stash":
            if lits[:1] and lits[0] in STASH_SUBS:
                return
            if "--" in lits:
                pos = rest[lits.index("--") + 1:]
            else:
                pos = [a for a, t in zip(rest, lits) if t not in ("push", "save")] if lits[:1] == ["push"] else []
                pos = [a for k, a in enumerate(pos) if not (k and lit_of(pos[k - 1]) in ("-m", "--message"))
                       and not (lit_of(a) or "x").startswith("-")]
            wholesale = not pos
        elif sub == "reset":
            pos, wholesale = [], any(t in ("--hard", "--merge", "--keep") for t in lits)
        elif sub in ("checkout", "switch"):
            wholesale = any(t in ("-f", "--force", "--discard-changes") for t in lits)
            if sub == "switch":
                pos = []
            else:
                skip = {k + 1 for k, t in enumerate(lits) if t in ("-b", "-B", "--orphan")}
                pos = [a for k, a in enumerate(rest) if k not in skip and a in pos]
        elif sub == "restore":
            if any(t in ("--staged", "-S") for t in lits) and not any(t in ("--worktree", "-W") for t in lits):
                return
            skip = {k + 1 for k, t in enumerate(lits) if t in ("-s", "--source")}
            pos = [a for k, a in enumerate(rest) if k not in skip and a in pos]
        elif sub == "rm":
            if "--cached" in lits:
                return
        elif sub == "clean":
            wholesale = not pos
        elif sub == "checkout-index":
            wholesale = any(t in ("-a", "--all") for t in lits)
        elif sub == "read-tree":
            pos, wholesale = [], any(t in ("-u", "--reset") for t in lits)
        elif sub in ("apply", "am"):
            return self.git_patch(sub, rest, lits, base, cmd)
        elif sub != "mv":
            return
        for a in pos:
            ctx.git_touch(a, "tree", base["dir"])
        if wholesale:
            dirty = self.dirty_protected(base)
            if dirty is None:
                ctx.touch(None, "unknown")
            elif dirty:
                ctx.act("tamper", "git %s would discard the uncommitted edit of %s" % (sub, ", ".join(dirty)))

    def dirty_protected(self, base):
        """Protected files with uncommitted changes (the human's edits), or None when git can't tell."""
        if base["dir"] is None:
            return None
        rc, out = run(base["cfg"] + ["status", "--porcelain", "-z", "--untracked-files=all", "--"] +
                      [":(top)" + p for p in PROT_FILE_REL], cwd=base["dir"], env_extra=base["env"], timeout=5)
        if rc != 0:
            return None
        return [e[3:] for e in out.split("\0") if len(e) > 3 and e[2] == " "]

    def git_patch(self, sub, rest, lits, base, cmd):
        """git apply / git am: list the patch's paths without applying it."""
        ctx = self.ctx

        def unreadable():
            ctx.dark("git %s of a patch the guard cannot read" % sub, True)

        if sub == "apply" and any(t in ("--stat", "--numstat", "--summary", "--check") for t in lits) and \
                "--apply" not in lits:
            return                                   # read-only forms
        if sub == "am" and any(t in ("--abort", "--quit", "--skip", "--show-current-patch") for t in lits):
            return
        if base["dir"] is None or None in lits or (sub == "am" and any(t in ("--continue", "-r", "--resolved")
                                                                         for t in lits)):
            return unreadable()
        top = run(base["cfg"] + ["rev-parse", "--show-toplevel"], cwd=base["dir"], env_extra=base["env"],
                  timeout=5)[1].strip()
        opts = [t for t in lits if t.startswith(("-p", "--directory="))]
        files = [t for t in lits if not t.startswith("-")]
        sources = [(os.path.join(base["dir"], os.path.expanduser(f)), None) for f in files]
        if not files:
            kind, text = stdin_of(cmd)
            if kind != "text":
                return unreadable()
            sources = [("-", text)]
        for path, text in sources:
            if path != "-" and not os.path.isfile(path):
                return unreadable()
            rc, out = run(base["cfg"] + ["apply", "--numstat", "-z"] + opts + [path], cwd=base["dir"],
                          env_extra=base["env"], timeout=10, stdin_text=text)
            if rc != 0 or not top:
                return unreadable()
            for tok in out.split("\0"):
                name = tok.split("\t", 2)[2] if tok.count("\t") >= 2 else tok
                if name:
                    ctx.touch(Word(name), "file", top)

    def git_cfg(self, base, key, all_values=False):
        if base["dir"] is None:
            return [] if all_values else ""
        rc, out = run(base["cfg"] + ["config", "--get-all" if all_values else "--get", key], cwd=base["dir"],
                      env_extra=base["env"], timeout=5)
        vals = [l.strip() for l in out.splitlines() if l.strip()] if rc == 0 else []
        return vals if all_values else (vals[0] if vals else "")

    def git_push(self, rest, base, input_args):
        ctx = self.ctx
        force = destroy = mirror = allb = dry = False
        why, pos, i = [], [], 0
        while i < len(rest):
            t = lit_of(rest[i], True)
            if t is None:
                why.append("%s is not literal" % rest[i].text()[:40])
            elif t == "--":
                pos.extend(rest[i + 1:])
                break
            elif t.startswith("--"):
                nm, eq, val = t[2:].partition("=")
                if not nm.startswith("no-"):
                    # git accepts any unambiguous prefix of a long option: --force-w, --mirr, --del
                    cand = [x for x in PUSH_LONG if x == nm] or [x for x in PUSH_LONG if x.startswith(nm)]
                    force = force or bool(set(cand) & {"force", "force-with-lease", "force-if-includes"})
                    destroy = destroy or "delete" in cand
                    mirror = mirror or bool(set(cand) & {"mirror", "prune"})
                    allb = allb or bool(set(cand) & {"all", "branches"})
                    dry = dry or cand == ["dry-run"]
                    if len(cand) == 1 and cand[0] in ("repo", "receive-pack", "exec", "push-option"):
                        if cand[0] == "repo":
                            pos.insert(0, Word(val) if eq else (rest[i + 1] if i + 1 < len(rest) else Word("")))
                        i += 0 if eq else 1
            elif t.startswith("-") and len(t) > 1:
                for k, ch in enumerate(t[1:]):              # bundled short flags: -fu, -uf, -nf
                    force = force or ch == "f"
                    destroy = destroy or ch == "d"
                    dry = dry or ch == "n"
                    if ch == "o":
                        i += 1 if k == len(t) - 2 else 0
                        break
            else:
                pos.append(rest[i])
            i += 1
        if dry and not why:
            return
        if input_args:
            why.append("its arguments come from xargs/find/parallel input")
        d = base["dir"]
        if d is None:
            why.append("an earlier `cd` makes the repository unknown")
            cur = ""
        else:
            cur = run(base["cfg"] + ["symbolic-ref", "--short", "-q", "HEAD"], cwd=d, env_extra=base["env"],
                      timeout=5)[1].strip()
        if pos:
            remote = lit_of(pos[0], True) or "?"
        else:
            remote = ""
            for key in ("branch.%s.pushremote" % cur, "remote.pushdefault", "branch.%s.remote" % cur):
                if (cur or not key.startswith("branch.")) and not remote:
                    remote = self.git_cfg(base, key)
            remote = remote or "origin"
        specs = [lit_of(s, True) for s in pos[1:]]
        if None in specs:
            specs = [s for s in specs if s is not None]
        if self.git_cfg(base, "remote.%s.mirror" % remote).lower() in ("true", "yes", "on", "1"):
            mirror = True
        pushcfg = self.git_cfg(base, "remote.%s.push" % remote, True)
        if not specs and not (why or mirror or allb):
            if pushcfg:
                specs = list(pushcfg)
            else:
                mode = (self.git_cfg(base, "push.default") or "simple").lower()
                up = re.sub(r"^refs/heads/", "", self.git_cfg(base, "branch.%s.merge" % cur)) if cur else ""
                if mode == "matching":
                    specs = [":"]
                elif mode in ("upstream", "tracking"):
                    specs = ["%s:%s" % (cur, up)] if cur and up else []
                elif mode == "current":
                    specs = ["%s:%s" % (cur, cur)] if cur else []
                elif mode != "nothing" and cur:                       # simple
                    specs = ["%s:%s" % (cur, cur)] + (["%s:%s" % (cur, up)] if up and up != cur else [])
        hits, skip = [], False
        for r in specs:
            if skip or r == "tag":
                skip = r == "tag"
                continue
            if r.startswith("^"):
                continue
            plus, r = r.startswith("+"), r.lstrip("+")
            if r == ":":                                              # matching branches
                for b in ("main", "master"):
                    if d is not None and run(base["cfg"] + ["rev-parse", "-q", "--verify", "refs/heads/" + b],
                                             cwd=d, env_extra=base["env"], timeout=5)[0] == 0:
                        hits.append((b, b, plus))
                continue
            src, dst = r.split(":", 1) if ":" in r else (r, r)
            if ":" not in r:
                for pc in pushcfg:                                    # remote.<r>.push maps <src>
                    ps, _, pd = pc.lstrip("+").partition(":")
                    if pd and re.sub(r"^refs/heads/", "", ps) == re.sub(r"^refs/heads/", "", r):
                        dst = pd
            src = cur if src in ("HEAD", "@") else src
            dst = re.sub(r"^(refs/heads/|heads/)", "", cur if dst in ("HEAD", "@") else dst)
            if "*" in dst:
                if any(fnmatch.fnmatchcase(b, dst) for b in ("main", "master", "refs/heads/main")):
                    hits.append(("*", "main", plus))
            elif dst in ("main", "master"):
                hits.append((src, dst, plus))
        if not (hits or why or mirror or allb):
            return
        ctx.act("push", {"dir": d, "remote": remote, "force": force or any(h[2] for h in hits),
                         "destroy": destroy or any(h[0] == "" for h in hits), "mirror": mirror, "all": allb,
                         "hits": hits, "why": "; ".join(why), "base": base})

    # -- curl & co ------------------------------------------------------------------------------
    def http(self, name, args):
        ctx, urls, dyn_url, write, i = self.ctx, [], False, False, 0
        while i < len(args):
            t = lit_of(args[i])
            if t is None:
                dyn_url = dyn_url or "://" in args[i].text() or not args[i].tail()
            elif name == "curl" and t in ("-X", "--request"):
                write = write or (lit_of(args[i + 1]) or "?").upper() not in ("GET", "HEAD") if i + 1 < len(args) else write
                i += 1
            elif name == "curl" and t.startswith("-X") and len(t) > 2:
                write = write or t[2:].upper() not in ("GET", "HEAD")
            elif name == "curl" and (t in ("-d", "-F", "-T") or t.startswith(("--data", "--form", "--json",
                                                                              "--upload-file", "-d", "-F", "-T"))):
                write = True
            elif name == "wget" and t.startswith(("--post-data", "--post-file", "--body-data", "--body-file")):
                write = True
            elif name == "wget" and t.startswith("--method"):
                m = t.split("=", 1)[1] if "=" in t else (lit_of(args[i + 1]) if i + 1 < len(args) else "?")
                write = write or (m or "?").upper() not in ("GET", "HEAD")
            elif name not in ("curl", "wget") and (t.upper() in ("POST", "PUT", "PATCH", "DELETE") or
                                                  (re.match(r"^[A-Za-z0-9_.\[\]-]+(:=|=|@)", t) and "://" not in t)):
                write = True
            if t is not None and GITHUB_URL_RE.search(t):
                urls.append(t)
            i += 1
        if write and urls:
            ctx.act("apiwrite", "%s writing to %s" % (name, urls[0][:80]))
        elif write and dyn_url:
            ctx.dark("%s writes to a non-literal URL" % name)


# --- Evaluation ---------------------------------------------------------------------------------
def eval_merge(a):
    global PR
    PR = "-"
    if a.get("why"):
        return block("ci", "merge not checkable: %s" % a["why"],
                     "merge-guard: cannot verify this merge %s %s. Run gh pr merge <number> directly, with literal "
                     "arguments (and --repo when it is not this checkout's repository)." % (DASH, a["why"]))
    target, repo, env = a.get("target") or "", a.get("repo"), a.get("env") or {}
    pr = None
    m = re.match(r"^#?(\d+)$", target)
    if m:
        pr = m.group(1)
    else:
        m = re.match(r"^https?://([^/]+)/([^/]+)/([^/]+)/pull/(\d+)", target)
        if m:
            host = m.group(1).lower()
            pr = m.group(4)
            repo = ("" if host in ("github.com", "www.github.com") else host + "/") + m.group(2) + "/" + m.group(3)
    rflag = ["--repo", repo] if repo else []
    if pr is None:                         # a bare `gh pr merge` or a branch: resolve it the way gh will
        rc, out = run(["gh", "pr", "view"] + ([target] if target else []) + rflag + ["--json", "number", "--jq",
                                                                                     ".number"],
                      cwd=a.get("cwd"), env_extra=env)
        pr = out.strip() if rc == 0 and out.strip().isdigit() else None
    if not pr:
        return block("ci", "could not determine PR number",
                     "merge-guard: could not determine which PR this merges. Pass the PR number explicitly.")
    PR = pr
    if IS_SUB:
        block("gate", "subagent caller (%s)" % AGENT,
              "merge-guard: subagents never merge %s merge authority belongs to the /kmp-forge-next-increment "
              "orchestrator." % DASH)
    if a.get("admin"):
        return block("ci", "--admin bypasses branch protection",
                     "merge-guard: --admin force-merges past branch protection. Never force-merge.")
    rc, out = run(["gh", "pr", "view", pr] + rflag + ["--json", "number,state,headRefOid,statusCheckRollup,reviews"],
                  cwd=a.get("cwd"), env_extra=env)
    try:
        view = json.loads(out) if rc == 0 and out.strip() else None
    except ValueError:
        view = None
    if not isinstance(view, dict):
        return block("ci", "gh pr view failed or timed out (offline? unauthenticated?)",
                     "merge-guard: could not read PR #%s from GitHub. Failing closed." % pr)
    nodes = [n for n in (view.get("statusCheckRollup") or []) if isinstance(n, dict)]
    fails = ("FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE")
    if not nodes:
        return block("ci", "no checks reported",
                     "merge-guard: PR #%s reports no checks. Refusing to merge unverified code." % pr)
    if any((n.get("conclusion") or "") in fails or (n.get("state") or "") in ("FAILURE", "ERROR") for n in nodes):
        return block("ci", "CI red", "merge-guard: PR #%s has failing checks. Fix CI before merging (max 2 fix "
                                     "cycles), or escalate." % pr)
    if any((n.get("state") or "") in ("PENDING", "EXPECTED") or (n.get("status") or "") not in ("", "COMPLETED")
           for n in nodes):
        return block("ci", "CI pending",
                     "merge-guard: PR #%s still has checks in flight. Wait for green before merging." % pr)
    if MODE == "enforce-ci":
        return audit("ALLOW", "CI green (enforce-ci; gate review not evaluated)")
    rc, login = run(["gh", "api", "user", "--jq", ".login"], cwd=a.get("cwd"), env_extra=env)
    login = login.strip() if rc == 0 else ""
    if not login:
        return block("gate", "could not resolve the authenticated GitHub login",
                     "merge-guard: could not resolve which GitHub account posts the gate reviews. Failing closed.")
    mine = [r for r in (view.get("reviews") or []) if isinstance(r, dict) and
            ((r.get("author") or {}).get("login") or "").lower() == login.lower() and
            (r.get("body") or "").startswith(GATE_PREFIX + " ")]
    mine.sort(key=lambda r: r.get("submittedAt") or "")
    if not mine:
        return block("gate", "no %s gate review from %s" % (ROBOT, login),
                     "merge-guard: PR #%s has no '%s' gate review posted by %s. The spec gate (docs PR) or the code "
                     "gate (code PR) must post its verdict before merge." % (pr, GATE_PREFIX, login))
    header = mine[-1]["body"].split("\n")[0].rstrip("\r")
    if ((mine[-1].get("commit") or {}).get("oid") or "") != (view.get("headRefOid") or "-"):
        return block("gate", "newest gate review predates the PR head",
                     "merge-guard: the newest gate review on PR #%s was posted on an older commit %s commits were "
                     "pushed after it. Re-run the gate on the current head." % (pr, DASH))
    if not re.match(r"^PASS([: ]|$)", header.split(" %s " % DASH)[-1]):
        return block("gate", "newest gate review is not PASS",
                     "merge-guard: the newest gate review on PR #%s is not PASS %s it reads: %s. Resolve the findings "
                     "and re-run the gate." % (pr, DASH, header[:120]))
    audit("ALLOW", "CI green + gate PASS on head")


def eval_push(a):
    global PR
    PR = "-"
    if a["why"]:
        return block("ci", "push not checkable: %s" % a["why"],
                     "merge-guard: cannot tell what this push updates %s %s. Push with a literal remote and refspec "
                     "(git push origin <branch>)." % (DASH, a["why"]))
    if a["force"] or a["destroy"] or a["mirror"]:
        return block("ci", "force-push, mirror or delete of main",
                     "merge-guard: refusing to force-push to, mirror over, prune or delete main/master.")
    base, d, remote = a["base"], a["dir"], a["remote"]
    changed = {}                                  # dst -> files the push changes there, or None if unknown
    for src, dst, _ in a["hits"]:
        if src == "*" or run(base["cfg"] + ["rev-parse", "-q", "--verify", "refs/remotes/%s/%s" % (remote, dst)],
                             cwd=d, env_extra=base["env"], timeout=5)[0] != 0:
            changed[dst] = None
            continue
        rc, out = run(base["cfg"] + ["diff", "--no-renames", "--no-ext-diff", "--no-textconv", "--name-only", "-z",
                                     "refs/remotes/%s/%s...%s" % (remote, dst, src), "--"],
                      cwd=d, env_extra=base["env"], timeout=10)
        changed[dst] = [f for f in out.split("\0") if f] if rc == 0 else None
    guard = [f for files in changed.values() for f in (files or []) if f.lower() in GUARD_FILE_REL]
    if guard:
        return block("ci", "push to main changes the guard's files: %s" % " ".join(guard),
                     "merge-guard: this push changes %s on main %s the merge guard's files are the human's to "
                     "commit and push." % (" ".join(guard), DASH))
    if IS_SUB:
        return block("gate", "subagent push to main",
                     "merge-guard: subagents may not push to main %s land changes through a PR that the orchestrator "
                     "merges." % DASH)
    if a["all"] or any(h[0] == "*" for h in a["hits"]):
        return block("gate", "push --all/--branches or a wildcard refspec",
                     "merge-guard: --all/--branches or a wildcard refspec can rewrite main. Push the specific branch "
                     "instead.")
    for dst, files in changed.items():
        if files is None:
            return block("gate", "cannot diff the push against %s/%s" % (remote, dst),
                         "merge-guard: cannot tell what this push changes on %s (no refs/remotes/%s/%s, or git diff "
                         "failed). Run git fetch %s, or land it through a PR." % (dst, remote, dst, remote))
        bad = [f for f in files if not f.startswith("openspec/")]
        if bad:
            shown = " ".join(bad[:3])
            return block("gate", "push to %s touches non-bookkeeping files: %s" % (dst, shown),
                         "merge-guard: only loop bookkeeping (openspec/**) may be pushed straight to %s %s %s must go "
                         "through a PR." % (dst, DASH, shown))
    audit("ALLOW", "bookkeeping-only push to main")


def tamper_hit(ctx):
    """The first guard file a Bash command writes, or None."""
    marked = bool(TAMPER_RE.search(ctx.raw)) or any(TAMPER_RE.search(t) for t in ctx.lits)
    for w, kind, cwd in ctx.touched:
        if w is None:
            if marked:
                return "a command whose targets cannot be read"
            continue
        strict = w.literal(strict=True)
        if strict is not None and (cwd is not None or strict.startswith("/")):
            if protected(strict, cwd or "/", kind if (kind != "into" or marked) else "file"):
                return strict
            continue
        if not marked or kind == "exact":
            continue
        loose = w.literal(strict=False)
        if loose is not None:              # a pattern, ~, or a relative path after an unknown cd
            if maybe_protected(os.path.expanduser(loose) if loose.startswith("~") else loose, False):
                return loose
        elif maybe_protected(w.tail(), not w.tail().startswith("/")):
            return w.text()
    return None


def opaque_hit(ctx):
    if not ctx.opaque:
        return None
    text = ctx.raw + "\n" + "\n".join(ctx.lits)
    hit = [(m[0], m[1]) for m in MARKERS if m[2].search(text)]
    if ctx.structural:
        hit.append(("ci", "gh or git"))
    if IS_SUB and ROBOT_RE.search(text):
        hit.append(("gate", "the gate header"))
    if not hit:
        return None
    return ("ci" if any(h[0] == "ci" for h in hit) else "gate", ", ".join(sorted(set(h[1] for h in hit))),
            "; ".join(ctx.opaque))


def evaluate(actions):
    if MODE_NOTE:
        audit("WARN", MODE_NOTE)
    for kind, x in actions:
        if kind == "merge":
            eval_merge(x)
        elif kind == "push":
            eval_push(x)
        elif kind == "refwrite":
            block("ci", "direct ref write: %s" % x,
                  "merge-guard: writing main through the API (%s) bypasses every gate. Merge through gh pr merge "
                  "<number>." % x)
        elif kind == "apiwrite":
            block("ci", "GitHub API write outside gh: %s" % x,
                  "merge-guard: %s bypasses the guard's checks. Use gh." % x)
        elif kind == "token":
            block("ci", "token or alias: %s" % x,
                  "merge-guard: %s would let commands act on GitHub out of the guard's sight." % x)
        elif kind == "promote":
            block("gate", "applying the ready label (%s)" % x,
                  "merge-guard: only a human applies the 'ready' label %s it puts an issue in the build loop's work "
                  "queue. Create or edit the issue without it and tell the human which issues to promote." % DASH)
        elif kind == "forge":
            block("gate", "subagent posting a gate verdict (%s)" % x,
                  "merge-guard: only the /kmp-forge-next-increment orchestrator posts '%s' gate verdicts, and "
                  "subagent review bodies must be readable (literal or --body-file). Return the verdict in your "
                  "result block instead." % GATE_PREFIX)
        elif kind == "tamper":
            block("ci", "writing protected files (%s)" % x[:120],
                  "merge-guard: the merge guard's files (.claude/hooks/merge-guard.*, .claude/settings*.json) and "
                  "the loop's runbook (openspec/AUTOLOOP.md) are the human's to change, in the enforce modes. Ask "
                  "the user to edit them outside Claude.")
        elif kind == "opaque":
            scope, names, why = x
            block(scope, "unparsed command mentions %s: %s" % (names, why[:200]),
                  "merge-guard: this command mentions %s but cannot be checked (%s). Run the gh/git command directly, "
                  "with literal arguments %s no variables or substitutions in its target, eval, pipes into a shell, "
                  "or inline interpreter code." % (names, why[:160], DASH))


def walk(o, key=""):
    if isinstance(o, dict):
        for k, v in o.items():
            for kv in walk(v, str(k)):
                yield kv
    elif isinstance(o, list):
        for v in o:
            for kv in walk(v, key):
                yield kv
    elif isinstance(o, str):
        yield key, o


def main():
    global AGENT, IS_SUB, SUMMARY, RAW_INPUT
    RAW_INPUT = sys.stdin.buffer.read().decode("utf-8", "replace")
    try:
        data = json.loads(RAW_INPUT)
        if not isinstance(data, dict):
            raise ValueError("not an object")
    except ValueError:
        SUMMARY = RAW_INPUT[:200]
        audit("ERROR", "hook input is not JSON")
        if ENFORCING:
            deny("merge-guard: the hook input is not valid JSON, so this call cannot be checked. Failing closed.")
        return
    tool = str(data.get("tool_name") or "")
    IS_SUB = bool(str(data.get("agent_id") or ""))
    AGENT = re.sub(r"\s+", " ", str(data.get("agent_type") or "subagent")) if IS_SUB else "main"
    cwd = str(data.get("cwd") or "")
    cwd = cwd if cwd and os.path.isdir(cwd) else PROJECT_DIR
    ti = data.get("tool_input") if isinstance(data.get("tool_input"), dict) else {}
    actions = []
    if tool == "Bash":
        command = ti.get("command")
        if not isinstance(command, str) or not command.strip():
            return
        SUMMARY = command
        ctx = Ctx(command, cwd)
        clf = Classifier(ctx)
        try:
            prog = parse(command)
        except ParseError as e:
            ctx.dark("unparseable command (%s)" % e)
            prog = []
        for c, d in flatten(prog):
            clf.cmd(c, d)
        actions = list(ctx.actions)
        hit = tamper_hit(ctx)
        if hit:
            actions.append(("tamper", "bash: %s" % hit))
        dark = opaque_hit(ctx)
        if dark:
            actions.append(("opaque", dark))
    elif tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        path = ti.get("file_path") or ti.get("notebook_path") or ""
        SUMMARY = "%s %s" % (tool, path)
        if isinstance(path, str) and path and protected(path, cwd):
            actions.append(("tamper", "%s %s" % (tool, path)))
    elif tool.startswith("mcp__"):
        lname = tool.lower()
        SUMMARY = "%s %s" % (tool, json.dumps(ti)[:200])
        if "merge" in lname:
            num = next((str(ti[k]) for k in ("pullNumber", "pull_number", "number", "pr") if ti.get(k) is not None), "")
            owner, repo = str(ti.get("owner") or ""), str(ti.get("repo") or "")
            actions.append(("merge", {"target": num if num.isdigit() else "", "cwd": cwd, "env": {}, "admin": False,
                                      "repo": "%s/%s" % (owner, repo) if owner and repo else None,
                                      "why": "" if num.isdigit() else "the MCP merge call names no PR number"}))
        elif re.search(r"push_files|create_or_update_file|delete_file|update_ref|create_ref", lname):
            branch = str(ti.get("branch") or ti.get("ref") or "")
            if re.sub(r"^refs/heads/", "", branch) in ("main", "master"):
                actions.append(("refwrite", "%s on %s" % (tool, branch)))
        elif re.search(r"label.*(create|update|add|write|set|edit)|issue.*(create|update|add|write|set|edit)|"
                       r"(create|update|add|edit).*issue|(add|set).*label", lname):
            # Write tools only (a list filtered by `ready` is a read), and only label-named fields.
            if any(re.search("label", k, re.I) and v.strip().lower() == "ready" for k, v in walk(ti)):
                actions.append(("promote", tool))
        if IS_SUB and re.search(r"review|comment", lname) and \
                any(v.lstrip().startswith(GATE_PREFIX) for _, v in walk(ti)):
            actions.append(("forge", tool))
        if re.search(r"write|edit|create|update|delete|move|rename|copy|put|patch|append|replace|remove|upload|save",
                     lname):
            for k, v in walk(ti):
                if re.search(r"path|file|dest|target|source|dir", k, re.I) and TAMPER_RE.search(v) and \
                        protected(v, cwd, "into"):
                    actions.append(("tamper", "%s %s" % (tool, v)))
                    break
    if actions:
        evaluate(actions)


if __name__ == "__main__":
    try:
        main()
    except Denied:
        pass
    except Exception as e:                       # an internal error fails closed for guard-shaped calls
        audit("ERROR", "internal error: %s: %s" % (type(e).__name__, str(e)[:160]))
        if ENFORCING and re.search(r"merge|push|refs|\.claude|settings|label|ready|token|credential|alias|github",
                                   RAW_INPUT, re.I):
            try:
                deny("merge-guard: internal error while checking this call (%s). Failing closed %s see "
                     ".claude/hooks/merge-guard.log." % (type(e).__name__, DASH))
            except Denied:
                pass
PY

if ! command -v python3 >/dev/null 2>&1; then
  if [ "${MODE}" != log ] && looks_guarded; then
    deny_json "merge-guard: python3 is not installed, so this call cannot be checked. Install python3."
  fi
  exit 0
fi

# The program goes in on fd 3 (stdin carries the hook input): no argv size limit, read as UTF-8.
out=$(printf '%s' "${input}" | python3 -I -S -c \
  'import sys; exec(compile(open(3, encoding="utf-8").read(), "merge-guard", "exec"))' \
  "${PROJECT_DIR}" 3<<<"${GUARD_PY}" 2>/dev/null)
rc=$?
if [ -n "${out}" ]; then
  printf '%s\n' "${out}"
elif [ "${rc}" -ne 0 ] && [ "${MODE}" != log ] && looks_guarded; then
  deny_json "merge-guard: internal error while checking this call (python3 exit ${rc}). Failing closed."
fi
exit 0
