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
#       Same as render but src/<sourceSet>/kotlin/X.kt → dest/src/<sourceSet>/kotlin/<base-package-path>/<module-path>/X.kt
#       for every source set (commonMain, commonTest, androidMain, nativeMain, ...). <module-name> is a
#       package suffix: dots become directories (`feature.gallery` → feature/gallery/), and an empty
#       string ("") puts files directly in <base-package-path>/ (used for :shared's composition root).
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
#   apply-overlay.sh pin-toolchain <project-dir> [--ios] [--web]
#       Raise the toolchain to kmp-forge's floor — never downgrades: the catalog's `agp`
#       version to >= MIN_AGP, the Gradle wrapper to >= MIN_GRADLE (distributionUrl +
#       distributionSha256Sum fetched from services.gradle.org). --ios / --web also raise the
#       build heaps in gradle.properties: org.gradle.jvmargs -Xmx >= MIN_GRADLE_HEAP_MB
#       (Kotlin/Native links the iOS frameworks inside the Gradle daemon) and, for --web,
#       kotlin.daemon.jvmargs -Xmx >= MIN_KOTLIN_DAEMON_HEAP_MB (js/wasmJs executables with
#       Compose are compiled in the Kotlin daemon). kmp.new's defaults run out on a clean build.
#
# Required env vars when rendering .tmpl files:
#   APP_NAME, APP_NAME_LOWER, BASE_PACKAGE, BASE_PACKAGE_PATH, APP_TAGLINE (optional),
#   PLATFORM_LIST, BUILD_COMMANDS, MODULE_LIST, FEATURE_LIST, OPTIONAL_LIBS, FIGMA_URL,
#   PROJECT_OVERRIDES, TIMELINE, SCAFFOLD_DATE, SPEC_WORKFLOW. For feature templates: FEATURE_NAME (kebab),
#   FEATURE_NAME_PKG, FEATURE_NAME_CAMEL, FEATURE_NAME_PASCAL. For autoloop: AUTOLOOP_HANDOFF, READY_APPROVERS.
#   Unset variables substitute as empty strings (envsubst default).

set -euo pipefail

die() { echo "apply-overlay: $*" >&2; exit 1; }

# Only these variables are substituted. A bare `envsubst` replaces EVERY $VAR / ${VAR} in
# the file — including shell variables that templates must keep verbatim, e.g.
# release.yml's `$ANDROID_KEYSTORE_BASE64` / `$RUNNER_TEMP`, which would render as "".
# Adding an overlay variable? Add it here AND to the export block in commands/kmp-forge-init.md.
OVERLAY_VARS='${APP_NAME} ${APP_NAME_LOWER} ${APP_TAGLINE} ${BASE_PACKAGE} ${BASE_PACKAGE_PATH}
${PLATFORM_LIST} ${BUILD_COMMANDS} ${MODULE_LIST} ${FEATURE_LIST} ${OPTIONAL_LIBS} ${FIGMA_URL}
${PROJECT_OVERRIDES} ${TIMELINE} ${SCAFFOLD_DATE} ${SPEC_WORKFLOW}
${FEATURE_NAME} ${FEATURE_NAME_PKG} ${FEATURE_NAME_CAMEL} ${FEATURE_NAME_PASCAL}
${AUTOLOOP_HANDOFF} ${READY_APPROVERS}'

# Toolchain floor applied by pin-toolchain (kmp.new may ship older pins). /kmp-forge-bump-stack
# moves projects beyond it; bump these when the floor itself should rise.
MIN_AGP="9.4.1"
MIN_GRADLE="9.8.1"
MIN_GRADLE_HEAP_MB=6144
MIN_KOTLIN_DAEMON_HEAP_MB=6144

require_envsubst() {
    if ! command -v envsubst >/dev/null; then
        die "envsubst not found. Install via 'brew install gettext && brew link --force gettext'."
    fi
}

render_file() {
    local src="$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    if [[ "$src" == *.tmpl ]]; then
        envsubst "$OVERLAY_VARS" < "$src" > "$dest"
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
    # Module templates are all `package ${BASE_PACKAGE}…`: an unset variable (exports lost
    # between shell sessions) would silently render `package .ui` into `src/.../kotlin//ui/`.
    [[ -n "${BASE_PACKAGE:-}" ]] || die "BASE_PACKAGE is empty — export the overlay variables first"
    [[ -n "$base_pkg_path" ]] || die "base-package-path is empty"
    [[ -d "$src_dir" ]] || die "source dir not found: $src_dir"
    mkdir -p "$dest_dir"

    # Package suffix → path: `feature.gallery` → `feature/gallery/`; "" → no extra segment.
    local pkg_dir="$base_pkg_path"
    [[ -n "$module_name" ]] && pkg_dir="$base_pkg_path/${module_name//.//}"

    find "$src_dir" -type f | while read -r src_file; do
        local rel="${src_file#$src_dir/}"
        local dest_rel
        # Insert the package path after src/<sourceSet>/kotlin/ (any source set)
        if [[ "$rel" =~ ^src/([A-Za-z0-9]+)/kotlin/(.+)$ ]]; then
            local sourceset="${BASH_REMATCH[1]}"
            local tail="${BASH_REMATCH[2]}"
            dest_rel="src/$sourceset/kotlin/$pkg_dir/$tail"
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
    envsubst "$OVERLAY_VARS" < "$additions" > "$tmp_additions"

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

cmd_pin_toolchain() {
    local project_dir="$1"; shift
    local ios="" web=""
    while [[ $# -gt 0 ]]; do
        case "$1" in --ios) ios=1 ;; --web) web=1 ;; *) die "pin-toolchain: unknown flag $1" ;; esac
        shift
    done
    local libs_file="$project_dir/gradle/libs.versions.toml"
    local wrapper="$project_dir/gradle/wrapper/gradle-wrapper.properties"
    [[ -f "$libs_file" ]] || die "libs.versions.toml not found at: $libs_file"
    [[ -f "$wrapper" ]] || die "gradle-wrapper.properties not found at: $wrapper"

    local current_gradle sha=""
    current_gradle="$(sed -nE 's#^distributionUrl=.*gradle-([0-9][0-9.]*)-(bin|all)\.zip.*#\1#p' "$wrapper")"
    if [[ -n "$current_gradle" && "$(printf '%s\n%s\n' "$current_gradle" "$MIN_GRADLE" | sort -V | tail -1)" != "$current_gradle" ]]; then
        sha="$(curl -sfL "https://services.gradle.org/distributions/gradle-${MIN_GRADLE}-bin.zip.sha256" || true)"
        [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || die "could not fetch the sha256 for Gradle $MIN_GRADLE (offline?)"
    fi

    python3 - "$libs_file" "$wrapper" "$project_dir/gradle.properties" "$MIN_AGP" "$MIN_GRADLE" "$sha" \
        "$ios" "$web" "$MIN_GRADLE_HEAP_MB" "$MIN_KOTLIN_DAEMON_HEAP_MB" <<'PY'
import re, sys, pathlib

libs, wrapper, props = (pathlib.Path(a) for a in sys.argv[1:4])
min_agp, min_gradle, sha, ios, web, gradle_heap, kotlin_heap = sys.argv[4:11]

def vkey(v):
    return [int(x) if x.isdigit() else x for x in re.split(r"[.\-]", v)]

# 1. catalog: [versions] agp
text = libs.read_text()
m = re.search(r'(?m)^(agp\s*=\s*")([^"]+)(")', text)
if m and vkey(m.group(2)) < vkey(min_agp):
    text = text[:m.start(2)] + min_agp + text[m.end(2):]
    libs.write_text(text)
    print(f"agp: {m.group(2)} -> {min_agp}")
elif m:
    print(f"agp: {m.group(2)} (>= {min_agp}, kept)")
else:
    print("agp: no `agp` key in [versions] — left to patch-libs' fallback")

# 2. Gradle wrapper (sha is only passed when an upgrade is due)
if sha:
    w = wrapper.read_text()
    w, n = re.subn(r"(?m)^distributionUrl=.*$",
                   "distributionUrl=https\\://services.gradle.org/distributions/gradle-%s-bin.zip" % min_gradle, w)
    if re.search(r"(?m)^distributionSha256Sum=", w):
        w = re.sub(r"(?m)^distributionSha256Sum=.*$", "distributionSha256Sum=" + sha, w)
    else:
        w = w.rstrip("\n") + "\ndistributionSha256Sum=" + sha + "\n"
    wrapper.write_text(w)
    print(f"gradle wrapper -> {min_gradle}")
else:
    print(f"gradle wrapper: already >= {min_gradle}")

# 3. build heaps (only for the targets that need them)
def raise_heap(text, key, min_mb):
    m = re.search(r"(?m)^%s=(.*)$" % re.escape(key), text)
    if not m:
        print(f"{key}: added -Xmx{min_mb}M")
        return text.rstrip("\n") + f"\n{key}=-Xmx{min_mb}M -Dfile.encoding=UTF-8\n"
    args = m.group(1)
    x = re.search(r"-Xmx(\d+)([mMgG])", args)
    mb = (int(x.group(1)) * (1024 if x.group(2) in "gG" else 1)) if x else 0
    if mb >= int(min_mb):
        print(f"{key}: heap already sufficient")
        return text
    args = (args[:x.start()] + f"-Xmx{min_mb}M" + args[x.end():]) if x else f"-Xmx{min_mb}M {args}".strip()
    print(f"{key}: -Xmx raised to {min_mb}M")
    return text[:m.start(1)] + args + text[m.end(1):]

if ios or web:
    p = props.read_text() if props.exists() else ""
    p = raise_heap(p, "org.gradle.jvmargs", gradle_heap)
    if web:
        p = raise_heap(p, "kotlin.daemon.jvmargs", kotlin_heap)
    props.write_text(p)
PY
}

main() {
    [[ $# -ge 1 ]] || die "usage: $0 <render|render-module|patch-settings|patch-libs|pin-toolchain> ..."
    local cmd="$1"; shift
    case "$cmd" in
        render)           [[ $# -eq 2 ]] || die "render <src> <dest>"; cmd_render "$@" ;;
        render-module)    [[ $# -eq 4 ]] || die "render-module <module> <src> <dest> <base-pkg-path>"; cmd_render_module "$@" ;;
        patch-settings)   [[ $# -eq 2 ]] || die "patch-settings <project> <module-csv>"; cmd_patch_settings "$@" ;;
        patch-libs)       [[ $# -eq 2 ]] || die "patch-libs <project> <additions-toml>"; cmd_patch_libs "$@" ;;
        pin-toolchain)    [[ $# -ge 1 && $# -le 3 ]] || die "pin-toolchain <project> [--ios] [--web]"; cmd_pin_toolchain "$@" ;;
        *)                die "unknown sub-command: $cmd" ;;
    esac
}

main "$@"
