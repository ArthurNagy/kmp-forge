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
tag_pattern = "v[0-9]+.[0-9]+.[0-9]+"
sort_commits = "newest"

[git.commit_parsers]
# feat → Features, fix → Fixes, chore → Chore, etc.
```

Full template: see `overlay/root/cliff.toml`.

## Use cases

### Generate the latest release notes only (release.yml does this)

```bash
git cliff --latest --strip header
```

Pipes into `softprops/action-gh-release@v2` as the `body` input.

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

Anything that doesn't match falls under "Other" (or is filtered out — config-dependent).

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
5. CI generates release body via `orhun/git-cliff-action@v3` + uploads artifacts

## Troubleshooting

- **Empty changelog**: tag pattern doesn't match. Check `tag_pattern` in `cliff.toml`.
- **Commits missing**: they don't match any `commit_parsers` rule. Either add a parser, or fix the commit message (rebase + force-push if not yet merged).
- **Old tag pulled into "latest"**: git-cliff needs `fetch-depth: 0` in the checkout step. Workflow ships with that already.

## kmp-forge convention

The shipped `release.yml` runs `git cliff --latest --strip header` only — does not auto-update `CHANGELOG.md` in the repo. Maintainer commits CHANGELOG updates manually if they care about a committed file. The GitHub Release body always reflects the latest generated content.
