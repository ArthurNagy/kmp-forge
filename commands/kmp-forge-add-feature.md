---
description: Add a new :feature-<name> module (Compose screen + Orbit ViewModel + state + Koin module + Nav 3 destination + commonTest skeleton).
argument-hint: <feature-name>
---

# /kmp-forge-add-feature

Scaffolds a complete `:feature-<name>` module on the locked stack and wires it into the project.

## Arguments

- **`<feature-name>`**: lowercase kebab-case or single word (e.g. `gallery`, `auth`, `photo-detail`). Becomes the module name `:feature-<feature-name>` and the package suffix `feature.<feature-name>` (kebabs become underscores in the package).

If the user invokes `/kmp-forge-add-feature` without an argument, ask for it via `AskUserQuestion`.

## Flow

### 1. Resolve names

```bash
FEATURE_NAME="<lowercase kebab-case input>"        # e.g. photo-detail
FEATURE_NAME_PKG="${FEATURE_NAME//-/_}"            # e.g. photo_detail (valid Kotlin pkg segment)
FEATURE_NAME_PASCAL="$(echo "$FEATURE_NAME" | awk -F- '{for(i=1;i<=NF;i++) printf "%s%s",toupper(substr($i,1,1)),substr($i,2)}')"
# e.g. PhotoDetail
```

### 2. Determine base package

Read from CLAUDE.md → `Base package:` line, or from `composeApp/build.gradle.kts` android config. Fallback: ask user.

```bash
BASE_PACKAGE="com.example.myapp"                    # parsed
BASE_PACKAGE_PATH="$(echo "$BASE_PACKAGE" | tr . /)"
```

### 3. Delegate to kmp-feature-builder agent

Spawn the `kmp-feature-builder` agent with the feature name + base package + project root. The agent:

- Reads one existing feature module (if any) for style reference
- Reads `:domain` to identify available use cases the feature might invoke
- Generates the 6 feature files from `overlay/modules/feature/` templates:
  - `<Name>State.kt`, `<Name>ViewModel.kt`, `<Name>Screen.kt`, `<Name>Route.kt`, `<feature>Module.kt`, `<Name>ViewModelTest.kt`
- Adjusts ViewModel constructor + load() body if a relevant use case exists in `:domain`

Or, if you prefer not to delegate (simpler/faster), run the overlay directly:

```bash
PROJECT_ROOT="<root>"
export FEATURE_NAME FEATURE_NAME_PASCAL BASE_PACKAGE BASE_PACKAGE_PATH

bash ${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh render-module \
    "feature.${FEATURE_NAME_PKG}" \
    "${CLAUDE_PLUGIN_ROOT}/overlay/modules/feature" \
    "${PROJECT_ROOT}/feature-${FEATURE_NAME}" \
    "${BASE_PACKAGE_PATH}"
```

(`render-module` inserts `<base-package-path>/<module-name>/` into commonMain/commonTest paths — so `feature.photo_detail` becomes `com/example/myapp/feature/photo_detail/`.)

Then rename the template file basenames from `Feature*` → `<Name>*`:

```bash
cd "${PROJECT_ROOT}/feature-${FEATURE_NAME}/src"
find . -name "Feature*.kt" -exec bash -c 'mv "$0" "${0/Feature/'"${FEATURE_NAME_PASCAL}"'}"' {} \;
find . -name "feature*.kt" -exec bash -c 'mv "$0" "${0/feature/'"${FEATURE_NAME_PKG}"'}"' {} \;
```

### 4. Patch settings.gradle.kts

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh patch-settings \
    "${PROJECT_ROOT}" "feature-${FEATURE_NAME}"
```

### 5. Wire Koin module into composeApp

Edit `composeApp/src/commonMain/kotlin/<base-pkg-path>/App.kt` (or wherever `startKoin { ... }` is called) to add the new feature's Koin module to the `modules(...)` list:

```kotlin
startKoin {
    modules(
        domainModule,
        dataModule,
        uiModule,
        photoDetailModule,  // ← add
    )
}
```

Use the Edit tool. Be defensive: if the file doesn't exist or the pattern doesn't match, surface the diff for the user to apply manually.

### 6. Wire Nav 3 destination

Edit `composeApp/src/commonMain/kotlin/<base-pkg-path>/App.kt` (or wherever `NavDisplay` is called) to add the feature's entry contribution to the `entryProvider { }` block (import `add<Name>Entries` from the feature package). The screen is `internal` — never reference it directly.

```kotlin
NavDisplay(
    backStack = backStack,
    entryProvider = entryProvider {
        // existing feature entries…
        addPhotoDetailEntries(onNavigateBack = { backStack.removeLastOrNull() })  // ← add
    },
)
```

Same defensive Edit pattern. If the app still uses a `NavDisplay(backStack) { key -> when (key) { ... } }`, surface the migration to the `entryProvider { }` DSL for the user to apply rather than adding a `when` branch.

### 7. Update CLAUDE.md

Replace the `Features: ...` line in CLAUDE.md to add the new feature. If the existing list reads `_(none yet ...)`, replace entirely; otherwise append.

### 8. Verify the build

```bash
cd "${PROJECT_ROOT}"
./gradlew :feature-${FEATURE_NAME}:build :feature-${FEATURE_NAME}:commonTest
```

If green, the feature is wired. Surface the result to the user.

### 9. Report

```
✓ Added :feature-<name>
✓ Files: <Name>Screen.kt, <Name>ViewModel.kt, <Name>State.kt, <Name>Route.kt, <feature>Module.kt, <Name>ViewModelTest.kt
✓ Wired Koin module + Nav 3 destination into composeApp
✓ Build: green | red (with output)

Next: implement the use case in :domain, add fakes/tests, build the UI.
```

## Notes

- The package segment uses underscores (`photo_detail`), not dashes — Kotlin packages can't contain dashes.
- The Gradle module name keeps dashes (`feature-photo-detail`) — `settings.gradle.kts` accepts them.
- Never reuse a feature name. If the module already exists, surface the conflict and stop.
- If `:domain` doesn't expose a use case relevant to the feature yet, the generated ViewModel has a TODO comment — that's intentional.
