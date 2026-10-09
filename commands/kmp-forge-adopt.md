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
export USE_OPENSPEC="<yes|no — see below>"
# SPEC_WORKFLOW: copy the whole `if [[ "$USE_OPENSPEC" == yes ]]; then export SPEC_WORKFLOW='…' else … fi`
# block from /kmp-forge-init step 4 verbatim. Keep its SINGLE quotes — the text is full of backticks,
# which double quotes would execute as commands.
```

`MODULE_LIST`/`FEATURE_LIST`/`PLATFORM_LIST` must reflect reality — they feed the generated `CLAUDE.md`.

**Spec workflow** — `USE_OPENSPEC=yes` when the project already has an `openspec/` directory.
Otherwise ask via `AskUserQuestion`, exactly like `/kmp-forge-init` step 1 question 7 (OpenSpec
recommended; OpenSpec ≥ 1.14 per init step 1b — never install the CLI without the user's answer).

### 3. Phase A — safe-additive (automatic)

These only ever **add** — every copy below is guarded so an existing file is never replaced
(existing ones go to scratch for a diff + hand-merge, like step 4):

```bash
OVERLAY="${CLAUDE_PLUGIN_ROOT}/overlay"
SH="${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh"
# copy_new <src> <dest>: copy only if dest is absent; otherwise print the diff for a hand-merge.
copy_new() {
    if [[ -e "$2" ]]; then
        echo "=== exists, not replaced — diff (existing ← → kmp-forge): $2"
        git --no-pager diff --no-index "$2" "$1" || true
    else
        mkdir -p "$(dirname "$2")" && cp "$1" "$2" && echo "added: $2"
    fi
}

# Version catalog: additive merge — skips existing keys, appends under "# --- kmp-forge additions ---"
bash "$SH" patch-libs "$TARGET" "$OVERLAY/gradle/libs.versions.toml.additions.tmpl"

# Secrets hygiene: gitleaks config + pre-commit hook
copy_new "$OVERLAY/git/.gitleaks.toml" "$TARGET/.gitleaks.toml"
copy_new "$OVERLAY/git/pre-commit-hook.sh" "$TARGET/.kmp-forge-pre-commit.sh"
chmod +x "$TARGET/.kmp-forge-pre-commit.sh"
HOOK="$(git -C "$TARGET" rev-parse --git-path hooks/pre-commit)"; [[ "$HOOK" = /* ]] || HOOK="$TARGET/$HOOK"
if [[ ! -e "$HOOK" ]]; then
    mkdir -p "$(dirname "$HOOK")" && cp "$TARGET/.kmp-forge-pre-commit.sh" "$HOOK" && chmod +x "$HOOK" && echo "installed: pre-commit hook"
elif ! grep -q "kmp-forge-pre-commit" "$HOOK"; then
    echo "⚠ a pre-commit hook already exists ($HOOK) — chain ours instead of replacing it:"
    echo '    "$(git rev-parse --show-toplevel)/.kmp-forge-pre-commit.sh" || exit 1'
fi
```

(For an existing hook, add that line with the Edit tool after confirming with the user; for a hook
manager like Husky/lefthook/pre-commit, register the script there instead.)

**Toolchain floor** — ask first (`AskUserQuestion`, default yes): kmp-forge's templates target AGP
≥ 9.4.1 and Gradle ≥ 9.8.1. `pin-toolchain` only ever raises (never downgrades) the catalog's `agp`
and the wrapper; `--ios` also raises the daemon heap for Kotlin/Native framework links:

```bash
bash "$SH" pin-toolchain "$TARGET" [--ios]
```

**Product docs** (`docs/MVP_SPEC.md`, `docs/DECISIONS/`) — fill gaps file by file, never clobber.
The ADRs are added even when the project already has a spec:

```bash
rm -rf /tmp/kmpf-product && bash "$SH" render "$OVERLAY/product" /tmp/kmpf-product
copy_new /tmp/kmpf-product/MVP_SPEC.md "$TARGET/docs/MVP_SPEC.md"
for adr in /tmp/kmpf-product/DECISIONS/*.md; do
    copy_new "$adr" "$TARGET/docs/DECISIONS/$(basename "$adr")"
done
```

Report each result.

**OpenSpec** (`USE_OPENSPEC=yes`) — kmp-forge's project rules live in `openspec/config.yaml`:

```bash
rm -rf /tmp/kmpf-openspec && bash "$SH" render "$OVERLAY/openspec" /tmp/kmpf-openspec
if [[ -d "$TARGET/openspec" ]]; then
    # Already spec-driven: merge kmp-forge's context/rules/operations into the existing config
    # by hand (Edit tool) — keep the project's own rules, add ours where they don't conflict.
    copy_new /tmp/kmpf-openspec/config.yaml "$TARGET/openspec/config.yaml"
else
    openspec init --tools claude --no-animation "$TARGET"
    cp /tmp/kmpf-openspec/config.yaml "$TARGET/openspec/config.yaml"   # replaces init's fresh stub
fi
```

**Issue labels** — the backlog is GitHub issues labeled `ready`. If `origin` is a GitHub repo, ask
(`AskUserQuestion`, default yes) before creating the workflow labels there — it writes to GitHub:

```bash
(cd "$TARGET" && bash "${CLAUDE_PLUGIN_ROOT}/scripts/issues.sh" labels)
```

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
        git --no-pager diff --no-index "$TARGET/$f" "/tmp/kmpf-root/$f" || true
    else
        cp "/tmp/kmpf-root/$f" "$TARGET/$f" && echo "added: $f"
    fi
done
```

Special-case `CLAUDE.md`: the generated one links to all the `docs/<area>.md` rules and declares the stack — if the project already has a CLAUDE.md, **merge the kmp-forge sections in** (stack table, locked rules, doc links) rather than replacing the user's existing guidance. Use the Edit tool; confirm with the user.

### 5. Phase A — CI workflows

Per file, never replacing an existing one — so a project with other workflows still gets
`pr.yml` (the gate `/kmp-forge-add-autoloop` requires), `release.yml` and `spec-link.yml` (a
no-op without `openspec/`), and the PR/issue templates are added only where missing:

```bash
rm -rf /tmp/kmpf-ci && bash "$SH" render "$OVERLAY/ci" /tmp/kmpf-ci
for wf in pr.yml release.yml spec-link.yml; do
    copy_new "/tmp/kmpf-ci/$wf" "$TARGET/.github/workflows/$wf"
done
copy_new "$OVERLAY/git/pull_request_template.md" "$TARGET/.github/pull_request_template.md"
for t in "$OVERLAY/git/ISSUE_TEMPLATE/"*.yml; do
    copy_new "$t" "$TARGET/.github/ISSUE_TEMPLATE/$(basename "$t")"
done
ls "$TARGET/.github/workflows"/*.yml   # other workflows: check they don't duplicate the gate
```

If the project's own workflows already run checks, make sure exactly one of them runs the gate
(`spotlessCheck detekt build koverVerify`) — merge rather than running it twice.

The non-negotiable CI gate is `spotlessCheck detekt build koverVerify` (ktlint via Spotless, Kover target 75%). However it lands in the user's workflows, that gate must be present.

### 6. Phase A — build-logic adoption (ask: how deep)

The `kmp-forge.kmp.library` precompiled-script convention plugin is how the stack stays consistent, but adopting it rewrites every module's `build.gradle.kts`. (There is a single convention plugin — the old `ComposeApp` / `kmp-forge.compose.app` convention plugin was removed; modules apply Compose directly via `alias(libs.plugins.composeMultiplatform)` + `alias(libs.plugins.composeCompiler)`, and the Android target via `alias(libs.plugins.androidMultiplatformLibrary)` + a `kotlin { android { } }` block.) Offer three levels via `AskUserQuestion`:

1. **Lint-only (lightest, default)** — skip the convention plugin; just ensure Spotless + detekt + Kover are applied (root or per-module) so the CI gate passes. Existing build setup untouched.
2. **Add, don't rewire** — copy `build-logic/` + `includeBuild("build-logic")` into `pluginManagement { }`, but leave modules on their current build files. Plugin available, adopted later per-module.
3. **Full adopt (heaviest)** — levels 2 + rewrite each module to `id("kmp-forge.kmp.library")`, then layer Compose/Android on the modules that need it (`alias(libs.plugins.composeMultiplatform)` + `alias(libs.plugins.composeCompiler)`; `alias(libs.plugins.androidMultiplatformLibrary)` + `kotlin { android {} }`). Big change; do per-module and build after each.

For levels 2/3 — never over an existing `build-logic/` (a project may already have its own
convention plugins there):

```bash
if [[ -d "$TARGET/build-logic" ]]; then
    # Existing build-logic: add only the kmp-forge convention scripts it lacks; merge
    # build.gradle.kts / settings.gradle.kts dependencies by hand (git --no-index diff).
    for f in $(cd "$OVERLAY/build-logic" && find . -type f); do
        copy_new "$OVERLAY/build-logic/$f" "$TARGET/build-logic/$f"
    done
else
    mkdir -p "$TARGET/build-logic" && cp -R "$OVERLAY/build-logic/." "$TARGET/build-logic/"
fi
# Insert includeBuild("build-logic") as first line inside pluginManagement { } via the Edit tool.
# Idempotent — skip if already present. If no pluginManagement block, prepend:
#   pluginManagement { includeBuild("build-logic") }
# Then add `id("kmp-forge.root")` to the root build.gradle.kts plugins { } block: the root
# convention owns the aggregated Kover gate (>= 75%) and loads build-logic (and its
# Spotless/Detekt/Kover) once in the root classloader — without it Spotless 8's shared build
# service fails configuration as soon as two modules apply the convention.
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

`:testing` (shared test doubles — `TestDispatcherProvider(testScheduler)`) is new in any project;
render it directly when the project has no module of that name, then add it to `patch-settings`:

```bash
[[ -e "$TARGET/testing" ]] || bash "$SH" render-module testing "$OVERLAY/modules/testing" "$TARGET/testing" "$BASE_PACKAGE_PATH"
```

**Composition root.** `/kmp-forge-add-feature` wires features at `// kmp-forge:` markers in the app module's `AppModules.kt` (Koin module list) and `AppNavigation.kt` (route `SerializersModule` + `entryProvider { }`). Render the reference files to scratch — never over an existing `App.kt`:

```bash
export APP_NAME_LOWER="$(echo "<rootProject.name>" | tr '[:upper:]' '[:lower:]')"   # Res package of :shared
bash "$SH" render-module "" "$OVERLAY/shared" /tmp/kmpf-shared "$BASE_PACKAGE_PATH"
```

If the project has no Koin bootstrap / `NavDisplay` yet, lift the files into the composition module (`:shared` or `:composeApp`) and make the platform entry points render its `App()`. If it already has them, merge the pattern by hand: a single module list, a `SavedStateConfiguration` registering every route, `entryProvider { addXEntries(...) }`, and the two marker comments. Add the matching dependencies (`koin-compose`, `koin-compose-viewmodel`, `androidx-navigation3-ui` (the JetBrains Nav 3 port — it re-exports the runtime; don't add Google's artifacts alongside it), `androidx-lifecycle-viewmodel-navigation3`, `kotlinx-serialization-json` + the serialization plugin).

Module build scripts reference sibling modules as `project(":domain")` — no type-safe `projects.` accessors, so they work whether or not the project enables `TYPESAFE_PROJECT_ACCESSORS`.

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
5. `orbit` — **Orbit state-only events** `OrbitContainerHost<State, State, Nothing>` (+ `orbitContainer(...)`; Orbit 12 deprecates `ContainerHost`/`container(...)`); replace every `postSideEffect` with a consumable state slot (`pendingX: ...?` set in intent, cleared by paired `onXConsumed()` intent the UI calls after `LaunchedEffect`). Biggest surface; per-feature.
6. `nav` — **Typed Nav 3** `@Serializable ... : NavKey` routes; migrate the app's `NavDisplay { when }` → per-feature `addXEntries(...)` contributions composed in `entryProvider { }`; register every route in the back stack's `SavedStateConfiguration` `SerializersModule`; remove string keys.
7. `module-deps` — enforce `:domain` pure Kotlin / `:feature-*` → `:domain` + `:ui` only / no feature → feature / `:data` never imports `:ui`.
8. `visibility` — **Restrictive visibility + explicit state** repo impls/data sources/DTOs/`RealDispatcherProvider` → `internal`; feature `State`/`ViewModel`/`Screen` → `internal` (`Content` → `private`); drop default values from domain entities + `State`; add `State.Initial` companion (use cases keep public ctors). Run after `nav` + `module-deps`.
9. `tests` — move MockK out of `commonTest` → fakes + Orbit's `test()` harness (seed with `State.Initial`).
10. `a11y` (🟡) — `contentDescription`, `start/end` not `left/right`, user strings → `Res.string`, typography over hardcoded `.sp`.

The layer keys above map 1:1 to the `layer` input of the **`kmp-migrator`** agent.

Canonical rules: read the matching `docs/<area>.md` before each layer —
[architecture](https://github.com/arthurnagy/kmp-forge/blob/main/docs/architecture.md) ·
[stack](https://github.com/arthurnagy/kmp-forge/blob/main/docs/stack.md) ·
[testing](https://github.com/arthurnagy/kmp-forge/blob/main/docs/testing.md) ·
[secrets](https://github.com/arthurnagy/kmp-forge/blob/main/docs/secrets.md) ·
[i18n-a11y](https://github.com/arthurnagy/kmp-forge/blob/main/docs/i18n-a11y.md).

Present the plan first (counts per layer). Then refactor **one layer at a time** by delegating to the **`kmp-migrator`** agent — pass `project_root`, `base_package`, `claude_plugin_root`, and `layer` (the key from the list above). The migrator establishes `:domain` foundations, applies the codemod, builds, re-greps, and returns a structured report with any `TODO(kmp-forge)` decisions it refused to guess. Run the layers **top-down in order**, with the user confirming between layers — do NOT fire them all at once. The Orbit and repos layers are large; the migrator scopes them per-feature / per-type, so invoke it once per feature (pass `target`). After each layer, re-run `kmp-reviewer` on the touched files to confirm the violations are gone.

> **`result` layer note:** the locked stack uses [kotlin-result](https://github.com/michaelbull/kotlin-result)'s two-param `Result<V, E>` (package `com.github.michaelbull.result`, explicit imports, `onOk`/`onErr`), not stdlib `kotlin.Result`. The migrator wires `kotlin-result` + `kotlin-result-coroutines` into the catalog and `api(libs.kotlin.result)` into `:domain` before converting use cases. If the existing project already standardized on another result type (Arrow `Either`, a project-local sealed type), tell the migrator via `target`/notes so it adapts instead of introducing a second convention.

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
✓ CI gate: spotlessCheck detekt build koverVerify present (+ spec-link)
✓ Spec workflow: <OpenSpec with kmp-forge rules | plain docs>; issue labels <created | skipped>
~ CLAUDE.md / .gitignore / detekt.yml: merged (review the diffs)
~ build-logic: <level chosen>

Phase B refactor remaining (from kmp-reviewer):
  <N> blocking, <N> warn, <N> nits — by layer:
  [ ] DispatcherProvider     <count>
  [ ] Result + DomainError   <count>
  [ ] one-repo-per-type      <count>
  [ ] Koin constructor DI    <count>
  [ ] Orbit state-only       <count>  (per-feature)
  [ ] Typed Nav 3 + entries  <count>
  [ ] Module deps            <count>
  [ ] Visibility + explicit  <count>
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
