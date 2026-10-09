---
description: Add a new screen (Composable + Orbit ViewModel + state + Nav 3 destination) inside an existing :feature-<name> module.
argument-hint: <feature-name> <screen-name>
---

# /kmp-forge-add-screen

Adds a new screen to an existing feature module. Unlike `/kmp-forge-add-feature`, this does not create a new module — it adds files into an existing `:feature-<name>`.

## Arguments

- **`<feature-name>`**: existing feature, e.g. `gallery`
- **`<screen-name>`**: kebab-case, e.g. `photo-detail`. PascalCase'd to e.g. `PhotoDetail` for class names.

Ask via `AskUserQuestion` if missing.

## Flow

1. **Verify the feature module exists**:
   ```bash
   test -d "${PROJECT_ROOT}/feature-${feature_name}" || { echo "feature-${feature_name} not found. Run /kmp-forge-add-feature ${feature_name} first."; exit 1; }
   ```

2. **Read existing screens in the feature** (if any) for style reference.

3. **Resolve names**:
   - `SCREEN_NAME_PASCAL`: PascalCase of `<screen-name>`
   - Package path under `feature-<feature-name>/src/commonMain/kotlin/<BASE_PACKAGE_PATH>/feature/<feature_pkg>/` (`<feature_pkg>` = feature name with dashes dropped, e.g. `photodetail`)

4. **Generate 4 files** under that package (state-only events — effect type is always `Nothing`):
   - `<Pascal>State.kt` — `internal data class <Pascal>State(...)`, **no constructor defaults**, with `companion object { val Initial = <Pascal>State(...) }`
   - `<Pascal>ViewModel.kt` — `internal class <Pascal>ViewModel : ViewModel(), OrbitContainerHost<<Pascal>State, <Pascal>State, Nothing>`, `orbitContainer<<Pascal>State, Nothing>(<Pascal>State.Initial)`
   - `<Pascal>Screen.kt` — `internal` Composable entry point (resolves `koinViewModel<<Pascal>ViewModel>()` in body) + stateless `private <Pascal>Content`; text via the feature's existing `Res.string` (add keys to its `composeResources/values/strings.xml`)
   - `<Pascal>Route.kt` — public `@Serializable data object/class <Pascal>Route : NavKey`

   Use the `Feature{State,ViewModel,Screen,Route}.kt.tmpl` templates from `overlay/modules/feature/src/commonMain/kotlin/`, rendered with the **feature's** `FEATURE_NAME_PKG` (package) and the **screen's** PascalCase as `FEATURE_NAME_PASCAL` (`envsubst` with an explicit variable list, as `apply-overlay.sh` does); rename basenames `Feature*` → `<Pascal>*`. Merge the template's string keys into the feature's existing `strings.xml` (prefix them with the screen name if they collide) rather than adding a second table. Do **not** generate a second `NavEntry.kt` or `Module.kt` — the feature already owns one of each; step 6 appends to its existing entry contribution.

5. **Add VM to the feature's Koin module**: Edit the feature's `<camelName>Module.kt` (e.g. `photoDetailModule.kt`), append `viewModelOf(::<Pascal>ViewModel)`.

6. **Wire Nav 3 destination into the feature's entry contribution**: Edit the feature's `<Feature>NavEntry.kt`, appending another `entry<<Pascal>Route> { <Pascal>Screen(...) }` line inside `add<Feature>Entries(...)`. If the new screen needs outgoing navigation, add an `onOpenX`/`onNavigateBack` callback parameter to `add<Feature>Entries(...)` (a pushed screen always needs a working back: pass it the feature's `onNavigateBack`, or — when the feature is the start destination and wired with `onNavigateBack = null` — a new non-null `on<Pascal>Back: () -> Unit` parameter the host fills with `navigateBack`) and surface the matching change to the `:shared` host's `entryProvider { add<Feature>Entries(...) }` call site (`:shared` owns `App.kt` + the `NavDisplay` back stack). Same defensive Edit pattern as `/kmp-forge-add-feature` — never reference the `internal` screen from `:shared`. Also register the new route in `:shared`'s `AppNavigation.kt` above `// kmp-forge:nav-routes`: `subclass(<Pascal>Route::class, <Pascal>Route.serializer())` — off Android an unregistered route throws `SerializationException` when the back stack is saved.

7. **Generate matching test**: `<Pascal>ViewModelTest.kt` under `feature-<feature-name>/src/commonTest/kotlin/.../feature/<feature_pkg>/`, seeded with `<Pascal>State.Initial`.

8. **Build to verify**: `./gradlew :feature-<feature-name>:build`.

9. **Report** files created + Edits applied + build result.

## Notes

- Multiple screens per feature is the common case (list + detail, or master + multiple drill-downs). Each screen is independent state + ViewModel + Composable.
- If the feature already has many screens (>5), consider whether it should be split into multiple features. Mention this to the user.
- Screen-level use cases live in `:domain` and are injected per ViewModel; this command does NOT create use cases.
