---
description: Add a new :feature-<name> module (Compose screen + Orbit ViewModel + state + Koin module + Nav 3 destination + commonTest skeleton).
argument-hint: <feature-name>
---

# /kmp-forge-add-feature

Scaffolds a complete `:feature-<name>` module on the locked stack and wires it into the project.

## Arguments

- **`<feature-name>`**: lowercase kebab-case or single word (e.g. `gallery`, `auth`, `photo-detail`). Becomes the module name `:feature-<feature-name>` and the package suffix `feature.<pkg>`, where `<pkg>` is the name with dashes dropped (`photo-detail` → `photodetail` — ktlint and detekt both reject underscores in package names).

If the user invokes `/kmp-forge-add-feature` without an argument, ask for it via `AskUserQuestion`.

## Flow

### 1. Resolve names

```bash
FEATURE_NAME="<lowercase kebab-case input>"        # e.g. photo-detail   → module :feature-photo-detail
[[ "$FEATURE_NAME" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]] || echo "invalid feature name"   # stop + ask again
FEATURE_NAME_PKG="${FEATURE_NAME//-/}"             # e.g. photodetail    → package …feature.photodetail
FEATURE_NAME_PASCAL="$(echo "$FEATURE_NAME" | awk -F- '{for(i=1;i<=NF;i++) printf "%s%s",toupper(substr($i,1,1)),substr($i,2)}')"
                                                   # e.g. PhotoDetail    → PhotoDetailViewModel, PhotoDetailRoute
FEATURE_NAME_CAMEL="$(echo "$FEATURE_NAME_PASCAL" | awk '{print tolower(substr($0,1,1)) substr($0,2)}')"
                                                   # e.g. photoDetail    → val photoDetailModule
```

### 2. Determine base package

Read from CLAUDE.md → `Base package:` line, or from `androidApp/build.gradle.kts` android config (the thin Android application module, where `applicationId`/`namespace` live). Fallback: ask user.

```bash
BASE_PACKAGE="com.example.myapp"                    # parsed
BASE_PACKAGE_PATH="$(echo "$BASE_PACKAGE" | tr . /)"
```

### 3. Delegate to kmp-feature-builder agent

Spawn the `kmp-feature-builder` agent with **all four** inputs it builds paths from:

- `feature_name` = `$FEATURE_NAME` (kebab-case)
- `base_package` = `$BASE_PACKAGE`
- `project_root` = absolute project path
- `claude_plugin_root` = the absolute value of `${CLAUDE_PLUGIN_ROOT}` (the agent does not inherit it — resolve it before spawning)

The agent:

- Reads one existing feature module (if any) for style reference
- Reads `:domain` to identify available use cases the feature might invoke
- Generates the feature files from `overlay/modules/feature/` templates:
  - `<Name>State.kt`, `<Name>ViewModel.kt`, `<Name>Screen.kt`, `<Name>Route.kt`, `<Name>NavEntry.kt`, `<camelName>Module.kt`, `<Name>ViewModelTest.kt`, `composeResources/values/strings.xml`
- Adjusts ViewModel constructor + load() body if a relevant use case exists in `:domain`
- Performs steps 4–8 below

Or, if you prefer not to delegate (simpler/faster), run the overlay directly:

```bash
PROJECT_ROOT="<root>"
export FEATURE_NAME FEATURE_NAME_PKG FEATURE_NAME_CAMEL FEATURE_NAME_PASCAL BASE_PACKAGE BASE_PACKAGE_PATH

bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render-module \
    "feature.${FEATURE_NAME_PKG}" \
    "${CLAUDE_PLUGIN_ROOT}/overlay/modules/feature" \
    "${PROJECT_ROOT}/feature-${FEATURE_NAME}" \
    "${BASE_PACKAGE_PATH}"
```

(`render-module` turns the dotted package suffix into directories — `feature.photodetail` lands in `com/example/myapp/feature/photodetail/` for every source set.)

Then rename the template file **basenames** (`Feature*` → `<Name>*`, `featureModule.kt` → `<camelName>Module.kt`). Only the basename changes — the directory path itself contains `feature/`:

```bash
cd "${PROJECT_ROOT}/feature-${FEATURE_NAME}/src"
find . -type f \( -name 'Feature*.kt' -o -name 'feature*.kt' \) | while read -r f; do
    base="$(basename "$f")"
    case "$base" in
        Feature*) new="${FEATURE_NAME_PASCAL}${base#Feature}" ;;
        feature*) new="${FEATURE_NAME_CAMEL}${base#feature}" ;;
    esac
    mv "$f" "$(dirname "$f")/$new"
done
```

### 4. Patch settings.gradle.kts

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-settings \
    "${PROJECT_ROOT}" "feature-${FEATURE_NAME}"
```

### 5. Wire the feature into `:shared`

`:shared` is the composition root: `App.kt` starts Koin with the list in `AppModules.kt`, and `AppNavigation.kt` owns the Nav 3 back stack. Both files carry `// kmp-forge:` marker comments (rendered by `/kmp-forge-init` from `overlay/shared/`); insert new lines **directly above** each marker and keep the marker. All paths below are under `shared/src/commonMain/kotlin/<base-pkg-path>/`.

1. `shared/build.gradle.kts` → `commonMain.dependencies { … }`: add `implementation(project(":feature-${FEATURE_NAME}"))`.
2. `AppModules.kt`: add `import ${BASE_PACKAGE}.feature.${FEATURE_NAME_PKG}.${FEATURE_NAME_CAMEL}Module` and, above `// kmp-forge:feature-modules`, the line `    ${FEATURE_NAME_CAMEL}Module,`.
3. `AppNavigation.kt`:
   - imports: `${BASE_PACKAGE}.feature.${FEATURE_NAME_PKG}.${FEATURE_NAME_PASCAL}Route` and `${BASE_PACKAGE}.feature.${FEATURE_NAME_PKG}.add${FEATURE_NAME_PASCAL}Entries`
   - above `// kmp-forge:nav-routes`: `            subclass(${FEATURE_NAME_PASCAL}Route::class, ${FEATURE_NAME_PASCAL}Route.serializer())` — **required**: off Android, `rememberNavBackStack` can only save routes registered in this `SerializersModule`; a missing one throws `SerializationException` the first time the back stack is saved.
   - above `// kmp-forge:nav-entries`: `            add${FEATURE_NAME_PASCAL}Entries(onNavigateBack = navigateBack)` — never reference the `internal` screen directly, never add a `when` branch. The parameter is nullable: the start destination is wired with `onNavigateBack = null` (nothing to go back to, so its screen shows no Back control).

Use the Edit tool. Be defensive: if a marker is missing (a project scaffolded before the composition root existed, or one the user restructured), find the equivalent `modules(...)` list / `polymorphic(NavKey::class) { … }` block / `entryProvider { … }` block; if there is none, surface the exact lines for the user to apply rather than guessing.

### 6. Update CLAUDE.md

Replace the `Features: ...` line in CLAUDE.md to add the new feature. If the existing list reads `_(none yet ...)`, replace entirely; otherwise append.

### 7. Verify the build

```bash
cd "${PROJECT_ROOT}"
./gradlew :feature-${FEATURE_NAME}:spotlessApply
./gradlew :feature-${FEATURE_NAME}:build :shared:build
```

`spotlessApply` first: ktlint orders imports lexicographically, so where the base-package imports belong depends on the base package itself — the templates assume a `com.*`/`dev.*`/`io.*`-style package, and this normalizes anything else. `:feature-x:build` runs the module's tests on every target plus the `detekt` + `spotlessCheck` gates (they hook into `check`); `:shared:build` proves the composition-root wiring compiles. (For a quick host-only test loop use `./gradlew :feature-${FEATURE_NAME}:jvmTest`. There is no `commonTest` task — common tests run inside each target's test task.)

If green, the feature is wired. Surface the result to the user.

### 8. Report

```
✓ Added :feature-<name>
✓ Files: <Name>Screen.kt, <Name>ViewModel.kt, <Name>State.kt, <Name>Route.kt, <Name>NavEntry.kt, <camelName>Module.kt, <Name>ViewModelTest.kt, values/strings.xml
✓ Wired feature dep + Koin module + Nav 3 route registration + entries into :shared
✓ Build: green | red (with output)

Next: implement the use case in :domain, add fakes/tests, build the UI.
The app still launches on HomeRoute — to start on this feature, pass <Name>Route to rememberNavBackStack(...) in AppNavigation.kt and wire add<Name>Entries(onNavigateBack = null).
The screen renders a placeholder line (TODO(kmp-forge)) — replace it with the real content.
```

## Notes

- The package segment drops dashes (`photodetail`) — Kotlin packages can't contain dashes, and ktlint (`package-name`) + detekt (`PackageNaming`) reject underscores.
- The Gradle module name keeps dashes (`feature-photo-detail`) — `settings.gradle.kts` accepts them.
- Never reuse a feature name. If the module already exists, surface the conflict and stop.
- If `:domain` doesn't expose a use case relevant to the feature yet, the generated ViewModel carries a comment showing where to call it — that's intentional (not a `TODO:`, which detekt's `ForbiddenComment` rejects).
- The generated screen's content is a placeholder string (`placeholder_content`) marked `// TODO(kmp-forge):` so neither QA nor a reviewer mistakes it for shipped UI; `kmp-reviewer` flags a feature that still renders it.
