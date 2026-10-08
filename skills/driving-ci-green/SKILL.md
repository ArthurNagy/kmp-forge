---
name: driving-ci-green
description: Watch a PR's GitHub Actions checks and drive them to green from the CLI in a kmp-forge-scaffolded project, without flooding the context window with CI logs. Use when watching PR checks after a push, diagnosing a red check, mirroring the CI gate locally before pushing, or when an agent needs the canonical gh commands for CI status and failure logs.
---

# Driving CI green — kmp-forge style

The kmp-forge PR gate lives in `.github/workflows/pr.yml` (rendered from the plugin's `overlay/ci/pr.yml.tmpl`). This skill is the one place that defines how to watch it, read its failures, and mirror it locally. CI logs run to megabytes — every command here is shaped to keep them out of the context window.

## Watch, don't poll

**1. Wait for the checks to register.** Right after `gh pr create` or a push, GitHub has not attached the workflow runs yet, and `gh pr checks` exits **1** with `no checks reported on the '<branch>' branch` — the same exit code as a failed check. Never read that as red. Wait until at least one check exists (bounded, ~3 min):

```bash
for i in $(seq 1 18); do
  n=$(gh pr checks <pr> --json name --jq length 2>/dev/null) && [ "${n:-0}" -gt 0 ] && break
  sleep 10
done; echo "checks registered: ${n:-0}"
```

Still `0` after the loop → the workflow is not triggering (missing `pr.yml`, a path filter, Actions disabled). Report that; do not keep watching.

**2. Watch.**

```bash
gh pr checks <pr> --watch --fail-fast --interval 20 >/dev/null 2>/tmp/ci-watch.err; rc=$?
echo "exit=$rc"; grep -q "no checks reported" /tmp/ci-watch.err && echo "NOT REGISTERED — back to step 1"
```

Run it with a Bash `timeout` of `600000` (10 min). Exit meanings:

- `0` — all checks green.
- `1` — a check failed — **unless** stderr says `no checks reported` (then go back to step 1; nothing failed).
- `8` — checks still pending when the command returned.

If the *Bash call itself* times out, simply re-run it — the checks resume server-side. After 3 such timeouts (~30 min wall), stop and report `CI: timeout` rather than watching forever.

Never busy-poll `gh pr checks` without `--watch`, and never dump its table repeatedly — one wait + one watch per push is the pattern.

## Reading failures without flooding context

`gh run view --log-failed` without a run id is interactive (it prompts you to pick a run) and errors out in a non-interactive session. Resolve the failing run for the PR's head commit first:

```bash
sha=$(gh pr view <pr> --json headRefOid --jq .headRefOid)
run=$(gh run list --commit "$sha" --json databaseId,conclusion \
        --jq '[.[] | select(.conclusion == "failure")][0].databaseId')
gh run view "$run" --log-failed 2>&1 | tail -100
```

Never run `gh run view --log-failed` unpiped. Always `| tail -100`; widen to `tail -300` only if the first 100 lines genuinely do not contain the error. If `$run` is empty, no run on the head commit has failed — re-check `gh pr checks <pr>` (a failing check may come from an external status, not a workflow run).

## Mirror CI locally before pushing

The CI gate (see `overlay/ci/pr.yml.tmpl`) runs, in order: `spotlessCheck`, `detekt`, `build -x test`, `jvmTest`, `koverVerify`. Mirror it locally with the auto-fix variant before every push:

```bash
./gradlew spotlessApply detekt build -x test jvmTest koverVerify 2>&1 | tail -80
```

`spotlessApply` auto-fixes formatting (CI runs the check-only `spotlessCheck`). Iterate until this is clean — a push with a locally-red build wastes a CI cycle. Do not weaken the gate to pass it: no lowering the Kover threshold, no deleting or `@Ignore`-ing a test, no detekt baseline entry or suppression to silence a real finding.

## Context discipline

- Pipe every noisy command: `./gradlew ... 2>&1 | tail -80`.
- `git diff --stat` before `git diff`; prefer reading the specific file a failure names over globbing the module.
- Fix-read cycles happen where the work is: read the failing test/file, fix, re-run the local mirror, push once.

## Fix-cycle budget

Two red-CI fix cycles per PR is the budget: red CI → read failure → fix → push → re-watch, at most twice. Still red after the second cycle? Stop and report the failure precisely (what failed, what you tried) instead of thrashing — a human decision is cheaper than a third blind attempt.
