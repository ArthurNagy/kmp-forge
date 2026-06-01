---
name: conventional-commits
description: Author Conventional Commits in a kmp-forge-scaffolded project, where git-cliff generates the changelog and GitHub Release notes from commit prefixes. Use when committing changes in such a repo and deciding the correct type/scope and semver impact so the release notes categorize correctly, or when reviewing commit-message style against the project's git-cliff config.
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
- `chore` — housekeeping (deps, CI, build, config)
- `docs` — docs only
- `refactor` — code change with no behavior change
- `test` — test only
- `build` — build system / Gradle changes
- `ci` — CI workflow changes
- `perf` — performance change
- `style` — formatting only (rare)

## Scope (optional)

Use module name (`gallery`, `auth`, `ui`) or area (`ci`, `release`, `deps`). Single token. Skip if it doesn't add clarity.

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
✓ `chore(deps): bump kotlin to 2.2.20`
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
