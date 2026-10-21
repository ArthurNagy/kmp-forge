# Git conventions

## Repository defaults

- Host: **GitHub**.
- Visibility: **private** by default for personal projects. Make public only when you're ready to share publicly. `/kmp-forge-init` creates `--private` when it runs `gh repo create`.
- CLI: install `gh` locally (`brew install gh`); authenticate once with `gh auth login`. The blueprint and most slash commands assume `gh` is on PATH.

## Branching

**Trunk-based.** `main` is always shippable. No long-lived `develop` or `release/*` branches.

Branch names:
- `feat/<short-name>` — new functionality
- `fix/<short-name>` — bug fix
- `chore/<short-name>` — non-code housekeeping (deps, CI, docs)
- `refactor/<short-name>` — code structure change with no behavior change
- `spec/<short-name>` — an OpenSpec docs PR (a proposal under `openspec/changes/`, an archive) — no production code

Issue-driven work uses one name for everything: the OpenSpec change `<issue>-<kebab>` is proposed on
`spec/<issue>-<kebab>` and built on `feat/<issue>-<kebab>` (`fix/…` for a bug) — see
[product-workflow.md](product-workflow.md); the autonomous loop relies on it.

Releases come from tags on `main`, not from branches.

## Commits

**Conventional Commits.** Format: `<type>(<scope>): <subject>`.

Allowed types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `build`, `ci`, `perf`, `style`.

Scope is optional but encouraged. Use module name (`gallery`, `auth`) or area (`ci`, `release`).

Examples:
- `feat(gallery): add multi-select bulk action`
- `fix(auth): reset token expiry on refresh`
- `chore: bump kotlin to 2.4.21`
- `ci: enable macOS leg for iOS builds`

Breaking changes get a `!` after the type and a `BREAKING CHANGE:` footer:

```
feat(api)!: drop v1 endpoint surface

BREAKING CHANGE: v1 routes return 410. Migrate to v2 (see docs/api-v2.md).
```

This drives semver: `BREAKING CHANGE` → major bump, `feat` → minor, `fix`/`perf` → patch.

## Pull requests

PR template at `.github/pull_request_template.md`:

```markdown
## Summary
- <!-- 1–3 bullets answering WHY, not what -->

Fixes #<!-- issue number: merging closes it -->

<!-- OpenSpec: a feat: PR that changes production code carries its change under
     openspec/changes/<name>/ (or its ticked tasks.md), or the `no-spec` label. -->

## Screenshots / GIFs
<!-- required for UI changes; before/after -->
```

PR titles follow Conventional Commits (the squash-merge commit message inherits from the PR title).

## Merge strategy

**Linear history.** Squash or rebase only — no merge commits.

Default: squash. Rebase when commits in the PR are individually meaningful and worth preserving (rare).

## Branch protection

Configure on `main`:

- Require pull request before merging
- Require status checks (`pr.yml` jobs) to pass
- Require linear history
- (Solo project): no review requirement; CI is the gate
- (Multi-contributor): require 1 approving review

With the autonomous loop, the account `gh` is authenticated as needs a bypass for its bookkeeping pushes to `main`
(steering files, archives) — see [autoloop.md § Branch protection](autoloop.md#branch-protection). See
[ci.md § Branch protection setup](ci.md#branch-protection-setup).

## .gitignore

Standard KMP entries (in `overlay/root/.gitignore.tmpl`):

```
# Build
.gradle/
build/
.kotlin/
local.properties

# IDE
.idea/
*.iml

# OS
.DS_Store

# Xcode / iOS
xcuserdata/
*.xcuserstate
iosApp/build/
iosApp/Pods/

# Secrets
*.keystore
*.jks
signing.properties
.env
.env.*.local
google-services.json
GoogleService-Info.plist

# Fastlane artifacts (if added)
fastlane/report.xml
fastlane/Preview.html
fastlane/screenshots/
fastlane/test_output/

# Web
kotlin-js-store/
```

## Secret scanning

Both client-side and server-side. Belt + suspenders.

### Pre-commit (gitleaks)

`.gitleaks.toml` at the repo root extends gitleaks' default rules; its allowlist skips only binary resources (images
and fonts under `composeResources/`, Android `res/` images, iOS asset-catalog images), build output, the Gradle
wrapper and lock files — `composeResources/values/strings.xml`, `composeResources/files/` and every other text file
are scanned. The hook, `.kmp-forge-pre-commit.sh`, runs
`gitleaks protect --staged --config .gitleaks.toml --no-banner --redact` (`SKIP_GITLEAKS=1` bypasses it for an
emergency commit). `/kmp-forge-init` copies it to `.git/hooks/pre-commit` when git init is opted in; after a fresh
clone: `cp .kmp-forge-pre-commit.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit`.

Both files, verbatim: [secrets.md § gitleaks](secrets.md#gitleaks-pre-commit).

### Server-side (GitHub)

Enable in repo Settings → Code security and analysis:
- ✅ Secret scanning
- ✅ Push protection

GitHub blocks pushes containing detected secrets and surfaces alerts for already-pushed ones.

## Commit signing

Not required by this blueprint. Enable per-project if you prefer signed commits — no impact on workflows.
