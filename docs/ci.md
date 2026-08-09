# CI / GitHub Actions

## Workflows

Every scaffolded project ships with two workflows:

### `.github/workflows/pr.yml`

Runs on every PR to `main`. Required by branch protection.

```yaml
name: PR
on:
  pull_request:
    branches: [main]

concurrency:
  group: pr-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-jvm:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: 'temurin', java-version: '17' }
      - uses: gradle/actions/setup-gradle@v3
      - run: ./gradlew spotlessCheck
      - run: ./gradlew detekt
      - run: ./gradlew build -x test
      - run: ./gradlew jvmTest
      - run: ./gradlew koverVerify

  build-ios:
    if: ${{ vars.IOS_ENABLED == 'true' }}
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: 'temurin', java-version: '17' }
      - uses: gradle/actions/setup-gradle@v3
      - run: ./gradlew :shared:linkReleaseFrameworkIosSimulatorArm64
```

(Abridged — the canonical template is `overlay/ci/pr.yml.tmpl`, which also uploads the Kover report as an artifact.)

- **Ubuntu** for everything that doesn't need Xcode (cheap).
- **macOS** only when iOS is enabled (expensive — gate on the `IOS_ENABLED` repository variable).
- Gradle build cache is enabled by `gradle/actions/setup-gradle@v3` automatically (writes to GitHub Actions cache).
- `concurrency` cancels older PR runs when the user pushes new commits.
- **Driving a PR to green from the CLI** — watching checks, reading failures without dumping logs, mirroring this gate locally — is the plugin's `driving-ci-green` skill.

### `.github/workflows/release.yml`

Runs on `v*` tag push.

```yaml
name: Release
on:
  push:
    tags: ['v*']

jobs:
  android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: actions/setup-java@v4
        with: { distribution: 'temurin', java-version: '17' }
      - uses: gradle/actions/setup-gradle@v3
      - name: Decode keystore
        run: echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > $RUNNER_TEMP/release.keystore
        env: { ANDROID_KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }} }
      - run: ./gradlew :androidApp:bundleRelease :androidApp:assembleRelease
        env:
          KEYSTORE_PATH: ${{ runner.temp }}/release.keystore
          KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
          KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
      - uses: actions/upload-artifact@v4
        with:
          name: android
          path: androidApp/build/outputs/**/*.{aab,apk}

  ios:
    if: ${{ env.IOS_ENABLED == 'true' }}
    runs-on: macos-latest
    # … xcodebuild archive + export — see docs/release.md

  changelog:
    runs-on: ubuntu-latest
    needs: [android]
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: orhun/git-cliff-action@v3
        with: { config: cliff.toml, args: --latest --strip header }
        id: cliff
      - uses: softprops/action-gh-release@v2
        with:
          body: ${{ steps.cliff.outputs.content }}
          files: |
            androidApp/build/outputs/bundle/release/*.aab
            androidApp/build/outputs/apk/release/*.apk
```

- Tag-triggered. Push `v0.1.0` → release builds + GitHub Release with auto-generated body.
- Optional jobs (Firebase App Distribution, `gradle-play-publisher`, App Store upload) added when those tiers are opted in. See [release.md](release.md).

## Runner matrix

| Job | Runner | When |
|---|---|---|
| Spotless (ktlint) + detekt | `ubuntu-latest` | always |
| Kover coverage verify + reports | `ubuntu-latest` | always |
| Common + JVM tests | `ubuntu-latest` | always |
| Android assemble + bundle | `ubuntu-latest` | always |
| iOS framework link | `macos-latest` | iOS opt-in |
| iOS archive + export | `macos-latest` | iOS opt-in, release only |
| Desktop build | `ubuntu-latest` (Linux), `macos-latest` (mac), `windows-latest` (win) | desktop opt-in, release only |
| Web build | `ubuntu-latest` | web opt-in |

macOS minutes are billed at ~10× Linux on private repos. Gate iOS jobs behind explicit env to avoid burning budget when iOS is disabled.

## Code quality + coverage

**Spotless + ktlint** — format + lint. ktlint version pinned in `libs.versions.toml`. Convention plugin applies Spotless to every shared module and configures it to verify `src/**/*.kt` and `*.gradle.kts`. CI runs `./gradlew spotlessCheck`; auto-fix locally via `./gradlew spotlessApply`.

**Detekt** — static analysis (complexity, smells). Convention plugin applies it; config in `detekt.yml` at project root.

**Kover** — JetBrains' KMP-native coverage tool. Convention plugin applies Kover per module. Target coverage **75%**. CI runs `./gradlew koverVerify` against a root-project rule and uploads `koverHtmlReport` + `koverXmlReport` as a workflow artifact.

Add the verify rule to root `build.gradle.kts`:

```kotlin
plugins { alias(libs.plugins.kover) }

dependencies {
    kover(projects.shared)
    kover(projects.domain)
    kover(projects.data)
    kover(projects.ui)
    // kover(projects.featureGallery)  // one per feature module
}

kover {
    reports {
        verify {
            rule {
                bound { minValue.set(75) }
            }
        }
    }
}
```

Adjust the 75 threshold or carve exclusions (`excludes { classes("*Module") }`) if the threshold is too aggressive for early-stage projects.

## Required secrets

| Secret | Purpose | Required when |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | Signing keystore | Android release |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password | Android release |
| `ANDROID_KEY_ALIAS` | Key alias inside keystore | Android release |
| `ANDROID_KEY_PASSWORD` | Key password | Android release |
| `FIREBASE_APP_ID_ANDROID` | App ID for Firebase App Distribution | Beta tier (Android) |
| `FIREBASE_APP_ID_IOS` | App ID for Firebase App Distribution | Beta tier (iOS) |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Service account for Firebase CLI | Beta tier |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Service account for `gradle-play-publisher` | Store tier (Android) |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API key ID | Store tier (iOS) |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | Issuer ID | Store tier (iOS) |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Base64-encoded P8 private key | Store tier (iOS) |
| `SENTRY_AUTH_TOKEN` | Symbol upload | Sentry opt-in |
| `SENTRY_DSN` | Runtime crash reporter DSN | Sentry opt-in |

Document each in repo Settings → Secrets and variables → Actions.

## Branch protection setup

Configure in repo Settings → Branches → Add branch protection rule for `main`:

- ✅ Require a pull request before merging
- ✅ Require status checks to pass before merging — select the PR workflow jobs
- ✅ Require linear history
- ❌ Require signed commits (not enforced by this blueprint)
- ✅ Restrict who can push to matching branches (you only, or empty for solo)

## Build cache

`gradle/actions/setup-gradle@v3` writes to GitHub Actions cache automatically. Cache key uses `gradle/**/*.lockfile`, `**/*.gradle*`, `**/gradle-wrapper.properties`. No further config needed.

For locally-shared cache between projects, configure `~/.gradle/caches/`. No Develocity / Gradle Enterprise needed for personal projects.
