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

This emits a `[versions]` block with the latest stable version for every key in the locked stack (orbit, koin, coil, ktor, kermit, kotlinx-*, androidx-*, sqldelight, turbine, detekt, kotlin, agp, compose-*).

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
  - orbitMvi: 9.0.0 → 9.1.0
  - coil: 3.1.0 → 3.2.0
  - androidxNavigation3: 1.1.2 → 1.1.3

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

- orbitMvi 9.0.0 → 9.1.0
- coil 3.1.0 → 3.2.0
- androidxNavigation3 1.1.2 → 1.1.3
```

User commits when they're ready (don't auto-commit — give them a chance to amend after manual review).

## Notes

- This is the **only** automated dependency-update path in kmp-forge. No Renovate/Dependabot.
- Versions are bumped one project at a time. If you have multiple kmp-forge projects, run this in each.
- For `kotlinGradlePlugin` / `androidGradlePlugin` major bumps, the build will frequently break — these often require breaking-change handling in convention plugins. Surface the change clearly.
