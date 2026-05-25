# iOS troubleshooting

The most common KMP-on-iOS failure modes and how to fix them.

## Tool versions

Pin these in `CLAUDE.md` and verify with `/kmp-forge-doctor`:

- **Xcode**: 16.0+ (or whatever Compose MP requires; check JetBrains release notes for current Compose MP version)
- **JDK**: 17 (Temurin)
- **Kotlin**: 2.2.20+
- **Compose Multiplatform**: 1.10+
- **AGP**: 8.13+
- **Android SDK**: 36 (compileSdk + targetSdk)

Run `xcodebuild -version`, `java -version`, `./gradlew --version` to verify.

## Framework integration

`composeApp` exports a Kotlin/Native static framework named `ComposeApp` consumed by `iosApp/iosApp.xcodeproj`.

### `composeApp/build.gradle.kts`

```kotlin
kotlin {
    listOf(iosArm64(), iosSimulatorArm64()).forEach {
        it.binaries.framework {
            baseName = "ComposeApp"
            isStatic = true
        }
    }
}
```

### Xcode build phase

The Xcode project has a "Run Script" build phase that invokes Gradle to build/embed the framework:

```bash
cd "$SRCROOT/.."
./gradlew :composeApp:embedAndSignAppleFrameworkForXcode
```

If this is missing or runs in the wrong directory, the framework doesn't end up where Xcode expects it.

## Common errors

### `Framework 'ComposeApp' not found`

**Cause**: Gradle didn't produce the framework, or Xcode is looking in the wrong path.

**Fixes**:
1. Run manually first: `./gradlew :composeApp:embedAndSignAppleFrameworkForXcode -PXCODE_CONFIGURATION=Debug -PSDK_NAME=iphonesimulator`
2. Check `composeApp/build/xcode-frameworks/<Config>/<Sdk>/ComposeApp.framework/` exists
3. Verify Xcode build phase script runs **before** "Compile Sources"
4. Ensure `FRAMEWORK_SEARCH_PATHS` in Xcode includes `$(SRCROOT)/../composeApp/build/xcode-frameworks/$(CONFIGURATION)/$(SDK_NAME)`

### `Undefined symbols for architecture arm64`

**Cause**: framework was built for the wrong architecture (simulator vs device).

**Fixes**:
1. Clean both: `./gradlew clean && rm -rf composeApp/build/`
2. Rebuild explicitly: `./gradlew :composeApp:linkDebugFrameworkIosArm64` (for device) or `linkDebugFrameworkIosSimulatorArm64` (for simulator)
3. Confirm Xcode's "Build Active Architecture Only" matches what you built

### Gradle daemon out-of-memory during iOS link

**Symptom**: `linkReleaseFrameworkIosArm64` task killed with OOM.

**Fix**: bump heap in `gradle.properties`:
```properties
org.gradle.jvmargs=-Xmx4g -XX:+UseParallelGC
kotlin.daemon.jvmargs=-Xmx3g
```

### `ld: warning: ignoring file ... mismatched personality`

**Cause**: mixed-architecture binary trying to link in an arch it doesn't support.

**Fix**: ensure your `iosX64()` target is removed if you don't need Intel Mac simulator support — Apple Silicon simulators use `iosSimulatorArm64`. Most modern setups have:
```kotlin
listOf(iosArm64(), iosSimulatorArm64())   // no iosX64
```

### `Module 'shared' not found` when importing from Swift

**Cause**: the framework's module name doesn't match the import.

**Fix**: framework `baseName` (e.g. `ComposeApp`) is what Swift imports as:
```swift
import ComposeApp
```

Not `import shared`, not `import composeApp`. The case matters.

### Cocoapods integration breaks after Gradle sync

**Cause**: this blueprint doesn't use Cocoapods. If the iOS app was set up with `kotlin("native.cocoapods")` plugin, it conflicts.

**Fix**: remove the `kotlin.native.cocoapods` plugin from `composeApp/build.gradle.kts`. Use the `embedAndSignAppleFrameworkForXcode` task instead (the JetBrains modern default since Compose MP 1.6+).

### Hot reload / Compose preview not working on iOS

Compose Multiplatform doesn't yet support hot reload on iOS the way it does on Android. Iterate via:
1. Rebuild in Xcode (Cmd+R) — accept ~30s rebuild cost
2. Or run Compose previews on JVM/desktop target during heavy UI iteration

### `signingConfigs not found` when archiving Android side from iOS macOS host

You ran an Android Gradle task while iOS work is in progress and signing.properties is missing. Either:
1. Run only iOS-relevant tasks: `./gradlew :composeApp:linkReleaseFrameworkIosArm64`
2. Or create a placeholder `signing.properties` with debug-only values

## Useful commands

```bash
# Verify simulators
xcrun simctl list devices available

# Wipe + rebuild iOS framework
./gradlew clean
./gradlew :composeApp:embedAndSignAppleFrameworkForXcode

# Open iOS workspace
open iosApp/iosApp.xcodeproj

# Build .ipa from CLI
xcodebuild -project iosApp/iosApp.xcodeproj \
           -scheme iosApp \
           -configuration Release \
           -archivePath build/iosApp.xcarchive \
           archive

xcodebuild -exportArchive \
           -archivePath build/iosApp.xcarchive \
           -exportPath build/ipa \
           -exportOptionsPlist iosApp/ExportOptions.plist
```

## When stuck

1. Run `/kmp-forge-doctor` to verify tool versions match what `CLAUDE.md` declares.
2. Spawn the `ios-build-doctor` agent (added in v2; for v1 run `kmp-reviewer` over the build log).
3. Last resort: scaffold a fresh KMP project via kmp.jetbrains.com (no overlay), confirm iOS builds in that, then diff against your project's `composeApp/build.gradle.kts` and Xcode project.

## Note on iosApp module

`iosApp/` is an **Xcode project**, not a Gradle module. Never add `include(":iosApp")` to `settings.gradle.kts`. The Xcode project consumes the `composeApp.framework`; Gradle drives the framework build via `embedAndSignAppleFrameworkForXcode`.
