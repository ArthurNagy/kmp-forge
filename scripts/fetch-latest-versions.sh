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
    "org.jetbrains.androidx.lifecycle:lifecycle-viewmodel:androidxLifecycle:google-maven"
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

fetch_maven_central() {
    local group="$1" artifact="$2"
    local url="https://search.maven.org/solrsearch/select?q=g:%22${group}%22+AND+a:%22${artifact}%22&rows=20&core=gav&wt=json"
    local versions
    versions="$(curl -sfL "$url" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for r in d.get('response',{}).get('docs',[]):
        v=r.get('v')
        if v: print(v)
except Exception:
    pass
" || true)"
    while IFS= read -r v; do
        if is_stable "$v"; then echo "$v"; return; fi
    done <<< "$versions"
    echo ""
}

fetch_google_maven() {
    local group="$1" artifact="$2"
    local group_path="${group//.//}"
    local url="https://dl.google.com/dl/android/maven2/${group_path}/${artifact}/maven-metadata.xml"
    local versions
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
        local v=""
        case "$repo" in
            maven-central) v="$(fetch_maven_central "$g" "$a")" ;;
            google-maven)  v="$(fetch_google_maven  "$g" "$a")" ;;
        esac
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
        local v=""
        case "$repo" in
            maven-central) v="$(fetch_maven_central "$g" "$a")" ;;
            google-maven)  v="$(fetch_google_maven  "$g" "$a")" ;;
        esac
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
