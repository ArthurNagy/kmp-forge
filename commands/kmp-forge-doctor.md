---
description: Verify local tool versions (JDK, Xcode, Android SDK, Gradle wrapper, Kotlin) against what the project's CLAUDE.md declares.
---

# /kmp-forge-doctor

Diagnostic. Read-only. Surfaces drift between the user's local environment and what the project expects.

## Flow

### 1. Check JDK

```bash
java -version 2>&1
javac -version 2>&1
```

Expected: 17 (or whatever CLAUDE.md / `gradle.properties` / `build-logic/build.gradle.kts` declares).

### 2. Check Xcode (if iOS is enabled)

```bash
xcodebuild -version
xcrun --show-sdk-path
```

Expected: 16.0+ (or per CLAUDE.md / Compose MP requirements).

### 3. Check Android SDK

```bash
ls "$ANDROID_HOME/platforms/" 2>/dev/null
```

Expected: `android-36` (or per `compileSdk` declared in `composeApp/build.gradle.kts`).

### 4. Check Gradle wrapper version

```bash
./gradlew --version
```

Expected: as declared in `gradle/wrapper/gradle-wrapper.properties`.

### 5. Check Kotlin version

Read `gradle/libs.versions.toml` → `kotlinGradlePlugin`. Cross-reference with what's actually applied in `build-logic/build.gradle.kts`.

### 6. Check signing config (if `signing.properties` exists)

- File exists at project root
- Required keys present: `storeFile`, `storePassword`, `keyAlias`, `keyPassword`
- `storeFile` points to an existing file
- Do NOT print any values from `signing.properties` (secret)

### 7. Check git hooks

- `.git/hooks/pre-commit` exists and is executable
- gitleaks binary available on PATH (`command -v gitleaks`)

### 8. Check Compose MP version

Read `gradle/libs.versions.toml` → `composeGradlePlugin`. Cross-reference with what's compatible with declared Kotlin version (compose-multiplatform release notes).

### 9. Optional: `./gradlew tasks` smoke test

Run quickly to verify Gradle can resolve plugins + dependencies:
```bash
./gradlew tasks --offline 2>&1 | tail -20
```

If `--offline` fails (cache empty), try without it.

## Output

Report per-section: ✓ OK / ⚠ Drift (expected vs actual) / ✗ Missing.

Example:
```
✓ JDK: Temurin 17.0.11 (matches expected 17)
✓ Xcode: 16.2 (matches expected 16+)
⚠ Android SDK: api-36 expected, found api-35. Install with: sdkmanager "platforms;android-36"
✓ Gradle wrapper: 8.13
✓ Kotlin: 2.2.20
✗ signing.properties: not present. Required for release builds — see docs/secrets.md
✓ git hooks: pre-commit installed, gitleaks on PATH
✓ Compose MP: 1.10.0 (compatible with Kotlin 2.2.20)
```

Exit with a summary count of OK / Drift / Missing.

## Notes

- Never modify anything. Diagnostic only.
- Do not run with `--refresh-dependencies` — that's slow and not the purpose.
- Surface remediation commands for each failure (e.g. `brew install gitleaks`, `sdkmanager "platforms;android-36"`).
