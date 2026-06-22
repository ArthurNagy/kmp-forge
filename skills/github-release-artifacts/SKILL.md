---
name: github-release-artifacts
description: Configure and ship release artifacts (APK/AAB, .ipa, desktop installers, web bundle) via GitHub Releases on v* tag push for kmp-forge projects. Use when setting up release CI, debugging release uploads, or planning artifact naming.
---

# GitHub Release artifacts — kmp-forge default distribution

The v1 default distribution tier for kmp-forge projects. Zero infra cost. Tag push → release artifacts attached to a GitHub Release with auto-generated body.

## Workflow

`.github/workflows/release.yml` ships with the kmp-forge overlay. Key jobs:

```yaml
on:
  push:
    tags: ['v*']

jobs:
  android:                                # always
  ios:                                    # if vars.IOS_ENABLED == 'true'
  desktop:                                # if desktop opted in (TBD)
  web:                                    # if web opted in (TBD)
  changelog-and-release:                  # creates the GH Release with artifacts
```

## Required GitHub Actions Secrets (Android signing)

| Secret | Encoding | What it is |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | base64 of `release.keystore` | Decoded to `$RUNNER_TEMP/release.keystore` |
| `ANDROID_KEYSTORE_PASSWORD` | plain | Keystore password |
| `ANDROID_KEY_ALIAS` | plain | Key alias inside keystore |
| `ANDROID_KEY_PASSWORD` | plain | Key password |

Encode the keystore once locally:
```bash
base64 -i release.keystore | pbcopy
# paste into ANDROID_KEYSTORE_BASE64 secret
```

## Repository variables (toggles)

Set in repo Settings → Secrets and variables → Actions → Variables:

- `IOS_ENABLED = true` — enables the iOS build leg in PR + release workflows. Default unset → false (Android-only).

## Artifact naming

Default outputs (Gradle tasks in parentheses):

- Android (`:androidApp:bundleRelease` + `:androidApp:assembleRelease`): `androidApp/build/outputs/bundle/release/androidApp-release.aab` + `androidApp/build/outputs/apk/release/androidApp-release.apk`
- iOS (`:shared:linkReleaseFramework*` produces the `Shared` framework consumed by the `iosApp/` Xcode project): `build/ipa/iosApp.ipa`
- Desktop (`:desktopApp:packageReleaseDistributionForCurrentOS`): `desktopApp/build/compose/binaries/main-release/dmg/*.dmg` (macOS) — similar for `.msi`, `.deb` under `main-release/{msi,deb}/`
- Web: `shared/build/distributions/<app>.zip`

The release workflow uploads them as-is. Rename via `gradlew renameRelease`-style task if you want versioned names like `myapp-0.3.0.aab` — not in v0.1.0, but trivial to add.

## Body of the GitHub Release

Auto-populated from `git-cliff`. See [git-cliff-changelog skill](../git-cliff-changelog/SKILL.md).

## When to graduate to Firebase / Play Store / App Store

GitHub Release artifacts are great for:

- OSS distribution to advanced users (they download + install)
- Internal tools where users can sideload
- Early-stage personal projects without store presence

Graduate when:

- You want non-technical users to install
- You need auto-updates on user devices
- You need in-app purchases / subscriptions
- You want review-process discoverability

The opt-in [Firebase App Distribution](../../docs/release.md#beta-tier-opt-in-firebase-app-distribution) and [gradle-play-publisher + App Store Connect API](../../docs/release.md#store-tier-opt-in-gradle-play-publisher--apple-cli) tiers handle that. Both are documented in `docs/release.md` and wired by `/kmp-forge-init` (currently print-note for v0.1.0; full wiring lands in v0.2).

## Troubleshooting

- **`Error: No files found`**: artifact upload step's glob didn't match. Check the actual output path of the Gradle task (`androidApp/build/outputs/...` for APK/AAB, `desktopApp/build/compose/binaries/...` for installers).
- **Signing fails in CI but works locally**: `KEYSTORE_PATH` env not set, or base64-decode produced empty file. Verify secret encoding.
- **`xcrun altool` rejects the build**: usually missing entitlements or invalid provisioning profile. See [docs/ios-troubleshooting.md](../../docs/ios-troubleshooting.md).
- **Release body empty**: `git-cliff` ran but found no matching commits since last tag. Check tag pattern + commit message format.

## Manual release (no CI)

If you need to ship without CI (rare), use `gh` CLI:

```bash
gh release create v0.3.0 \
  --title "v0.3.0" \
  --notes "$(git cliff --latest --strip header)" \
  androidApp/build/outputs/bundle/release/*.aab \
  androidApp/build/outputs/apk/release/*.apk
```
