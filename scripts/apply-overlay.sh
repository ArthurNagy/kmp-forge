#!/usr/bin/env bash
#
# kmp-forge overlay renderer.
#
# Usage:
#   apply-overlay.sh render <src-dir> <dest-dir>
#       Walk <src-dir>, render every .tmpl file via envsubst (strips .tmpl suffix),
#       copy non-.tmpl files as-is. Preserves directory structure.
#
#   apply-overlay.sh render-module <module-name> <src-dir> <dest-dir> <base-package-path>
#       Same as render but src/commonMain/kotlin/X.kt → dest/src/commonMain/kotlin/<base-package-path>/<module-name>/X.kt
#       (Same for commonTest/.) For module-style overlays.
#
#   apply-overlay.sh patch-settings <project-dir> <module-list>
#       Append `include(":x")` lines to project's settings.gradle.kts for each module
#       in comma-separated <module-list>, idempotently (skip if already included).
#
#   apply-overlay.sh patch-libs <project-dir> <additions-toml-file>
#       Merge additional [versions], [libraries], [plugins] entries from <additions-toml-file>
#       into project's gradle/libs.versions.toml. Section-aware: appends under each header
#       (creates header if missing). Skips entries whose keys already exist.
#
# Required env vars when rendering .tmpl files:
#   APP_NAME, BASE_PACKAGE, BASE_PACKAGE_PATH, APP_TAGLINE (optional), PLATFORM_LIST,
#   BUILD_COMMANDS, MODULE_LIST, FEATURE_LIST, OPTIONAL_LIBS, FIGMA_URL, PROJECT_OVERRIDES,
#   TIMELINE, SCAFFOLD_DATE. For feature templates: FEATURE_NAME, FEATURE_NAME_PASCAL.
#   Unset variables substitute as empty strings (envsubst default).

set -euo pipefail

die() { echo "apply-overlay: $*" >&2; exit 1; }

require_envsubst() {
    if ! command -v envsubst >/dev/null; then
        die "envsubst not found. Install via 'brew install gettext && brew link --force gettext'."
    fi
}

render_file() {
    local src="$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    if [[ "$src" == *.tmpl ]]; then
        envsubst < "$src" > "$dest"
    else
        cp "$src" "$dest"
    fi
}

cmd_render() {
    local src_dir="$1" dest_dir="$2"
    require_envsubst
    [[ -d "$src_dir" ]] || die "source dir not found: $src_dir"
    mkdir -p "$dest_dir"

    find "$src_dir" -type f | while read -r src_file; do
        local rel="${src_file#$src_dir/}"
        local dest_rel="${rel%.tmpl}"
        local dest_file="$dest_dir/$dest_rel"
        render_file "$src_file" "$dest_file"
    done
}

cmd_render_module() {
    local module_name="$1" src_dir="$2" dest_dir="$3" base_pkg_path="$4"
    require_envsubst
    [[ -d "$src_dir" ]] || die "source dir not found: $src_dir"
    mkdir -p "$dest_dir"

    find "$src_dir" -type f | while read -r src_file; do
        local rel="${src_file#$src_dir/}"
        local dest_rel
        # Insert <base-package-path>/<module-name>/ after src/commonMain/kotlin/ and src/commonTest/kotlin/
        if [[ "$rel" =~ ^src/(commonMain|commonTest)/kotlin/(.+)$ ]]; then
            local sourceset="${BASH_REMATCH[1]}"
            local tail="${BASH_REMATCH[2]}"
            dest_rel="src/$sourceset/kotlin/$base_pkg_path/$module_name/$tail"
        else
            dest_rel="$rel"
        fi
        dest_rel="${dest_rel%.tmpl}"
        local dest_file="$dest_dir/$dest_rel"
        render_file "$src_file" "$dest_file"
    done
}

cmd_patch_settings() {
    local project_dir="$1" module_csv="$2"
    local settings="$project_dir/settings.gradle.kts"
    [[ -f "$settings" ]] || die "settings.gradle.kts not found at: $settings"

    # Ensure the file ends with a newline before appending — kmp.new's generated
    # settings.gradle.kts has no trailing newline, so a bare `>>` would concatenate
    # the first include() onto its last line (e.g. `include(":shared")include(":ui")`).
    [[ -s "$settings" && -n "$(tail -c1 "$settings")" ]] && printf '\n' >> "$settings"

    IFS=',' read -ra modules <<< "$module_csv"
    for m in "${modules[@]}"; do
        m="$(echo "$m" | xargs)"  # trim
        [[ -z "$m" ]] && continue
        local include_line="include(\":$m\")"
        if grep -qxF "$include_line" "$settings"; then
            echo "skip (already present): $include_line"
        else
            echo "$include_line" >> "$settings"
            echo "added: $include_line"
        fi
    done
}

cmd_patch_libs() {
    local project_dir="$1" additions="$2"
    local libs_file="$project_dir/gradle/libs.versions.toml"
    [[ -f "$libs_file" ]] || die "libs.versions.toml not found at: $libs_file"
    [[ -f "$additions" ]] || die "additions file not found: $additions"

    require_envsubst

    local tmp_additions
    tmp_additions="$(mktemp)"
    envsubst < "$additions" > "$tmp_additions"

    python3 - "$libs_file" "$tmp_additions" <<'PY'
import re, sys, pathlib

libs_path = pathlib.Path(sys.argv[1])
add_path = pathlib.Path(sys.argv[2])

def parse_sections(text):
    sections = {}
    current = None
    sections.setdefault(current, [])
    for line in text.splitlines(keepends=False):
        m = re.match(r"^\[(.+)\]\s*$", line)
        if m:
            current = m.group(1)
            sections.setdefault(current, [])
        else:
            sections.setdefault(current, []).append(line)
    return sections

def existing_keys(lines):
    keys = set()
    for line in lines:
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        m = re.match(r'^([A-Za-z0-9._-]+|"[^"]+")\s*=', s)
        if m:
            keys.add(m.group(1).strip('"'))
    return keys

base = parse_sections(libs_path.read_text())
add = parse_sections(add_path.read_text())

for section, add_lines in add.items():
    if section is None:
        continue
    base_lines = base.setdefault(section, [])
    have = existing_keys(base_lines)
    appended = []
    for line in add_lines:
        s = line.strip()
        if not s or s.startswith("#"):
            appended.append(line)
            continue
        m = re.match(r'^([A-Za-z0-9._-]+|"[^"]+")\s*=', s)
        if m and m.group(1).strip('"') in have:
            continue
        appended.append(line)
        if m:
            have.add(m.group(1).strip('"'))
    if appended:
        if base_lines and base_lines[-1].strip() != "":
            base_lines.append("")
        base_lines.append(f"# --- kmp-forge additions ({section}) ---")
        base_lines.extend(appended)

out = []
preamble = base.pop(None, [])
out.extend(preamble)
for section, lines in base.items():
    if out and out[-1].strip() != "":
        out.append("")
    out.append(f"[{section}]")
    out.extend(lines)
libs_path.write_text("\n".join(out).rstrip() + "\n")
print(f"patched: {libs_path}")
PY

    rm -f "$tmp_additions"
}

main() {
    [[ $# -ge 1 ]] || die "usage: $0 <render|render-module|patch-settings|patch-libs> ..."
    local cmd="$1"; shift
    case "$cmd" in
        render)           [[ $# -eq 2 ]] || die "render <src> <dest>"; cmd_render "$@" ;;
        render-module)    [[ $# -eq 4 ]] || die "render-module <module> <src> <dest> <base-pkg-path>"; cmd_render_module "$@" ;;
        patch-settings)   [[ $# -eq 2 ]] || die "patch-settings <project> <module-csv>"; cmd_patch_settings "$@" ;;
        patch-libs)       [[ $# -eq 2 ]] || die "patch-libs <project> <additions-toml>"; cmd_patch_libs "$@" ;;
        *)                die "unknown sub-command: $cmd" ;;
    esac
}

main "$@"
