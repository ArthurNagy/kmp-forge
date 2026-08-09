---
name: driving-ci-green
description: Watch a PR's GitHub Actions checks and drive them to green from the CLI in a kmp-forge-scaffolded project, without flooding the context window with CI logs. Use when watching PR checks after a push, diagnosing a red check, mirroring the CI gate locally before pushing, or when an agent needs the canonical gh commands for CI status and failure logs.
---

# Driving CI green — kmp-forge style

The kmp-forge PR gate lives in `.github/workflows/pr.yml` (rendered from the plugin's `overlay/ci/pr.yml.tmpl`). This skill is the one place that defines how to watch it, read its failures, and mirror it locally. CI logs run to megabytes — every command here is shaped to keep them out of the context window.

## Watch, don't poll

```bash
gh pr checks <pr> --watch --fail-fast --interval 20 >/dev/null 2>&1; echo "exit=$?"
```

Run it with a Bash `timeout` of `600000` (10 min). Exit meanings:

- `0` — all checks green.
- `1` — a check failed.
- any other non-zero (commonly `8`) — checks still pending when the command returned.

If the *Bash call itself* times out, simply re-run it — the checks resume server-side. After 3 such timeouts (~30 min wall), stop and report `CI: timeout` rather than watching forever.

Never busy-poll `gh pr checks` in a loop without `--watch`, and never dump its table repeatedly — one watch call per push is the pattern.

## Reading failures without flooding context

```bash
gh run view --log-failed 2>&1 | tail -100
```

Never run `gh run view --log-failed` unpiped. Always `| tail -100`; widen to `tail -300` only if the first 100 lines genuinely do not contain the error. If several runs exist, target the failing one: `gh run list --branch <branch> --limit 3` then `gh run view <run-id> --log-failed 2>&1 | tail -100`.

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
