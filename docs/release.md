# Release

## Versioning

**SemVer.** Tag format `v<major>.<minor>.<patch>`.

- **Major**: breaking API or behavior change
- **Minor**: new feature, additive only
- **Patch**: bug fix, perf, docs

Conventional Commits drive the bump:
- `BREAKING CHANGE:` footer or `<type>!:` → major
- `feat:` → minor
- `fix:` / `perf:` → patch
- `chore:` / `docs:` / `test:` / `ci:` / `build:` / `refactor:` / `style:` → no version bump (still appear in changelog)

## Tagging

```
git tag -a v0.3.0 -m "Release v0.3.0"
git push origin v0.3.0
```

Tag push triggers `.github/workflows/release.yml`.

## Distribution tiers

### v1 default: GitHub Release artifacts

Every `v*` tag publishes a GitHub Release with auto-generated changelog (via `git-cliff`) and artifacts attached:
- Android: `app-release.apk` + `app-release.aab`
- iOS: `.ipa` (when iOS opted in)
- Desktop: `.dmg` (mac), `.exe`/`.msi` (win), `.deb`/`.AppImage` (linux) — when desktop opted in
- Web: zipped `composeApp/build/distributions/` bundle — when web opted in

Users install by downloading from the Releases page. No store presence. Zero infra cost. Good for OSS distribution, internal tools, early-stage personal projects.

### Beta tier (opt-in): Firebase App Distribution

Adds a job to `release.yml`:

```yaml
firebase-android:
  needs: android
  runs-on: ubuntu-latest
  steps:
    - uses: actions/download-artifact@v4
      with: { name: android }
    - uses: wzieba/Firebase-Distribution-Github-Action@v1
      with:
        appId: ${{ secrets.FIREBASE_APP_ID_ANDROID }}
        serviceCredentialsFileContent: ${{ secrets.FIREBASE_SERVICE_ACCOUNT_JSON }}
        groups: testers
        file: app-release.apk
        releaseNotesFile: RELEASE_NOTES.md
```

Same for iOS using the `.ipa`. Testers get an email + Firebase install link.

### Store tier (opt-in): gradle-play-publisher + Apple CLI

**Android — `gradle-play-publisher`** (no Ruby/fastlane needed):

`build.gradle.kts`:
```kotlin
plugins {
    id("com.github.triplet.play") version "3.10.1"
}
play {
    serviceAccountCredentials.set(file(System.getenv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")))
    track.set("internal") // or "alpha", "beta", "production"
}
```

CI step:
```yaml
- run: ./gradlew publishReleaseBundle --track=${{ inputs.track || 'internal' }}
  env:
    GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: ${{ runner.temp }}/play-sa.json
```

Decode the JSON from `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` secret beforehand.

**iOS — Apple CLI** (no fastlane):

```yaml
- name: Validate
  run: xcrun altool --validate-app -f $IPA_PATH -t ios --apiKey $KEY_ID --apiIssuer $ISSUER_ID
- name: Upload
  run: xcrun altool --upload-app -f $IPA_PATH -t ios --apiKey $KEY_ID --apiIssuer $ISSUER_ID
```

API key (`.p8`) reconstructed from `APP_STORE_CONNECT_API_KEY_CONTENT` secret to `~/private_keys/AuthKey_<KEY_ID>.p8` before `altool` runs.

For notarization of a macOS desktop build: `xcrun notarytool submit ... --wait`.

### When to add fastlane

Only when you need:
- Automated screenshot generation across devices/locales
- Bulk metadata + store listing management
- Match (cert sharing across machines)

For solo personal projects, you almost never need it. `gradle-play-publisher` + Apple CLI cover release uploads cleanly.

## Keystore policy

**Never commit the keystore.** Never commit `signing.properties`. Never commit `.env*` files.

Local:
- Generate keystore once with `keytool -genkey -v -keystore release.keystore -keyalg RSA -keysize 2048 -validity 25000 -alias release`
- Store at `<projectRoot>/release.keystore` (gitignored) or `~/.android-keystores/<project>.keystore`
- Create `signing.properties` (gitignored):
  ```
  storeFile=release.keystore
  storePassword=...
  keyAlias=release
  keyPassword=...
  ```
- `composeApp/build.gradle.kts` reads it:
  ```kotlin
  val signingProps = Properties().apply {
      file("signing.properties").takeIf { it.exists() }?.inputStream()?.use(::load)
  }
  android {
      signingConfigs {
          create("release") {
              storeFile = signingProps["storeFile"]?.toString()?.let(::file)
                  ?: System.getenv("KEYSTORE_PATH")?.let(::file)
              storePassword = signingProps["storePassword"]?.toString() ?: System.getenv("KEYSTORE_PASSWORD")
              keyAlias = signingProps["keyAlias"]?.toString() ?: System.getenv("KEY_ALIAS")
              keyPassword = signingProps["keyPassword"]?.toString() ?: System.getenv("KEY_PASSWORD")
          }
      }
  }
  ```

CI:
- Encode keystore once: `base64 -i release.keystore | pbcopy`, paste into `ANDROID_KEYSTORE_BASE64` secret
- Workflow decodes to `$RUNNER_TEMP/release.keystore`, sets `KEYSTORE_PATH` env to that path; Gradle picks it up

## Changelog (git-cliff)

`cliff.toml` at repo root:

```toml
[changelog]
header = "# Changelog\n\n"
body = """
{% for group, commits in commits | group_by(attribute="group") %}
### {{ group | upper_first }}
{% for commit in commits %}
- {{ commit.message | upper_first }} ({{ commit.id | truncate(length=7, end="") }})
{% endfor %}
{% endfor %}
"""

[git]
conventional_commits = true
filter_unconventional = false
commit_parsers = [
    { message = "^feat", group = "Features" },
    { message = "^fix", group = "Fixes" },
    { message = "^perf", group = "Performance" },
    { message = "^refactor", group = "Refactor" },
    { message = "^docs", group = "Documentation" },
    { message = "^chore", group = "Chore" },
    { message = "^build", group = "Build" },
    { message = "^ci", group = "CI" },
    { message = "^test", group = "Tests" },
]
```

Release workflow runs `git-cliff --latest --strip header` to populate the GitHub Release body. Full `CHANGELOG.md` regenerated on each release via `git-cliff -o CHANGELOG.md` and committed back to `main` via a follow-up PR (optional — manual is fine for solo work).

## Hotfix flow

1. Branch off `main`: `fix/<urgent>`
2. PR + merge as usual
3. Tag a patch release: `v<current-minor>.<patch+1>`

No `release/*` branch unless you support multiple major versions concurrently.
