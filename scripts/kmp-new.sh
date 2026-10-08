#!/usr/bin/env bash
#
# Get a fresh Kotlin Multiplatform project from JetBrains' wizard (https://kmp.jetbrains.com).
#
# The wizard's form is a plain GET to /generateKmtProject (name, id, buildSystem, locale and a
# JSON `spec`), so the project can be downloaded directly — no browser needed. The wizard page
# also reads its target checkboxes from URL parameters (android=true&ios=true…), which `url`
# uses for the manual fallback; the project NAME and ID are not URL parameters and must still
# be typed into the form there.
#
# The wizard no longer offers a library picker: optional libraries (Ktor, SQLDelight) are wired
# by kmp-forge itself after download (see commands/kmp-forge-init.md step 6).
#
# Usage:
#   kmp-new.sh download "<APP_NAME>" "<BASE_PACKAGE>" "<PLATFORMS_CSV>" "<dest-dir>"
#       Download + unzip the generated project into <dest-dir> (must not exist or be empty).
#       Exit 2 if the generator is unreachable or returns something that isn't a project zip —
#       fall back to `url` + a manual download.
#   kmp-new.sh url "<PLATFORMS_CSV>"
#       Print the wizard URL with the targets pre-selected (manual fallback).
#
#   PLATFORMS_CSV: comma-separated subset of {android,ios,desktop,web}; android is always added.
#   All targets use Compose Multiplatform UI (ios ui=compose, web ui=compose); tests included.

set -euo pipefail

die() { echo "kmp-new: $*" >&2; exit 1; }

GENERATOR="https://kmp.jetbrains.com/generateKmtProject"
WIZARD="https://kmp.jetbrains.com/"

platforms() {
    local csv="android,${1:-}" p out=()
    IFS=',' read -ra items <<< "$csv"
    for p in "${items[@]}"; do
        p="$(echo "$p" | tr '[:upper:]' '[:lower:]' | xargs)"
        [[ -z "$p" ]] && continue
        case "$p" in android|ios|desktop|web) ;; *) die "unknown platform: $p (expected android,ios,desktop,web)" ;; esac
        [[ " ${out[*]-} " == *" $p "* ]] || out+=("$p")
    done
    echo "${out[@]}"
}

cmd_url() {
    local query="" p
    for p in $(platforms "${1:-}"); do
        query+="${p}=true&"
        [[ "$p" == ios || "$p" == web ]] && query+="${p}ui=compose&"
    done
    echo "${WIZARD}?${query}includeTests=true"
}

cmd_download() {
    local app_name="$1" base_package="$2" platforms_csv="$3" dest="$4"
    [[ "$app_name" =~ ^[A-Z][A-Za-z0-9]*$ ]] || die "APP_NAME must be PascalCase alphanumeric: '$app_name'"
    [[ "$base_package" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]] || die "BASE_PACKAGE must be reverse-domain lowercase: '$base_package'"
    if [[ -e "$dest" && -n "$(ls -A "$dest" 2>/dev/null)" ]]; then die "destination is not empty: $dest"; fi
    command -v unzip >/dev/null || die "unzip not found"

    local targets="" p
    for p in $(platforms "$platforms_csv"); do
        targets+="\"$p\":{\"ui\":[\"compose\"]},"
    done
    local spec="{\"template_id\":\"kmt\",\"targets\":{${targets%,}},\"include_tests\":true}"
    local enc_spec
    enc_spec="$(python3 -I -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$spec")"

    local work zip
    work="$(mktemp -d)"
    zip="$work/project.zip"
    trap 'rm -rf "$work"' RETURN
    if ! curl -sfL --max-time 120 -o "$zip" \
        "${GENERATOR}?name=${app_name}&id=${base_package}&buildSystem=gradle&locale=en-us&spec=${enc_spec}"; then
        echo "kmp-new: generator request failed — use: $0 url \"$platforms_csv\"" >&2
        exit 2
    fi
    if ! unzip -tq "$zip" >/dev/null 2>&1; then
        echo "kmp-new: generator did not return a zip — use: $0 url \"$platforms_csv\"" >&2
        exit 2
    fi

    # The zip holds a single top-level folder named after the app; lift its contents (incl.
    # dotfiles) into <dest>. Extracted into a fresh temp dir — never into the destination.
    mkdir -p "$work/x" "$dest"
    unzip -q "$zip" -d "$work/x"
    local inner
    inner="$(find "$work/x" -mindepth 1 -maxdepth 1 -type d | head -1)"
    [[ -n "$inner" && -f "$inner/settings.gradle.kts" ]] || die "unexpected archive layout (no settings.gradle.kts)"
    (shopt -s dotglob && mv "$inner"/* "$dest/")
    echo "kmp-new: downloaded $(cd "$dest" && ls -d */ | tr -d '/' | tr '\n' ' ')into $dest"
}

[[ $# -ge 1 ]] || die "usage: $0 download <APP_NAME> <BASE_PACKAGE> <PLATFORMS_CSV> <dest-dir> | url <PLATFORMS_CSV>"
cmd="$1"; shift
case "$cmd" in
    download) [[ $# -eq 4 ]] || die "download <APP_NAME> <BASE_PACKAGE> <PLATFORMS_CSV> <dest-dir>"; cmd_download "$@" ;;
    url)      [[ $# -le 1 ]] || die "url <PLATFORMS_CSV>"; cmd_url "$@" ;;
    *)        die "unknown sub-command: $cmd" ;;
esac
