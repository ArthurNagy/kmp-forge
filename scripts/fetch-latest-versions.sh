#!/usr/bin/env bash
#
# Query Maven Central and Google Maven for the latest stable versions of every
# locked-stack library. Prints a TOML-like report; does NOT modify any file.
#
# Used by /kmp-forge-bump-stack — the slash command parses this output, diffs
# against the project's libs.versions.toml, and proposes an updated catalog
# in a single commit.
#
# Usage:
#   fetch-latest-versions.sh [json|toml]    (default: toml)

set -euo pipefail

fmt="${1:-toml}"

# coord: group:artifact:version-ref-name
# version-ref-name is the [versions] key used in our libs.versions.toml.additions.tmpl
declare -a coords=(
    "org.orbit-mvi:orbit-core:orbitMvi:maven-central"
    "io.insert-koin:koin-core:koin:maven-central"
    "io.coil-kt.coil3:coil-compose:coil:maven-central"
    "io.ktor:ktor-client-core:ktor:maven-central"
    "co.touchlab:kermit:kermit:maven-central"
    "org.jetbrains.kotlinx:kotlinx-coroutines-core:kotlinxCoroutines:maven-central"
    "org.jetbrains.kotlinx:kotlinx-datetime:kotlinxDatetime:maven-central"
    "org.jetbrains.kotlinx:kotlinx-serialization-json:kotlinxSerialization:maven-central"
    "org.jetbrains.androidx.lifecycle:lifecycle-viewmodel:androidxLifecycle:maven-central"
    "androidx.navigation3:navigation3-ui:androidxNavigation3:google-maven"
    "androidx.datastore:datastore-core:androidxDatastore:google-maven"
    "app.cash.sqldelight:runtime:sqldelight:maven-central"
    "app.cash.turbine:turbine:turbine:maven-central"
    "io.gitlab.arturbosch.detekt:detekt-cli:detekt:maven-central"
    "org.jetbrains.kotlin:kotlin-stdlib:kotlinGradlePlugin:maven-central"
    "com.android.tools.build:gradle:androidGradlePlugin:google-maven"
    "org.jetbrains.compose:compose-gradle-plugin:composeGradlePlugin:maven-central"
)

is_stable() {
    local v="$1"
    [[ ! "$v" =~ -alpha|-beta|-rc|-SNAPSHOT|-dev|-eap|-M[0-9]+ ]]
}

# Authoritative maven-metadata.xml is the source of truth for both repos.
# (The old search.maven.org/solrsearch endpoint lagged the index — it returned
# versions OLDER than current pins, so a blind follow proposed downgrades.)
metadata_base() {
    case "$1" in
        maven-central) echo "https://repo1.maven.org/maven2" ;;
        google-maven)  echo "https://dl.google.com/dl/android/maven2" ;;
    esac
}

# Fetch newest stable version from a repo's maven-metadata.xml. <versions> is in
# chronological release order, so tac yields newest-first; we take the first
# stable. Returns "" on 404 / no stable release (caller emits a WARN line).
fetch_latest() {
    local repo="$1" group="$2" artifact="$3"
    local base group_path url versions
    base="$(metadata_base "$repo")"
    group_path="${group//.//}"
    url="${base}/${group_path}/${artifact}/maven-metadata.xml"
    versions="$(curl -sfL "$url" 2>/dev/null | grep -oE '<version>[^<]+</version>' | sed 's/<[^>]*>//g' | tac || true)"
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        if is_stable "$v"; then echo "$v"; return; fi
    done <<< "$versions"
    echo ""
}

emit_toml() {
    echo "# kmp-forge fetch-latest-versions: $(date -u +%FT%TZ)"
    echo "[versions]"
    for entry in "${coords[@]}"; do
        IFS=':' read -r g a key repo <<< "$entry"
        local v
        v="$(fetch_latest "$repo" "$g" "$a")"
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
        IFS=':' read -r g a key repo <<< "$entry"
        local v
        v="$(fetch_latest "$repo" "$g" "$a")"
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
