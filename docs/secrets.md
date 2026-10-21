# Secrets

## Principles

1. Never commit secrets. Never amend a commit that accidentally added one — rotate the secret instead.
2. Local secrets live in **gitignored** files. CI secrets live in **GitHub Actions Secrets**.
3. Both client-side (gitleaks) and server-side (GitHub Push Protection) scanning. Belt + suspenders.

## What counts as a secret

- Signing keystores and keystore passwords
- API keys (Sentry DSN, Firebase, Maps, third-party services)
- OAuth client secrets
- Service account JSON files (Google Play, Firebase)
- App Store Connect API key (`.p8` private key)
- Any token or credential the app uses to authenticate

## Local layout

```
<projectRoot>/
├── release.keystore          ← gitignored
├── signing.properties        ← gitignored
├── .env.local                ← gitignored
└── google-services.json      ← gitignored (Firebase config; treat as secret-ish)
```

### `signing.properties`

```properties
storeFile=release.keystore
storePassword=<password>
keyAlias=release
keyPassword=<password>
```

Read by `androidApp/build.gradle.kts`:

```kotlin
val signingProps = Properties().apply {
    file("signing.properties").takeIf { it.exists() }?.inputStream()?.use(::load)
}
```

### `.env.local`

Runtime keys consumed at build time (compile-time `BuildConfig`):

```
SENTRY_DSN=https://...
API_BASE_URL=https://api.example.com
```

Loaded by a small Gradle task that emits a `BuildConfig`-like Kotlin object in `:shared`:

```kotlin
val envFile = file(".env.local")
val env = if (envFile.exists()) envFile.readLines().filter { it.contains("=") }
    .associate { it.substringBefore("=").trim() to it.substringAfter("=").trim() }
else emptyMap()

tasks.register("generateAppBuildConfig") {
    val out = file("src/commonMain/kotlin/AppBuildConfig.kt")
    doLast {
        out.writeText("""
            object AppBuildConfig {
                const val sentryDsn = "${env["SENTRY_DSN"].orEmpty()}"
                const val apiBaseUrl = "${env["API_BASE_URL"].orEmpty()}"
                const val versionName = "${project.findProperty("versionName") ?: "0.0.0"}"
                const val isDebug = ${gradle.startParameter.taskNames.any { "debug" in it.lowercase() }}
            }
        """.trimIndent())
    }
}
tasks.named("preBuild").configure { dependsOn("generateAppBuildConfig") }
```

`AppBuildConfig.kt` itself is **gitignored** since it contains injected values. Add it to `.gitignore`:

```
shared/src/commonMain/kotlin/AppBuildConfig.kt
```

## CI secrets

Stored at: GitHub repo → Settings → Secrets and variables → Actions.

| Secret | Encoding | Purpose |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | base64 of `release.keystore` | Decoded to `$RUNNER_TEMP/release.keystore` at workflow start |
| `ANDROID_KEYSTORE_PASSWORD` | plain | Passed via env to Gradle |
| `ANDROID_KEY_ALIAS` | plain | Passed via env |
| `ANDROID_KEY_PASSWORD` | plain | Passed via env |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | raw JSON | Decoded to file for `firebase` CLI |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | raw JSON | Decoded for `gradle-play-publisher` |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | base64 of `AuthKey_<id>.p8` | Decoded to `~/private_keys/AuthKey_<id>.p8` |
| `APP_STORE_CONNECT_API_KEY_ID` | plain | Passed to `xcrun altool` |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | plain | Passed to `xcrun altool` |
| `SENTRY_DSN` | plain | Injected as env, baked into `AppBuildConfig` at build time |
| `SENTRY_AUTH_TOKEN` | plain | Used by `getsentry/action-release` for symbol upload |

### Encoding keystore for CI

```bash
base64 -i release.keystore | pbcopy
# paste into ANDROID_KEYSTORE_BASE64 secret
```

### Decoding in workflow

```yaml
- name: Decode keystore
  run: echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$RUNNER_TEMP/release.keystore"
  env: { ANDROID_KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }} }
```

Gradle reads `KEYSTORE_PATH=$RUNNER_TEMP/release.keystore` and signs the AAB/APK.

## gitleaks (pre-commit)

`.gitleaks.toml` at the repo root extends gitleaks' default rules. Its allowlist skips only binary files and build
output — text resources stay scanned: a key pasted into `composeResources/values/strings.xml` or a JSON under
`composeResources/files/` ships in every app build, so it's reported like any other file. As shipped:

```toml
[allowlist]
description = "Binary resources and build outputs"
paths = [
    '''(^|/)src/[^/]+/composeResources/drawable[^/]*/[^/]+\.(png|webp|jpe?g|gif|bmp)$''',  # Compose resource images
    '''(^|/)src/[^/]+/composeResources/font[^/]*/[^/]+\.(ttf|otf)$''',                     # Compose resource fonts
    '''(^|/)src/[^/]+/res/(drawable|mipmap)[^/]*/[^/]+\.(png|webp|jpe?g|gif)$''',          # Android launcher icons, images
    '''(^|/)iosApp/(.+/)?[^/]+\.xcassets/.+\.(png|jpe?g|pdf)$''',                          # iOS asset catalogs (app icon, images)
    '''^([^/]+/){0,3}build/''',                                                             # build outputs (a module's build/)
    '''(^|/)gradle/wrapper/gradle-wrapper\.(jar|properties)$''',                            # Gradle wrapper
    '''\.lock$''',                                                                          # lock files
]
regexes = [
    # Secret *names* in workflows, docs and build files (never their values)
    '''ANDROID_KEYSTORE_BASE64''',
    '''ANDROID_KEYSTORE_PASSWORD''',
    '''ANDROID_KEY_ALIAS''',
    '''ANDROID_KEY_PASSWORD''',
    '''APP_STORE_CONNECT_API_KEY_ID''',
    '''APP_STORE_CONNECT_API_KEY_ISSUER_ID''',
    '''APP_STORE_CONNECT_API_KEY_CONTENT''',
    '''FIREBASE_SERVICE_ACCOUNT_JSON''',
    '''GOOGLE_PLAY_SERVICE_ACCOUNT_JSON''',
    '''SENTRY_DSN''',
]
```

A false positive in a text file is silenced on its line with a `gitleaks:allow` comment (`// gitleaks:allow`,
`<!-- gitleaks:allow -->`) or with a narrow path entry — never by allowlisting a whole directory such as
`composeResources/`. The paths match repo-relative, so scan a full tree with `gitleaks dir . --config .gitleaks.toml`
from the repo root.

The hook ships as `.kmp-forge-pre-commit.sh` (committed, so a fresh clone can reinstall it) and `/kmp-forge-init`
copies it to `.git/hooks/pre-commit` (executable):

```bash
#!/usr/bin/env bash
# Installed at .git/hooks/pre-commit by /kmp-forge-init.
# Set SKIP_GITLEAKS=1 to bypass for an emergency commit (rotate any leaked secret afterward).
set -euo pipefail

if [[ "${SKIP_GITLEAKS:-}" == "1" ]]; then
    exit 0
fi

if ! command -v gitleaks >/dev/null; then
    echo "warning: gitleaks not installed; install with: brew install gitleaks"
    echo "         skipping secret scan for this commit."
    exit 0
fi

gitleaks protect --staged --config .gitleaks.toml --no-banner --redact
```

Reinstall after a clone: `cp .kmp-forge-pre-commit.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit`.

## GitHub server-side scanning

Enable in repo Settings → Code security and analysis:

- ✅ **Secret scanning** — alerts on detected secrets in repo + history
- ✅ **Push protection** — blocks the push if a secret is detected at push time

These are free for public repos and included in GitHub Advanced Security for private repos.

## What to do when a secret leaks

1. **Rotate the secret immediately** at its source (regenerate API key, change password, generate new keystore).
2. Force-push history rewrite is *not* enough — GitHub keeps unreferenced commits accessible via the API for some time; rotation is the only real fix.
3. Audit access logs (Sentry, Firebase, Google Play) for unauthorized use during the exposure window.
4. Document the incident in `docs/DECISIONS/NNNN-secret-rotation.md` (date, secret type, scope, remediation).

## Don't put in CLAUDE.md or docs/

Per-project CLAUDE.md mentions *which* secrets exist (e.g. "Sentry DSN required") but never the secrets themselves. Docs reference secret *names* (`SENTRY_DSN`), never values.
