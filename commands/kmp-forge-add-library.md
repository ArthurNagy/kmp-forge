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

```bash
GROUP="<group>"
ARTIFACT="<artifact>"
# Maven Central:
curl -sL "https://search.maven.org/solrsearch/select?q=g:%22${GROUP}%22+AND+a:%22${ARTIFACT}%22&rows=5&core=gav&wt=json" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(next((r['v'] for r in d.get('response',{}).get('docs',[]) if '-' not in r['v']), ''))"
```

If empty (not Maven Central), try Google Maven:
```bash
GROUP_PATH="${GROUP//.//}"
curl -sL "https://dl.google.com/dl/android/maven2/${GROUP_PATH}/${ARTIFACT}/maven-metadata.xml" \
  | grep -oE '<version>[^<]+</version>' | sed 's/<[^>]*>//g' | grep -v -E -- '-alpha|-beta|-rc' | tail -1
```

### 4. Update `gradle/libs.versions.toml`

Compute a stable key (lowercase, dashes-from-dots, no extension):
- `KEY="${GROUP//.-/-}-${ARTIFACT//./-}"` (e.g. `io-kamel-kamel-image`)
- Or use a cleaner key: just `<artifact>` if not already taken.

Edit `gradle/libs.versions.toml`:
- Add `[versions]` entry: `<key> = "<version>"`
- Add `[libraries]` entry: `<key> = { module = "<group>:<artifact>", version.ref = "<key>" }`

Use the `Edit` tool with `replace_all = false` and unique context to avoid collisions.

### 5. Ask which module to add to

`AskUserQuestion`: which module's `build.gradle.kts` to add the implementation to. Default to `:data` for networking/persistence libs, `:ui` for Compose libs, `:feature-<name>` for feature-specific deps.

### 6. Add to module's build.gradle.kts

Edit the target module's `build.gradle.kts`:
```kotlin
sourceSets.commonMain.dependencies {
    implementation(libs.<key>)
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
✓ Catalog: gradle/libs.versions.toml — versions.<key> + libraries.<key>
✓ Used in: <target-module>/build.gradle.kts
✓ Build: green | red
```
