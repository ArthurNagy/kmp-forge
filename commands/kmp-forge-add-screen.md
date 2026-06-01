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

4. **Generate 4 files** under that package:
   - `<Pascal>State.kt` — `data class <Pascal>State(...)` + `sealed interface <Pascal>Effect`
   - `<Pascal>ViewModel.kt` — `class <Pascal>ViewModel : ViewModel(), ContainerHost<<Pascal>State, <Pascal>Effect>`
   - `<Pascal>Screen.kt` — stateless Composable + `<Pascal>Content`
   - `<Pascal>Route.kt` — `@Serializable data object/class <Pascal>Route : NavKey`

   Use the same templates as `overlay/modules/feature/src/commonMain/kotlin/Feature*.kt.tmpl`. Run `apply-overlay.sh` with appropriate env vars; rename basenames `Feature*` → `<Pascal>*`.

5. **Add VM to the feature's Koin module**: Edit `<feature_pkg>Module.kt`, append `viewModelOf(::<Pascal>ViewModel)`.

6. **Wire Nav 3 destination into composeApp**: Edit composeApp's `NavDisplay` `when` block to handle `<Pascal>Route`. Same defensive Edit pattern as `/kmp-forge-add-feature`.

7. **Generate matching test**: `<Pascal>ViewModelTest.kt` under `feature-<feature-name>/src/commonTest/kotlin/.../feature/<feature_pkg>/`.

8. **Build to verify**: `./gradlew :feature-<feature-name>:build`.

9. **Report** files created + Edits applied + build result.

## Notes

- Multiple screens per feature is the common case (list + detail, or master + multiple drill-downs). Each screen is independent state + ViewModel + Composable.
- If the feature already has many screens (>5), consider whether it should be split into multiple features. Mention this to the user.
- Screen-level use cases live in `:domain` and are injected per ViewModel; this command does NOT create use cases.
