---
description: Adopt the kmp-forge locked stack into an EXISTING Kotlin Multiplatform project — overlay docs/CI/conventions, then drive a reviewer-led refactor of code to the locked patterns.
---

# /kmp-forge-adopt

Sibling to `/kmp-forge-init`, but for a project that **already exists**. No kmp.jetbrains.com download. Instead it detects the existing structure, applies the kmp-forge overlay **non-destructively**, and produces a dependency-ordered refactor plan to migrate code onto the locked patterns.

Two phases:

- **Phase A — mechanical overlay** (this command does it): safe-additive pieces applied automatically; overwrite-danger files rendered to a scratch dir and hand-merged via diff. Never blind-clobbers existing files.
- **Phase B — pattern refactor** (reviewer-driven): the `kmp-reviewer` agent audits the code; this command turns its findings into an ordered work-list and refactors layer-by-layer with confirmation.

Execute steps **in order**. Stop and ask if anything is unclear. Everything happens on a branch — never touch `main` directly.

## Conventions

- **Always quote paths** (`"$TARGET"`) — the user's Personal projects directory contains a space.
- **Never blind-overwrite** an existing file. If a target exists, render to scratch, `git --no-index diff`, and merge with the Edit tool after showing the user.
- The plugin does NOT push to GitHub or enable branch protection. The user opts into both manually.
- Canonical rules live in `docs/<area>.md` on GitHub `main` (linked below). Re-read them when refactoring — do not invent rules.

---

### 0. Preconditions + safety

The user must run this from the **root of the existing project**. Verify it is a KMP project and the tree is clean:

```bash
TARGET="$PWD"
# Must be a Gradle KMP project
[[ -f "$TARGET/settings.gradle.kts" ]] || { echo "✗ no settings.gradle.kts — run from project root"; exit 1; }
[[ -f "$TARGET/gradle/libs.versions.toml" ]] || { echo "✗ no gradle/libs.versions.toml — kmp-forge needs a version catalog"; exit 1; }
grep -rqlE "kotlin\\(\"multiplatform\"\\)|org.jetbrains.kotlin.multiplatform" --include="*.kts" "$TARGET" \
  || echo "⚠ no Kotlin Multiplatform plugin found — continue only if this really is a KMP project"
# Working tree must be clean
git -C "$TARGET" diff --quiet && git -C "$TARGET" diff --cached --quiet \
  || { echo "✗ working tree dirty — commit or stash first"; exit 1; }
```

If any hard check fails, stop and tell the user. Then create the adoption branch:

```bash
git -C "$TARGET" switch -c chore/adopt-kmp-forge
```

Use `AskUserQuestion` to confirm the user understands this writes many files (on a branch, reversible via `git`) before proceeding.

### 1. Detect existing structure

Build a map of what the project already is — do NOT assume the kmp-forge layout.

```bash
# Modules already declared
grep -nE "include\(" "$TARGET/settings.gradle.kts"
# App module (Compose entry point)
ls -d "$TARGET"/*/src/*/kotlin 2>/dev/null
# Platforms / targets
grep -rnE "androidTarget|iosArm64|iosSimulatorArm64|jvm\(|js\(|wasmJs" --include="*.kts" "$TARGET" | head
# Existing version catalog keys (so we know what patch-libs will skip vs add)
grep -nE "^[a-zA-Z]" "$TARGET/gradle/libs.versions.toml" | head -60
# Does it already use the locked stack at all?
grep -rql "org.orbit-mvi" "$TARGET" && echo "has Orbit" || echo "no Orbit"
grep -rql "io.insert-koin" "$TARGET" && echo "has Koin" || echo "no Koin"
grep -rql "build-logic" "$TARGET/settings.gradle.kts" && echo "has build-logic" || echo "no build-logic"
```

Read the app module's `build.gradle.kts` to infer `namespace`/`applicationId` (→ `BASE_PACKAGE`) and `App name`.

Present the detected map to the user:
- existing modules + inferred role (app / ui / domain / data / feature / other)
- platforms enabled
- which locked-stack libs are already present
- whether `build-logic` convention plugins exist

Then use `AskUserQuestion` to **confirm the role mapping** (especially: which module is the app, and whether the project already has ui/domain/data layering or needs it created).

### 2. Gather overlay variables

Same vars as `/kmp-forge-init` step 4, but **infer from the existing project** and confirm with `AskUserQuestion` rather than asking cold:

```bash
export APP_NAME="<inferred PascalCase, confirm>"
export APP_TAGLINE="<one-liner or empty>"
export BASE_PACKAGE="<inferred from namespace, confirm>"
export BASE_PACKAGE_PATH="$(echo "$BASE_PACKAGE" | tr . /)"
export SCAFFOLD_DATE="$(date -u +%Y-%m-%d)"
export PLATFORM_LIST="<markdown bullets from detected targets>"
export BUILD_COMMANDS="<per-platform ./gradlew ... fenced block>"
export MODULE_LIST="<the project's REAL module list, not the default>"
export FEATURE_LIST="<detected :feature-* modules, or '_(none yet)_'>"
export OPTIONAL_LIBS="<detected opt-in libs: ktor, sqldelight, ...>"
export FIGMA_URL="(none)"
export PROJECT_OVERRIDES=""
export TIMELINE=""
```

`MODULE_LIST`/`FEATURE_LIST`/`PLATFORM_LIST` must reflect reality — they feed the generated `CLAUDE.md`.

### 3. Phase A — safe-additive (automatic)

These are purely additive and safe to run unconditionally:

```bash
OVERLAY="${CLAUDE_PLUGIN_ROOT}/overlay"
SH="${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh"

# Version catalog: additive merge — skips existing keys, appends under "# --- kmp-forge additions ---"
bash "$SH" patch-libs "$TARGET" "$OVERLAY/gradle/libs.versions.toml.additions.tmpl"

# Secrets hygiene
cp "$OVERLAY/git/.gitleaks.toml" "$TARGET/.gitleaks.toml"
cp "$OVERLAY/git/pre-commit-hook.sh" "$TARGET/.kmp-forge-pre-commit.sh"
chmod +x "$TARGET/.kmp-forge-pre-commit.sh"
```

**Product docs** (`docs/MVP_SPEC.md`, `docs/DECISIONS/`) — only fill gaps, never clobber an existing spec:

```bash
mkdir -p "$TARGET/docs"
if [[ -f "$TARGET/docs/MVP_SPEC.md" ]]; then
    bash "$SH" render "$OVERLAY/product" /tmp/kmpf-product
    echo "⚠ docs/MVP_SPEC.md exists — review /tmp/kmpf-product and merge manually"
else
    bash "$SH" render "$OVERLAY/product" "$TARGET/docs"
fi
```

Report each result.

### 4. Phase A — overwrite-danger (scratch + diff + merge)

`overlay/root` renders `CLAUDE.md`, `.gitignore`, `.editorconfig`, `detekt.yml`, `cliff.toml` — all likely to already exist. Render to scratch first:

```bash
bash "$SH" render "$OVERLAY/root" /tmp/kmpf-root
```

For **each** file:
- **Absent in project** → copy it in.
- **Present** → show the diff and hand-merge with the Edit tool. Never overwrite blindly.

```bash
for f in CLAUDE.md .gitignore .editorconfig detekt.yml cliff.toml; do
    if [[ -f "$TARGET/$f" ]]; then
        echo "=== diff: $f (existing ← → kmp-forge) ==="
        git --no-index --no-pager diff "$TARGET/$f" "/tmp/kmpf-root/$f" || true
    else
        cp "/tmp/kmpf-root/$f" "$TARGET/$f" && echo "added: $f"
    fi
done
```

Special-case `CLAUDE.md`: the generated one links to all the `docs/<area>.md` rules and declares the stack — if the project already has a CLAUDE.md, **merge the kmp-forge sections in** (stack table, locked rules, doc links) rather than replacing the user's existing guidance. Use the Edit tool; confirm with the user.

### 5. Phase A — CI workflows

```bash
if [[ -d "$TARGET/.github/workflows" ]] && ls "$TARGET/.github/workflows"/*.yml >/dev/null 2>&1; then
    mkdir -p /tmp/kmpf-ci
    bash "$SH" render "$OVERLAY/ci" /tmp/kmpf-ci
    echo "⚠ existing workflows found — DON'T clobber. Merge the gate into yours:"
    echo "   required job: ./gradlew spotlessCheck detekt build koverVerify"
    echo "   rendered reference in /tmp/kmpf-ci"
else
    mkdir -p "$TARGET/.github/workflows" "$TARGET/.github/ISSUE_TEMPLATE"
    bash "$SH" render "$OVERLAY/ci" "$TARGET/.github/workflows"
    cp "$OVERLAY/git/pull_request_template.md" "$TARGET/.github/pull_request_template.md"
    cp "$OVERLAY/git/ISSUE_TEMPLATE/"*.yml "$TARGET/.github/ISSUE_TEMPLATE/"
fi
```

The non-negotiable CI gate is `spotlessCheck detekt build koverVerify` (ktlint via Spotless, Kover target 75%). However it lands in the user's workflows, that gate must be present.

### 6. Phase A — build-logic adoption (ask: how deep)

Convention plugins (`KmpLibrary`, `ComposeApp`) are how the stack stays consistent, but adopting them rewrites every module's `build.gradle.kts`. Offer three levels via `AskUserQuestion`:

1. **Lint-only (lightest, default)** — skip convention plugins; just ensure Spotless + detekt + Kover are applied (root or per-module) so the CI gate passes. Existing build setup untouched.
2. **Add, don't rewire** — copy `build-logic/` + `includeBuild("build-logic")` into `pluginManagement { }`, but leave modules on their current build files. Plugins available, adopted later per-module.
3. **Full adopt (heaviest)** — levels 2 + rewrite each module to `id("kmp.library")` / `id("kmp.compose-app")`. Big change; do per-module and build after each.

For levels 2/3:

```bash
mkdir -p "$TARGET/build-logic"
cp -R "$OVERLAY/build-logic/." "$TARGET/build-logic/"
# Insert includeBuild("build-logic") as first line inside pluginManagement { } via the Edit tool.
# Idempotent — skip if already present. If no pluginManagement block, prepend:
#   pluginManagement { includeBuild("build-logic") }
```

### 7. Phase A — modules

- If the project **already has** ui/domain/data layering → **skip `render-module`** (it would duplicate). Only the patterns matter (Phase B), not new skeletons.
- If a layer is **missing** and the user wants it → render that module to scratch and lift files in, fixing package paths:

```bash
for module in ui domain data; do   # only the missing ones
    bash "$SH" render-module "$module" "$OVERLAY/modules/$module" \
        /tmp/kmpf-mod-"$module" "$BASE_PACKAGE_PATH"
done
```

Then `patch-settings` only for **genuinely new** modules (idempotent — skips existing):

```bash
bash "$SH" patch-settings "$TARGET" "<comma-list-of-NEW-modules-only>"
```

### 8. Phase B — audit (reviewer-driven work-list)

Invoke the **`kmp-reviewer`** agent across the existing code — domain, data, every feature, and the app module. Aggregate its findings (`path:line: 🔴/🟡/🟢: problem. fix.`).

Turn the findings into a **dependency-ordered work-list** — foundations first so each layer compiles before the next depends on it:

1. `dispatchers` — **`DispatcherProvider`** define + inject; replace every `Dispatchers.IO/Default/Main` in `:domain`/`:data`/`:feature-*`. (Touches everything — do first.)
2. `result` — **`Result<T, DomainError>`** define sealed `DomainError`; convert use cases from throws → `Result`; remove `try/catch` from `intent {}`.
3. `repos` — **One repo per domain type** split any `AppRepository`/`DataRepository` god object.
4. `koin` — **Koin constructor injection** remove `GlobalContext.get()`/`KoinComponent`; `viewModelOf(::X)`, `koinViewModel<T>()`.
5. `orbit` — **Orbit state-only events** `ContainerHost<State, Nothing>`; replace every `postSideEffect` with a consumable state slot (`pendingX: ...?` set in intent, cleared by paired `onXConsumed()` intent the UI calls after `LaunchedEffect`). Biggest surface; per-feature.
6. `nav` — **Typed Nav 3** `@Serializable ... : NavKey` routes + `NavDisplay` `when`; remove string keys.
7. `module-deps` — enforce `:domain` pure Kotlin / `:feature-*` → `:domain` + `:ui` only / no feature → feature / `:data` never imports `:ui`.
8. `tests` — move MockK out of `commonTest` → fakes + `ContainerHost.test()` harness.
9. `a11y` (🟡) — `contentDescription`, `start/end` not `left/right`, user strings → `Res.string`, typography over hardcoded `.sp`.

The layer keys above map 1:1 to the `layer` input of the **`kmp-migrator`** agent.

Canonical rules: read the matching `docs/<area>.md` before each layer —
[architecture](https://github.com/arthurnagy/kmp-forge/blob/main/docs/architecture.md) ·
[stack](https://github.com/arthurnagy/kmp-forge/blob/main/docs/stack.md) ·
[testing](https://github.com/arthurnagy/kmp-forge/blob/main/docs/testing.md) ·
[secrets](https://github.com/arthurnagy/kmp-forge/blob/main/docs/secrets.md) ·
[i18n-a11y](https://github.com/arthurnagy/kmp-forge/blob/main/docs/i18n-a11y.md).

Present the plan first (counts per layer). Then refactor **one layer at a time** by delegating to the **`kmp-migrator`** agent — pass `project_root`, `base_package`, `claude_plugin_root`, and `layer` (the key from the list above). The migrator establishes `:domain` foundations, applies the codemod, builds, re-greps, and returns a structured report with any `TODO(kmp-forge)` decisions it refused to guess. Run the layers **top-down in order**, with the user confirming between layers — do NOT fire them all at once. The Orbit and repos layers are large; the migrator scopes them per-feature / per-type, so invoke it once per feature (pass `target`). After each layer, re-run `kmp-reviewer` on the touched files to confirm the violations are gone.

> **`result` layer note:** the locked stack uses [kotlin-result](https://github.com/michaelbull/kotlin-result)'s two-param `Result<V, E>` (`com.github.michaelbull.result.*`), not stdlib `kotlin.Result`. The migrator wires `kotlin-result` + `kotlin-result-coroutines` into the catalog and `api(libs.kotlin.result)` into `:domain` before converting use cases. If the existing project already standardized on another result type (Arrow `Either`, a project-local sealed type), tell the migrator via `target`/notes so it adapts instead of introducing a second convention.

### 9. Verify

After Phase A and each Phase-B layer:

```bash
./gradlew spotlessCheck detekt build koverVerify
```

Green = that slice is adopted. Re-run `kmp-reviewer` until it reports `No findings.`

### 10. Report

Print what changed and what remains:

```
✓ Branch: chore/adopt-kmp-forge
✓ Version catalog: kmp-forge libs merged (additive)
✓ Docs: docs/<...> added/merged
✓ CI gate: spotlessCheck detekt build koverVerify present
~ CLAUDE.md / .gitignore / detekt.yml: merged (review the diffs)
~ build-logic: <level chosen>

Phase B refactor remaining (from kmp-reviewer):
  <N> blocking, <N> warn, <N> nits — by layer:
  [ ] DispatcherProvider     <count>
  [ ] Result + DomainError   <count>
  [ ] one-repo-per-type      <count>
  [ ] Koin constructor DI    <count>
  [ ] Orbit state-only       <count>  (per-feature)
  [ ] Typed Nav 3            <count>
  [ ] Module deps            <count>
  [ ] Tests (fakes)          <count>
  [ ] a11y / i18n            <count>

Next:
  1. Work the layers top-down; re-run `kmp-reviewer` after each.
  2. ./gradlew spotlessCheck detekt build koverVerify must pass before merge.
  3. Open a PR from chore/adopt-kmp-forge — do NOT push to main.
```

## Notes

- This command is **non-destructive by design**: additive merges run automatically; anything that could overwrite is diffed and hand-merged. If `apply-overlay.sh` errors, surface it verbatim and stop — let the user inspect (the branch makes it safe).
- Phase B is a guided refactor, not magic. Large surfaces (Orbit per-feature, build-logic full adopt) are done incrementally with build + reviewer checks between steps.
- Do NOT push to GitHub or enable branch protection — the user opts in manually.
