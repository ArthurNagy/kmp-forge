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
   - Package path under `feature-<feature-name>/src/commonMain/kotlin/<BASE_PACKAGE_PATH>/feature/<feature_pkg>/`

4. **Generate 4 files** under that package (state-only events — effect type is always `Nothing`):
   - `<Pascal>State.kt` — `internal data class <Pascal>State(...)`, **no constructor defaults**, with `companion object { val Initial = <Pascal>State(...) }`
   - `<Pascal>ViewModel.kt` — `internal class <Pascal>ViewModel : ViewModel(), ContainerHost<<Pascal>State, Nothing>`, `container(<Pascal>State.Initial)`
   - `<Pascal>Screen.kt` — `internal` stateless Composable (resolves `koinViewModel<<Pascal>ViewModel>()` in body) + `private <Pascal>Content`
   - `<Pascal>Route.kt` — public `@Serializable data object/class <Pascal>Route : NavKey`

   Use the `Feature{State,ViewModel,Screen,Route}.kt.tmpl` templates from `overlay/modules/feature/src/commonMain/kotlin/`. Run `apply-overlay.sh` with appropriate env vars; rename basenames `Feature*` → `<Pascal>*`. Do **not** generate a second `NavEntry.kt` or `Module.kt` — the feature already owns one of each; step 6 appends to its existing entry contribution.

5. **Add VM to the feature's Koin module**: Edit `<feature_pkg>Module.kt`, append `viewModelOf(::<Pascal>ViewModel)`.

6. **Wire Nav 3 destination into the feature's entry contribution**: Edit the feature's `<Feature>NavEntry.kt`, appending another `entry<<Pascal>Route> { <Pascal>Screen(...) }` line inside `add<Feature>Entries(...)`. If the new screen needs outgoing navigation, add an `onOpenX`/`onNavigateBack` callback parameter to `add<Feature>Entries(...)` and surface the matching change to the app's `entryProvider { add<Feature>Entries(...) }` call site. Same defensive Edit pattern as `/kmp-forge-add-feature` — never reference the `internal` screen from `:composeApp`.

7. **Generate matching test**: `<Pascal>ViewModelTest.kt` under `feature-<feature-name>/src/commonTest/kotlin/.../feature/<feature_pkg>/`, seeded with `<Pascal>State.Initial`.

8. **Build to verify**: `./gradlew :feature-<feature-name>:build`.

9. **Report** files created + Edits applied + build result.

## Notes

- Multiple screens per feature is the common case (list + detail, or master + multiple drill-downs). Each screen is independent state + ViewModel + Composable.
- If the feature already has many screens (>5), consider whether it should be split into multiple features. Mention this to the user.
- Screen-level use cases live in `:domain` and are injected per ViewModel; this command does NOT create use cases.
