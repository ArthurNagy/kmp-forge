---
name: git-cliff-changelog
description: Configure and run git-cliff to generate CHANGELOG.md and GitHub Release bodies from Conventional Commits in kmp-forge-scaffolded projects. Use when setting up changelog automation, releasing a new version, or troubleshooting changelog output.
---

# git-cliff — kmp-forge changelog

[git-cliff](https://git-cliff.org/) is a small Rust binary that parses Conventional Commits and generates a `CHANGELOG.md` / release body. It's our changelog tool by default for kmp-forge projects.

## Why git-cliff over release-please

- Single binary, no continuously-open Release PR cluttering the timeline.
- Runs in CI at tag-push time, not on every merge.
- Solo-friendly: you cut a release when you're ready, not on a treadmill.

## Install (local, for testing)

```bash
brew install git-cliff
```

## Project setup

`cliff.toml` ships at project root via the kmp-forge overlay. Verify it has:

```toml
[git]
conventional_commits = true
filter_unconventional = false
tag_pattern = "v[0-9]+.[0-9]+.[0-9]+"
sort_commits = "newest"
commit_parsers = [
    { message = "^Merge (pull request|branch|remote-tracking branch) ", skip = true },
    { message = "^feat", group = "Features" },
    # … fix → Fixes, chore → Chore, etc. …
    { message = "^[Rr]evert", group = "Reverts" },
    { message = ".*", group = "Other" },
]
```

Full template: see `overlay/root/cliff.toml`.

## Use cases

### Generate the latest release notes only (release.yml does this)

```bash
git cliff --latest --strip header
```

Pipes into `softprops/action-gh-release@v3` as the `body` input.

### Regenerate the full CHANGELOG.md (occasional)

```bash
git cliff -o CHANGELOG.md
```

Commit the result with `docs(changelog): regenerate`. Some projects re-commit `CHANGELOG.md` on every release; some let CI handle release-only generation. For solo projects, regenerating manually before each release is simplest.

### Preview what's coming in the next release

```bash
git cliff --unreleased
```

Shows everything since the last tag. Useful before deciding the semver bump.

## Categorization

The default `commit_parsers` map:

| Prefix | Group |
|---|---|
| `feat` | Features |
| `fix` | Fixes |
| `perf` | Performance |
| `refactor` | Refactor |
| `docs` | Documentation |
| `chore` | Chore |
| `build` | Build |
| `ci` | CI |
| `test` | Tests |
| `style` | Style |
| `revert:` or git's default `Revert "…"` | Reverts (rendered with the full subject, e.g. `Revert "fix: retry upload"`) |
| anything else (non-conventional) | Other |
| `Merge pull request …` / `Merge branch …` | **skipped on purpose** — the PR's own commits (merge workflow) or its squash commit already carry the entry |

Nothing is dropped silently: a non-conventional subject still reaches the notes under **Other**, where it's visible in review.

## Breaking changes

Commits with `BREAKING CHANGE:` footer or `<type>!:` get a **BREAKING** suffix in the generated entry. The `cliff.toml` template shipped by kmp-forge handles this automatically.

Example output:

```
### Features
- feat(gallery): add multi-select (abc1234) **BREAKING**
- feat(auth): support 2FA (def5678)
```

## Release flow

1. `git cliff --unreleased` to preview
2. Decide semver bump (major / minor / patch based on commits)
3. `git tag -a v0.3.0 -m "Release v0.3.0"`
4. `git push origin v0.3.0` → triggers `.github/workflows/release.yml`
5. CI generates release body via `orhun/git-cliff-action@v4` + uploads artifacts

## Troubleshooting

- **Empty changelog**: tag pattern doesn't match. Check `tag_pattern` in `cliff.toml`.
- **Commits missing**: only merge commits are skipped (by the first parser). If a commit you expected is absent, check it isn't before the previous tag (`git describe --tags`). If it shows under **Other**, its subject isn't a Conventional Commit — reword it before merging next time (rebase + force-push if still unmerged).
- **Old tag pulled into "latest"**: git-cliff needs `fetch-depth: 0` in the checkout step. Workflow ships with that already.

## kmp-forge convention

The shipped `release.yml` runs `git cliff --latest --strip header` only — does not auto-update `CHANGELOG.md` in the repo. Maintainer commits CHANGELOG updates manually if they care about a committed file. The GitHub Release body always reflects the latest generated content.
