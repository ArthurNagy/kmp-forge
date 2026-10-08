#!/usr/bin/env bash
#
# Query Maven Central and Google Maven for the latest versions of every
# locked-stack library. Prints a TOML-like report; does NOT modify any file.
#
# Used by /kmp-forge-bump-stack — the slash command parses this output, diffs
# against the project's libs.versions.toml, and proposes an updated catalog
# in a single commit.
#
# Every emitted key is the [versions] key a kmp-forge project actually uses:
# the toolchain keys come from kmp.new's generated catalog (kotlin, agp,
# composeMultiplatform, androidx-lifecycle, kotlinx-coroutines, material3), the
# rest from overlay/gradle/libs.versions.toml.additions.tmpl.
#
# Usage:
#   fetch-latest-versions.sh [json|toml]    (default: toml)

set -euo pipefail

fmt="${1:-toml}"

# coord: group:artifact:version-key:repo:channel
#   channel "stable" — newest purely numeric version (1.2.3); any qualifier
#                      (-alpha01, -RC, -Beta1, -0.6.x-compat, ...) is skipped.
#   channel "pre"    — the pin itself tracks a pre-release line; report the newest
#                      pre-release unless a stable release at or above its base exists.
#   channel "nav3rt" — derived: the navigation3-runtime version the latest JetBrains
#                      navigation3-ui port requires (the two are versioned
#                      independently; ui 1.1.2 requires runtime 1.1.7).
declare -a coords=(
    # --- toolchain (keys owned by kmp.new's catalog) ---
    "org.jetbrains.kotlin:kotlin-stdlib:kotlin:maven-central:stable"
    "com.android.tools.build:gradle:agp:google-maven:stable"
    "org.jetbrains.compose:compose-gradle-plugin:composeMultiplatform:maven-central:stable"
    # (material3 is deliberately absent: kmp.new pins a material3 build matched to its
    # composeMultiplatform release — bump it together with composeMultiplatform by hand.)
    "org.jetbrains.androidx.lifecycle:lifecycle-viewmodel:androidx-lifecycle:maven-central:stable"
    "org.jetbrains.kotlinx:kotlinx-coroutines-core:kotlinx-coroutines:maven-central:stable"
    # --- locked stack (keys owned by the overlay additions) ---
    "org.orbit-mvi:orbit-core:orbitMvi:maven-central:stable"
    "io.insert-koin:koin-core:koin:maven-central:stable"
    "io.coil-kt.coil3:coil-compose:coil:maven-central:stable"
    "io.ktor:ktor-client-core:ktor:maven-central:stable"
    "co.touchlab:kermit:kermit:maven-central:stable"
    "org.jetbrains.kotlinx:kotlinx-datetime:kotlinxDatetime:maven-central:stable"
    "org.jetbrains.kotlinx:kotlinx-serialization-json:kotlinxSerialization:maven-central:stable"
    "org.jetbrains.androidx.navigation3:navigation3-ui:androidxNavigation3:maven-central:stable"
    "org.jetbrains.androidx.navigation3:navigation3-ui:androidxNavigation3Runtime:maven-central:nav3rt"
    "androidx.datastore:datastore-core:androidxDatastore:google-maven:stable"
    "app.cash.sqldelight:runtime:sqldelight:maven-central:stable"
    "app.cash.turbine:turbine:turbine:maven-central:stable"
    "com.michael-bull.kotlin-result:kotlin-result:kotlinResult:maven-central:stable"
    "org.mobilenativefoundation.store:store5:store:maven-central:pre"
    # --- quality gates ---
    "io.gitlab.arturbosch.detekt:detekt-cli:detekt:maven-central:stable"
    "com.diffplug.spotless:spotless-plugin-gradle:spotless:maven-central:stable"
    "com.pinterest.ktlint:ktlint-cli:ktlint:maven-central:stable"
    "org.jetbrains.kotlinx:kover-gradle-plugin:kover:maven-central:stable"
)

# Authoritative maven-metadata.xml is the source of truth for both repos.
# (The old search.maven.org/solrsearch endpoint lagged the index — it returned
# versions OLDER than current pins, so a blind follow proposed downgrades.)
repo_base() {
    case "$1" in
        maven-central) echo "https://repo1.maven.org/maven2" ;;
        google-maven)  echo "https://dl.google.com/dl/android/maven2" ;;
    esac
}

# All published versions, one per line, in version order (oldest first).
# <versions> in maven-metadata.xml is deploy order, NOT version order — a 2.4.21
# patch deployed after 2.5.0-Beta1 would otherwise read as "latest". `sort -V`
# exists in both GNU coreutils and stock macOS sort (no `tac` dependency).
list_versions() {
    local repo="$1" group="$2" artifact="$3"
    curl -sfL "$(repo_base "$repo")/${group//.//}/${artifact}/maven-metadata.xml" 2>/dev/null \
        | grep -oE '<version>[^<]+</version>' | sed 's/<[^>]*>//g' | sort -V || true
}

is_stable() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]]; }

# Version-order comparison: true if $1 >= $2.
version_ge() { [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]; }

fetch_latest() {
    local repo="$1" group="$2" artifact="$3" channel="$4"
    local versions stable pre
    versions="$(list_versions "$repo" "$group" "$artifact")"
    stable="$(grep -E '^[0-9]+(\.[0-9]+)*$' <<< "$versions" | tail -1 || true)"
    case "$channel" in
        stable)
            echo "$stable"
            ;;
        pre)
            pre="$(grep -vE '^[0-9]+(\.[0-9]+)*$|SNAPSHOT|-compat' <<< "$versions" | tail -1 || true)"
            if [[ -z "$pre" ]] || { [[ -n "$stable" ]] && version_ge "$stable" "${pre%%-*}"; }; then
                echo "$stable"
            else
                echo "$pre"
            fi
            ;;
        nav3rt)
            [[ -z "$stable" ]] && { echo ""; return; }
            # Gradle module metadata (pretty-printed JSON): the root variant's dependency
            # block lists "module": "navigation3-runtime" followed by "requires": "<ver>".
            curl -sfL "$(repo_base "$repo")/${group//.//}/${artifact}/${stable}/${artifact}-${stable}.module" 2>/dev/null \
                | grep -A4 '"module": "navigation3-runtime"' \
                | grep -oE '"requires": "[^"]+"' | head -1 | cut -d'"' -f4 || true
            ;;
    esac
}

emit_toml() {
    echo "# kmp-forge fetch-latest-versions: $(date -u +%FT%TZ)"
    echo "[versions]"
    for entry in "${coords[@]}"; do
        IFS=':' read -r g a key repo channel <<< "$entry"
        local v
        v="$(fetch_latest "$repo" "$g" "$a" "$channel")"
        if [[ -z "$v" ]]; then
            echo "# WARN $key ($g:$a) — not found"
        else
            echo "$key = \"$v\""
        fi
    done
}

emit_json() {
    echo "{"
    local first=1
    for entry in "${coords[@]}"; do
        IFS=':' read -r g a key repo channel <<< "$entry"
        local v
        v="$(fetch_latest "$repo" "$g" "$a" "$channel")"
        [[ $first -eq 1 ]] || echo ","
        first=0
        printf '  "%s": "%s"' "$key" "$v"
    done
    echo
    echo "}"
}

case "$fmt" in
    toml) emit_toml ;;
    json) emit_json ;;
    *) echo "usage: $0 [json|toml]" >&2; exit 1 ;;
esac
