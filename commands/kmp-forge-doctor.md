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

Expected: a JDK able to run Gradle (17+). The Gradle **daemon** JDK is pinned separately by kmp.new's `gradle/gradle-daemon-jvm.properties` (Zulu 21 by default; Gradle provisions it via foojay if missing) — report it, and note that CI's `setup-java` must match it (`.github/workflows/*.yml`).

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

Expected: the `android-compileSdk` platform from `gradle/libs.versions.toml` (kmp.new: `37`). Remediation: `android sdk install platforms/android-<N>` (Android CLI) or `sdkmanager "platforms;android-<N>"`.

### 3b. Android CLI (optional, recommended)

```bash
command -v android && android --version && android info
```

`android` is Google's Android CLI: emulator management (`android emulator list/start/stop`), install + launch (`android run --apks … --device <serial>`), UI inspection (`android layout`, `android screen capture`) and SDK management (`android sdk install …`). kmp-forge's device-verification steps (docs/testing.md § Running on a device or emulator) use it. If missing, report ⚠ and print the installer for the host (macOS arm64: `curl -fsSL https://dl.google.com/android/cli/latest/darwin_arm64/install.sh | bash`; macOS Intel: `…/darwin_x86_64/install.sh`; Linux: `…/linux_x86_64/install.sh`). Also list attached devices — a **physical** device is the user's phone: never install to it without asking.

### 4. Check Gradle wrapper version + toolchain floor

```bash
./gradlew --version
grep distributionUrl gradle/wrapper/gradle-wrapper.properties
grep -E '^agp *=' gradle/libs.versions.toml
```

Expected: Gradle **≥ 9.8.1** and AGP (`agp`) **≥ 9.4.1** — kmp-forge's floor (`MIN_GRADLE` / `MIN_AGP` in `scripts/apply-overlay.sh`). Below it: ⚠, remediation `bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" pin-toolchain .` (raises both, never downgrades; `--ios` / `--web` also raise the Gradle / Kotlin daemon heaps those targets need).

### 5. Check Kotlin version

Read `gradle/libs.versions.toml` → `[versions] kotlin` (the key kmp.new's catalog owns; build-logic's `kotlin-gradle-plugin` entry references it via `version.ref = "kotlin"`, so both always match).

### 6. Check signing config (if `signing.properties` exists)

- File exists at project root
- Required keys present: `storeFile`, `storePassword`, `keyAlias`, `keyPassword`
- `storeFile` points to an existing file
- Do NOT print any values from `signing.properties` (secret)

### 7. Check git hooks

- `.git/hooks/pre-commit` exists and is executable
- gitleaks binary available on PATH (`command -v gitleaks`)

### 7b. Spec & work workflow (OpenSpec + GitHub issues)

```bash
[[ -d openspec ]] && openspec --version && node --version
grep -q "kmp-forge project rules" openspec/config.yaml 2>/dev/null && echo "kmp-forge rules present"
gh label list --limit 200 --json name --jq '[.[].name] | map(select(. == "ready" or . == "in-progress" or . == "epic" or . == "no-spec"))'
```

- `openspec/` present → `openspec` **≥ 1.14** (kmp-forge's `openspec/config.yaml` rules need it; older CLIs ignore them). Remediation: `brew upgrade openspec` or `npm install -g @fission-ai/openspec@latest` (Node ≥ 20.19). Absent → report "plain docs" (✓, not drift).
- `openspec/config.yaml` without kmp-forge's rules → ⚠, remediation: merge in the plugin's `overlay/openspec/config.yaml.tmpl`.
- The workflow labels (`ready`, `in-progress`, `epic`, `no-spec`, …) missing on the GitHub repo → ⚠, remediation: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/issues.sh" labels` (writes labels to GitHub — say so). Skip when `gh` is unauthenticated or there is no GitHub `origin`.

### 8. Check Compose MP version

Read `gradle/libs.versions.toml` → `[versions] composeMultiplatform` (and `material3`, which kmp.new pins to a build matched to it). Cross-reference with what's compatible with the declared Kotlin version (compose-multiplatform release notes).

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
✓ JDK: Zulu 21.0.8 (Gradle daemon toolchain: Zulu 21)
✓ Xcode: 27.0 (matches expected 16+)
⚠ Android SDK: api-37 expected, found api-36. Install with: android sdk install platforms/android-37
✓ Android CLI: 1.0 (devices: emulator-5554)
✓ Gradle wrapper: 9.8.1 (floor 9.8.1) · AGP 9.4.1 (floor 9.4.1)
✓ Kotlin: 2.4.20
✗ signing.properties: not present. Required for release builds — see docs/secrets.md
✓ git hooks: pre-commit installed, gitleaks on PATH
⚠ OpenSpec: 1.3.1 found, ≥ 1.14 needed for openspec/config.yaml rules. Upgrade: brew upgrade openspec
✓ Issue labels: ready, in-progress, epic, no-spec present
✓ Compose MP: 1.12.1 (compatible with Kotlin 2.4.20)
```

Exit with a summary count of OK / Drift / Missing.

## Notes

- Never modify anything. Diagnostic only.
- Do not run with `--refresh-dependencies` — that's slow and not the purpose.
- Surface remediation commands for each failure (e.g. `brew install gitleaks`, `sdkmanager "platforms;android-36"`).
