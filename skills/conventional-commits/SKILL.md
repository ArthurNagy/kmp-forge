---
name: conventional-commits
description: This skill should be used in a kmp-forge project (its CLAUDE.md links kmp-forge's docs as its rules) when writing a commit message or PR title — choosing the Conventional Commit type (feat vs fix vs refactor/chore), scope and breaking-change marker, which drive git-cliff release notes, the semver bump and CI's spec-link check on feat PRs — or when reviewing commit-message style against the project's git-cliff config.
---

# Conventional Commits — kmp-forge style

## Format

```
<type>(<scope>): <subject>

[optional body]

[optional footers]
```

## Types

- `feat` — new feature, user-visible
- `fix` — bug fix
- `chore` — housekeeping that isn't build or CI (dependency bumps, config, the release version bump)
- `docs` — docs only
- `refactor` — code change with no behavior change
- `test` — test only
- `build` — build system / Gradle changes
- `ci` — CI workflow changes
- `perf` — performance change
- `style` — formatting only (rare)
- `revert` — reverts an earlier commit (git's `Revert "…"` subject is fine; git-cliff groups both)

## Scope (optional)

A single token: the feature (`gallery`, `photo-detail`), a shared module (`shared`, `ui`, `domain`, `data`,
`testing`), a platform (`android`, `ios`, `desktop`, `web`) or an area (`ci`, `release`, `deps`, `adr`,
`changelog`). Skip it if it doesn't add clarity.

## PR titles and CI

- PR titles follow the same format: squash is the default merge, so the PR title becomes the commit — and the
  changelog entry.
- A `feat:` PR that changes production code (`src/*Main/` in `:shared`, `:ui`, `:domain`, `:data` or a
  `:feature-*`) must carry its OpenSpec change under `openspec/changes/` or `openspec/specs/`, or the `no-spec`
  label — CI's `spec-link` check fails it otherwise. Pick `feat` for user-visible behavior, not to dodge or trigger
  that check.

## Subject

- Imperative mood: "add", "fix", "remove" — not "added", "fixed"
- ≤ 70 chars
- No trailing period
- Lowercase first letter

## Body (optional)

- Explain *why*, not what
- Wrap at 72 chars
- Separated from subject by blank line

## Footers (optional)

- `BREAKING CHANGE: <description>` — drives major semver bump
- `Closes #123` / `Fixes #45` — issue refs
- `Co-Authored-By: ...`

## Breaking changes

Use `!` after type:

```
feat(api)!: drop v1 endpoint surface

BREAKING CHANGE: v1 routes now return 410. Migrate to v2.
```

## Examples

✓ `feat(gallery): add multi-select bulk action`
✓ `fix(auth): reset token expiry on refresh`
✓ `chore(deps): bump kotlin to 2.4.21`
✓ `ci: enable macOS leg for iOS builds`
✓ `refactor(domain): extract OrderSorter from CheckoutUseCase`
✓ `docs(release): document gradle-play-publisher graduation path`

✗ `Added new feature` (no type, past tense)
✗ `feat: stuff` (vague subject)
✗ `Fix.` (no type, ends with period, capitalized)
✗ `feat: ... (refs #45, see also slack convo)` (no rambling subject)

## Semver impact

- `BREAKING CHANGE:` footer or `<type>!:` → major bump
- `feat:` → minor bump
- `fix:` / `perf:` → patch bump
- Everything else → no version bump (still in changelog)

`git-cliff` parses commit messages and generates the changelog at release time based on these prefixes.

## When the rule bends

- Merge commits + revert commits use git's default format — don't fight git.
- Very rarely, a `chore:` commit warrants a body explaining a dependency choice rationale. ADRs are the better place for substantive rationale.

## kmp-forge defaults

Pre-commit hook (gitleaks) doesn't validate commit-message format. Add a commitlint hook per-project if strict enforcement matters; otherwise rely on PR review and `git-cliff`'s tolerance (non-conventional commits are still included in the changelog, just under "Other").
