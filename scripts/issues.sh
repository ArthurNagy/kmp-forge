#!/usr/bin/env bash
#
# GitHub Issues as the kmp-forge work queue.
#
# Usage (run from the project root — gh resolves the repo from `origin`):
#   issues.sh labels [--repo OWNER/REPO]
#       Create the workflow labels the queue relies on (ready, in-progress, epic,
#       priority:high, priority:low, no-spec, chore, adr). Idempotent: existing labels are
#       left exactly as they are.
#
#   issues.sh next [--approvers login1,login2] [--repo OWNER/REPO]
#       Pick the issue the build loop works next and print ONE JSON object on stdout.
#       Read-only. The selection rules are code, not model judgment:
#         1. An open `in-progress` issue is resumed first (two of them → "conflict"; one that is no
#            longer workable → "paused", so a half-done slice is never abandoned for another).
#         2. Otherwise the open `ready` issues, minus `epic`s, ordered priority:high →
#            unlabeled → priority:low, then oldest issue number first.
#         3. A candidate is TRUSTED only if its author AND whoever last applied `ready` are the
#            authenticated account (the account the loop runs as) or one of --approvers.
#            Anyone can open an issue on a public repo, and an issue form can auto-apply labels
#            on behalf of its author — so a label alone proves nothing.
#         4. A candidate is BLOCKED while any issue it depends on is still open — the
#            "Depends on" section's #refs plus GitHub's native "blocked by" relationships.
#         5. Its change name (also the spec/ and feat/ branch suffix) is `<issue>-<kebab>`,
#            reusing whatever name an earlier attempt already used (open change dir, remote
#            branch, or a same-repo PR head by an approver with that `<issue>-` prefix), so a
#            crashed increment resumes on the same branches even if the issue title changed since.
#            A `ready` issue whose feat/ PR already merged (a reopened, finished issue) is skipped.
#       Output — one of:
#         {"status":"next","issue":42,"title":"…","slug":"42-add-session-cache","resume":false,
#          "priority":"high|normal|low","preconditions":"…","skipped":[…]}
#         {"status":"empty","skipped":[{"issue":12,"reason":"…"}]}
#         {"status":"paused","issue":42,"title":"…","reason":"…"}   (the in-progress issue can't be
#                                                    worked right now — the loop waits, never starts another)
#         {"status":"conflict","reason":"…"}
#         {"status":"error","reason":"…"}            (exit 1)
#
# Requires: gh (authenticated), git, python3.

set -euo pipefail

die() { echo "issues: $*" >&2; exit 1; }

cmd="${1:-}"
[[ -n "$cmd" ]] || die "usage: issues.sh labels|next [--approvers a,b] [--repo OWNER/REPO]"
shift

REPO=""
APPROVERS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo) REPO="${2:-}"; shift 2 ;;
        --repo=*) REPO="${1#--repo=}"; shift ;;
        --approvers) APPROVERS="${2:-}"; shift 2 ;;
        --approvers=*) APPROVERS="${1#--approvers=}"; shift ;;
        *) die "unknown argument: $1" ;;
    esac
done

command -v gh >/dev/null || die "gh is not installed (brew install gh)"
export GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1

cmd_labels() {
    local -a rflag=()
    [[ -n "$REPO" ]] && rflag=(--repo "$REPO")
    local existing
    existing="$(gh label list ${rflag[@]+"${rflag[@]}"} --limit 500 --json name --jq '.[].name')" \
        || die "could not list labels (is gh authenticated and origin a GitHub repo?)"
    local name color desc
    while IFS='|' read -r name color desc; do
        [[ -n "$name" ]] || continue
        if grep -qixF -- "$name" <<<"$existing"; then
            echo "kept:    $name"
        else
            gh label create "$name" ${rflag[@]+"${rflag[@]}"} --color "$color" --description "$desc" >/dev/null \
                || die "could not create label '$name'"
            echo "created: $name"
        fi
    done <<'LABELS'
ready|0E8A16|Approved for work: the build loop's queue. A human applies this, never Claude.
in-progress|FBCA04|Being worked on (the build loop sets and clears this)
epic|5319E7|Too big for one change: split into slice issues first
priority:high|B60205|Worked before unlabeled issues
priority:low|C5DEF5|Worked after unlabeled issues
no-spec|D4C5F9|feat PR that deliberately ships without an OpenSpec change
chore|FEF2C0|Build, tooling or maintenance work
adr|0052CC|Architecture decision record
LABELS
}

cmd_next() {
    command -v python3 >/dev/null || die "python3 is not installed"
    python3 -I - "$REPO" "$APPROVERS" <<'PY'
import json, os, re, subprocess, sys

repo_arg, approvers_arg = sys.argv[1], sys.argv[2]
api_repo = repo_arg if repo_arg else "{owner}/{repo}"   # gh fills the placeholders from origin
rflag = ["--repo", repo_arg] if repo_arg else []


def out(obj, code=0):
    print(json.dumps(obj))
    sys.exit(code)


def gh(*args, check=True):
    try:
        r = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        raise RuntimeError("gh %s timed out" % " ".join(args[:2]))
    if check and r.returncode != 0:
        raise RuntimeError("gh %s failed: %s" % (" ".join(args[:2]), r.stderr.strip()[:300]))
    return r.stdout if r.returncode == 0 else None


def sections(body):
    """Issue-form bodies render as `### <field label>` blocks; `_No response_` = empty."""
    found, current, buf = {}, None, []
    for line in (body or "").splitlines():
        m = re.match(r"^#{2,3}\s+(.+?)\s*$", line)
        if m:
            if current is not None:
                found[current] = "\n".join(buf).strip()
            current, buf = m.group(1).strip().lower(), []
        elif current is not None:
            buf.append(line)
    if current is not None:
        found[current] = "\n".join(buf).strip()
    return {k: ("" if v == "_No response_" else v) for k, v in found.items()}


def kebab(text, limit=40):
    s = re.sub(r"[^a-z0-9]+", "-", (text or "").lower()).strip("-")
    if len(s) > limit:
        s = s[:limit].rsplit("-", 1)[0] if "-" in s[:limit] else s[:limit]
    return s.strip("-")


def priority(labels):
    names = {l.lower() for l in labels}
    if "priority:high" in names:
        return 0, "high"
    if "priority:low" in names:
        return 2, "low"
    return 1, "normal"


try:
    me = gh("api", "user", "--jq", ".login").strip()
    if not me:
        raise RuntimeError("could not resolve the authenticated GitHub login")
    trusted = {me.lower()} | {a.strip().lower() for a in approvers_arg.split(",") if a.strip()}
    fields = "number,title,body,labels,author"

    def listing(label):
        raw = gh("issue", "list", *rflag, "--state", "open", "--label", label,
                 "--limit", "200", "--json", fields)
        return json.loads(raw or "[]")

    def label_names(issue):
        return [l.get("name", "") for l in issue.get("labels", [])]

    def ready_actor(number):
        raw = gh("api", "repos/%s/issues/%d/timeline" % (api_repo, number), "--paginate",
                 "--jq", '.[] | select(.event == "labeled" and .label.name == "ready") | .actor.login')
        lines = [l for l in (raw or "").splitlines() if l.strip()]
        return lines[-1].strip() if lines else ""

    state_cache = {}

    def is_open(number):
        if number not in state_cache:
            raw = gh("issue", "view", str(number), *rflag, "--json", "state", "--jq", ".state", check=False)
            # Unknown / inaccessible reference → treat as open (blocked) rather than guess it is done.
            state_cache[number] = (raw or "OPEN").strip().upper() != "CLOSED"
        return state_cache[number]

    def open_blockers(issue, secs):
        refs = {int(n) for n in re.findall(r"#(\d+)", secs.get("depends on", ""))}
        native = gh("api", "repos/%s/issues/%d/dependencies/blocked_by" % (api_repo, issue["number"]),
                    "--jq", '.[] | select(.state == "open") | .number', check=False)
        for line in (native or "").splitlines():
            if line.strip().isdigit():
                refs.add(int(line.strip()))
                state_cache[int(line.strip())] = True
        refs.discard(issue["number"])
        return sorted(n for n in refs if is_open(n))

    cache = {"heads": None}

    def existing_names(number):
        """Change names already used for this issue → {"spec": [PR states], "feat": [PR states]}.

        Only names this repo's approvers created count: an open change dir, a branch on origin, or a
        PR head from this repository opened by a trusted account — a fork PR named feat/<n>-x can
        neither rename the change nor wedge the queue with a "conflict"."""
        names = {}
        prefix = "%d-" % number
        changes = os.path.join("openspec", "changes")
        if os.path.isdir(changes):
            for d in os.listdir(changes):
                if d.startswith(prefix) and os.path.isdir(os.path.join(changes, d)):
                    names.setdefault(d, {"spec": [], "feat": []})
        r = subprocess.run(["git", "branch", "-r", "--list", "origin/spec/" + prefix + "*",
                            "origin/feat/" + prefix + "*"], capture_output=True, text=True)
        for line in r.stdout.splitlines():
            m = re.match(r"^\s*origin/(?:spec|feat)/(%s.+)$" % re.escape(prefix), line)
            if m:
                names.setdefault(m.group(1).strip(), {"spec": [], "feat": []})
        if cache["heads"] is None:
            raw = gh("pr", "list", *rflag, "--state", "all", "--limit", "500",
                     "--json", "headRefName,state,isCrossRepository,author")
            cache["heads"] = [p for p in json.loads(raw or "[]")
                              if not p.get("isCrossRepository")
                              and (p.get("author") or {}).get("login", "").lower() in trusted]
        for pr in cache["heads"]:
            m = re.match(r"^(spec|feat)/(%s.+)$" % re.escape(prefix), pr["headRefName"])
            if m:
                names.setdefault(m.group(2), {"spec": [], "feat": []})[m.group(1)].append(pr.get("state", ""))
        return names

    def slug_for(issue, secs):
        """→ (slug, in_flight, implemented)."""
        names = existing_names(issue["number"])
        if len(names) > 1:
            raise LookupError("issue #%d has several change names in flight: %s (use one name for the "
                              "OpenSpec change and its spec/ + feat/ branches)"
                              % (issue["number"], ", ".join(sorted(names))))
        if names:
            name, prs = names.popitem()
            return name, True, "MERGED" in prs["feat"]
        hint = secs.get("change name", "").strip().strip("`").strip()
        if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", hint or ""):
            hint = kebab(issue.get("title", ""))
        return "%d-%s" % (issue["number"], hint or "change"), False, False

    skipped = []

    def vet(issue):
        """Return a skip reason, or None when the issue may be worked."""
        labels = {l.lower() for l in label_names(issue)}
        if "epic" in labels:
            return "epic: split it into slice issues"
        if "ready" not in labels:
            return "not labeled ready (paused or not yet approved)"
        author = (issue.get("author") or {}).get("login", "")
        if author.lower() not in trusted:
            return "author @%s is not an approver: re-file it as your own issue to queue it" % author
        actor = ready_actor(issue["number"])
        if actor.lower() not in trusted:
            return "`ready` was applied by @%s, who is not an approver" % (actor or "unknown")
        blockers = open_blockers(issue, sections(issue.get("body", "")))
        if blockers:
            return "blocked by open " + ", ".join("#%d" % n for n in blockers)
        return None

    def result(issue, slug, resume, secs):
        return {
            "status": "next",
            "issue": issue["number"],
            "title": issue.get("title", ""),
            "slug": slug,
            "resume": resume,
            "priority": priority(label_names(issue))[1],
            "preconditions": secs.get("needs a human first", ""),
            "skipped": skipped,
        }

    in_progress = listing("in-progress")
    if len(in_progress) > 1:
        out({"status": "conflict", "reason": "several open issues carry in-progress: "
             + ", ".join("#%d" % i["number"] for i in in_progress)
             + " (the loop works one at a time; remove the label from all but one)"})
    for issue in in_progress:
        # The loop's current slice. If it can't be worked right now (a human removed `ready`, a
        # dependency reopened, …) the loop must wait — starting another issue would leave two
        # half-done slices and two `in-progress` labels.
        reason = vet(issue)
        if reason is not None:
            out({"status": "paused", "issue": issue["number"], "title": issue.get("title", ""),
                 "reason": reason + " — relabel it `ready` to resume, or remove `in-progress` to drop it"})
        secs = sections(issue.get("body", ""))
        try:
            slug, _, _ = slug_for(issue, secs)
        except LookupError as e:
            out({"status": "conflict", "reason": str(e)})
        out(result(issue, slug, True, secs))

    ready = listing("ready")
    ready.sort(key=lambda i: (priority(label_names(i))[0], i["number"]))
    for issue in ready:
        reason = vet(issue)
        if reason is None:
            secs = sections(issue.get("body", ""))
            try:
                slug, in_flight, implemented = slug_for(issue, secs)
            except LookupError as e:
                out({"status": "conflict", "reason": str(e)})
            if not implemented:
                out(result(issue, slug, in_flight, secs))
            # Its code PR already merged and the loop isn't mid-increment on it: a human reopened a
            # finished issue. Resuming would just close it again — new work needs a new issue.
            reason = "already implemented (feat/%s merged): file a new issue for further changes" % slug
        skipped.append({"issue": issue["number"], "reason": reason})

    out({"status": "empty", "skipped": skipped})
except RuntimeError as e:
    out({"status": "error", "reason": str(e)}, 1)
PY
}

case "$cmd" in
    labels) cmd_labels ;;
    next) cmd_next ;;
    *) die "unknown command: $cmd (expected labels|next)" ;;
esac
