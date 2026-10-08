---
description: Refresh gradle/libs.versions.toml against the latest stable versions of every locked-stack library.
---

# /kmp-forge-bump-stack

Queries Maven Central + Google Maven for the latest stable versions of every locked-stack lib, produces a diff against the project's current `gradle/libs.versions.toml`, and proposes a single commit.

## Flow

### 1. Fetch latest versions

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/fetch-latest-versions.sh toml > /tmp/kmp-forge-latest.toml
```

This emits a `[versions]` block keyed exactly like the project's catalog: the toolchain keys kmp.new owns (`kotlin`, `agp`, `composeMultiplatform`, `androidx-lifecycle`, `kotlinx-coroutines`) plus the overlay's keys (`orbitMvi`, `koin`, `coil`, `ktor`, `kermit`, `kotlinxDatetime`, `kotlinxSerialization`, `androidxNavigation3`, `androidxNavigation3Runtime`, `androidxDatastore`, `sqldelight`, `turbine`, `kotlinResult`, `store`, `detekt`, `spotless`, `ktlint`, `kover`). "Latest" means the highest purely numeric release in version order — `-alpha`/`-beta`/`-RC`/`-compat` builds are skipped, except for keys whose pin already tracks a pre-release line (`store`). `androidxNavigation3Runtime` is derived from the latest JetBrains `navigation3-ui` port's own dependency (the two are versioned independently). `material3` is not reported — bump it by hand together with `composeMultiplatform`.

### 2. Read the current project catalog

```bash
PROJECT_LIBS="<projectRoot>/gradle/libs.versions.toml"
```

### 3. Compute the diff

For each key in `/tmp/kmp-forge-latest.toml`'s `[versions]` block:

- If the key exists in `PROJECT_LIBS` and the version is newer, mark for bump.
- If the key exists and the version is older (e.g. you pinned an older minor on purpose), skip — surface a note.
- If the key doesn't exist in `PROJECT_LIBS`, skip (this project doesn't use that lib).
- If the script returned `# WARN <key> ... not found`, skip — surface a warning.

### 4. Present the diff to the user

Use `AskUserQuestion` to confirm the bump, showing the full list of changes:

```
Libraries to bump:
  - orbitMvi: 12.0.1 → 12.1.0
  - coil: 3.6.3 → 3.7.0
  - ktor: 3.6.0 → 3.7.0

Continue?
```

### 5. Apply the bump

Use the `Edit` tool with `replace_all = false` to update each `[versions]` entry in `PROJECT_LIBS`. Use unique anchor text (the full `key = "old_version"` line) for safety.

### 6. Build to verify

```bash
cd <projectRoot>
./gradlew build 2>&1 | tail -50
```

If green, proceed to step 7. If red, surface the failure verbatim — user decides whether to revert or fix forward. **Do not** auto-revert.

### 7. Surface breaking-change notes

For each major bump (e.g. `2.x → 3.x`), suggest the user check the library's release notes for migration steps. Don't try to migrate automatically.

### 8. Suggest commit

Print a Conventional Commit message ready to use:

```
chore(deps): bump locked stack to latest stable

- orbitMvi 12.0.1 → 12.1.0
- coil 3.6.3 → 3.7.0
- ktor 3.6.0 → 3.7.0
```

User commits when they're ready (don't auto-commit — give them a chance to amend after manual review).

## Notes

- This is the **only** automated dependency-update path in kmp-forge. No Renovate/Dependabot.
- Versions are bumped one project at a time. If you have multiple kmp-forge projects, run this in each.
- For `kotlin` / `agp` major bumps, the build will frequently break — these often require breaking-change handling in convention plugins. Surface the change clearly. An `agp` bump can also require a newer Gradle wrapper (`gradle/wrapper/gradle-wrapper.properties`).
