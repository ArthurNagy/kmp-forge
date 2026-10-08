---
description: Search klibs.io for a KMP library, present matches, and add the chosen one to gradle/libs.versions.toml plus a target module.
argument-hint: <search-query>
---

# /kmp-forge-add-library

Library discovery via [klibs.io](https://klibs.io/) (JetBrains' KMP library directory). klibs.io has no JSON API, so this is best-effort web parsing.

## Arguments

- **`<search-query>`**: free-form, e.g. `"image cropping"`, `"work manager"`, `"date picker"`

## Flow

### 1. Fetch klibs.io search results

```bash
QUERY="<query>"
QUERY_URL_ENCODED="$(echo "$QUERY" | sed 's/ /+/g')"
```

Use `WebFetch` against `https://klibs.io/search?query=${QUERY_URL_ENCODED}` to retrieve the search results page. Parse the page to extract library entries (name, group, artifact, KMP targets, last updated, brief description).

If WebFetch can't parse the HTML reliably (klibs.io is a SPA — likely client-rendered), fall back to:
- Print the URL `https://klibs.io/search?query=${QUERY_URL_ENCODED}` for the user to open in browser
- Ask the user to paste the artifact coordinates (e.g. `io.kamel:kamel-image:1.0.5`)

### 2. Present candidates

Show top 5 matches with `AskUserQuestion`: artifact coords + target set + brief description. User picks one.

### 3. Resolve latest stable version

Read the repository's authoritative `maven-metadata.xml` (the old `search.maven.org/solrsearch` index lags months behind and returns stale versions). `<versions>` there is in deploy order, so sort by version and keep only purely numeric releases (`1.2.3` — no `-alpha`/`-beta`/`-RC`/`-compat`):

```bash
GROUP="<group>"          # e.g. media.kamel
ARTIFACT="<artifact>"    # e.g. kamel-image
GROUP_PATH="${GROUP//.//}"
latest_stable() {  # $1 = repository base URL → newest purely numeric version, or ""
  curl -sfL "$1/${GROUP_PATH}/${ARTIFACT}/maven-metadata.xml" 2>/dev/null \
    | grep -oE '<version>[^<]+</version>' | sed 's/<[^>]*>//g' \
    | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -V | tail -1
}
VERSION="$(latest_stable https://repo1.maven.org/maven2)"                     # Maven Central
[ -n "$VERSION" ] || VERSION="$(latest_stable https://dl.google.com/dl/android/maven2)"   # Google Maven
```

(`sort -V` exists in both GNU coreutils and stock macOS `sort`; the snippet runs unchanged in bash and zsh.) If `VERSION` is still empty, the library has no stable release on either repository: list the newest pre-releases (drop the numeric filter, `| sort -V | tail -5`) and ask the user via `AskUserQuestion` whether to pin one — never pick a pre-release silently.

### 4. Update `gradle/libs.versions.toml`

Derive keys in the catalog's existing style — **kebab-case library aliases** (`koin-core`, `orbit-compose` → `libs.koin.core`) and **camelCase version keys** (`orbitMvi`, `kotlinxDatetime`):

```bash
LIB_KEY="$(printf '%s' "$ARTIFACT" | tr '[:upper:]' '[:lower:]' | tr '._' '--')"        # kamel-image
# Alias taken? Prefix the group's last segment: media.kamel → kamel-kamel-image
grep -qE "^${LIB_KEY}[[:space:]]*=" gradle/libs.versions.toml \
  && LIB_KEY="$(printf '%s' "${GROUP##*.}" | tr '[:upper:]' '[:lower:]' | tr '._' '--')-${LIB_KEY}"
VERSION_KEY="$(printf '%s' "$LIB_KEY" | awk -F- '{printf "%s", $1; for (i = 2; i <= NF; i++) printf "%s", toupper(substr($i, 1, 1)) substr($i, 2)}')"
                                                                                     # kamelImage
```

Edit `gradle/libs.versions.toml`:
- `[versions]`: `<VERSION_KEY> = "<VERSION>"` — **unless** a sibling artifact of the same library family is already in the catalog (e.g. adding `kamel-decoder` next to `kamel-image`): reuse that entry's `version.ref` so the family stays on one version.
- `[libraries]`: `<LIB_KEY> = { module = "<GROUP>:<ARTIFACT>", version.ref = "<VERSION_KEY>" }`

Two alias pitfalls (checked against Gradle 9.8): an alias whose **first** segment is reserved (`versions`, `bundles`, `plugins`, `class`, `extensions`, …) makes Gradle reject the whole catalog, and a segment that starts with a digit (`lib-3d-viewer`) is accepted but gets **no** type-safe accessor (`libs.lib.3d…` doesn't compile). If the derived key hits either, prefix it with the group's last segment / spell the digit out (`lib-threed-viewer`) and tell the user. The module's accessor is the alias with dashes as dots: `libs.kamel.image`.

Use the `Edit` tool with `replace_all = false` and unique context to avoid collisions.

### 5. Ask which module to add to

`AskUserQuestion`: which module's `build.gradle.kts` to add the implementation to. Default to `:data` for networking/persistence libs, `:ui` for Compose libs, `:feature-<name>` for feature-specific deps.

### 6. Add to module's build.gradle.kts

Edit the target module's `build.gradle.kts`:
```kotlin
sourceSets.commonMain.dependencies {
    implementation(libs.<LIB_KEY with dashes as dots>)
    // existing deps
}
```

### 7. Verify the build

`./gradlew :<target-module>:build`.

### 8. Suggest ADR

If the library is non-trivial (changes architecture, opts into a new paradigm), suggest the user write `docs/DECISIONS/NNNN-add-<lib>.md`.

### 9. Report

```
✓ Added <group>:<artifact>:<version>
✓ Catalog: gradle/libs.versions.toml — versions.<VERSION_KEY> + libraries.<LIB_KEY>
✓ Used in: <target-module>/build.gradle.kts
✓ Build: green | red
```
