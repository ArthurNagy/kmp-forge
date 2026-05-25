# Git conventions

## Branching

**Trunk-based.** `main` is always shippable. No long-lived `develop` or `release/*` branches.

Branch names:
- `feature/<short-name>` — new functionality
- `fix/<short-name>` — bug fix
- `chore/<short-name>` — non-code housekeeping (deps, CI, docs)
- `refactor/<short-name>` — code structure change with no behavior change

Releases come from tags on `main`, not from branches.

## Commits

**Conventional Commits.** Format: `<type>(<scope>): <subject>`.

Allowed types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `build`, `ci`, `perf`, `style`.

Scope is optional but encouraged. Use module name (`gallery`, `auth`) or area (`ci`, `release`).

Examples:
- `feat(gallery): add multi-select bulk action`
- `fix(auth): reset token expiry on refresh`
- `chore: bump kotlin to 2.2.20`
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
- <one to three bullets answering WHY, not what>

## Screenshots / GIFs
<required for UI changes; before/after>
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

See [ci.md § Branch protection setup](ci.md#branch-protection-setup).

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

`.gitleaks.toml` at repo root with default rules.

Hook at `.git/hooks/pre-commit`:

```bash
#!/usr/bin/env bash
set -euo pipefail
if ! command -v gitleaks >/dev/null; then
    echo "gitleaks not installed; install via brew install gitleaks"
    exit 0
fi
gitleaks protect --staged --config .gitleaks.toml
```

Mark executable: `chmod +x .git/hooks/pre-commit`.

`/kmp-forge-init` installs the hook automatically when git init is opted in.

### Server-side (GitHub)

Enable in repo Settings → Code security and analysis:
- ✅ Secret scanning
- ✅ Push protection

GitHub blocks pushes containing detected secrets and surfaces alerts for already-pushed ones.

## Commit signing

Not required by this blueprint. Enable per-project if you prefer signed commits — no impact on workflows.
