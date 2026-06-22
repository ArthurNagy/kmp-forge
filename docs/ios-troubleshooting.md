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

`:shared` exports a Kotlin/Native static framework named `Shared` consumed by `iosApp/iosApp.xcodeproj`.

### `shared/build.gradle.kts`

```kotlin
kotlin {
    listOf(iosArm64(), iosSimulatorArm64()).forEach {
        it.binaries.framework {
            baseName = "Shared"
            isStatic = true
        }
    }
}
```

### Xcode build phase

The Xcode project has a "Run Script" build phase that invokes Gradle to build/embed the framework:

```bash
cd "$SRCROOT/.."
./gradlew :shared:embedAndSignAppleFrameworkForXcode
```

If this is missing or runs in the wrong directory, the framework doesn't end up where Xcode expects it.

## Common errors

### `Framework 'Shared' not found`

**Cause**: Gradle didn't produce the framework, or Xcode is looking in the wrong path.

**Fixes**:
1. Run manually first: `./gradlew :shared:embedAndSignAppleFrameworkForXcode -PXCODE_CONFIGURATION=Debug -PSDK_NAME=iphonesimulator`
2. Check `shared/build/xcode-frameworks/<Config>/<Sdk>/Shared.framework/` exists
3. Verify Xcode build phase script runs **before** "Compile Sources"
4. Ensure `FRAMEWORK_SEARCH_PATHS` in Xcode includes `$(SRCROOT)/../shared/build/xcode-frameworks/$(CONFIGURATION)/$(SDK_NAME)`

### `Undefined symbols for architecture arm64`

**Cause**: framework was built for the wrong architecture (simulator vs device).

**Fixes**:
1. Clean both: `./gradlew clean && rm -rf shared/build/`
2. Rebuild explicitly: `./gradlew :shared:linkDebugFrameworkIosArm64` (for device) or `linkDebugFrameworkIosSimulatorArm64` (for simulator)
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

**Fix**: framework `baseName` (`Shared`) is what Swift imports as:
```swift
import Shared
```

Not `import shared`, not `import SHARED`. The case matters.

### Cocoapods integration breaks after Gradle sync

**Cause**: this blueprint doesn't use Cocoapods. If the iOS app was set up with `kotlin("native.cocoapods")` plugin, it conflicts.

**Fix**: remove the `kotlin.native.cocoapods` plugin from `shared/build.gradle.kts`. Use the `embedAndSignAppleFrameworkForXcode` task instead (the JetBrains modern default since Compose MP 1.6+).

### Hot reload / Compose preview not working on iOS

Compose Multiplatform doesn't yet support hot reload on iOS the way it does on Android. Iterate via:
1. Rebuild in Xcode (Cmd+R) — accept ~30s rebuild cost
2. Or run Compose previews on JVM/desktop target during heavy UI iteration

### `signingConfigs not found` when archiving Android side from iOS macOS host

You ran an Android Gradle task while iOS work is in progress and signing.properties is missing. Either:
1. Run only iOS-relevant tasks: `./gradlew :shared:linkReleaseFrameworkIosArm64`
2. Or create a placeholder `signing.properties` with debug-only values

## Useful commands

```bash
# Verify simulators
xcrun simctl list devices available

# Wipe + rebuild iOS framework
./gradlew clean
./gradlew :shared:embedAndSignAppleFrameworkForXcode

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
3. Last resort: scaffold a fresh KMP project via kmp.jetbrains.com (no overlay), confirm iOS builds in that, then diff against your project's `shared/build.gradle.kts` and Xcode project.

## Note on iosApp module

`iosApp/` is an **Xcode project**, not a Gradle module. Never add `include(":iosApp")` to `settings.gradle.kts`. The Xcode project consumes the `Shared.framework`; Gradle drives the framework build via `embedAndSignAppleFrameworkForXcode`.
