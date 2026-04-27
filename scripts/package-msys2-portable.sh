#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 <build-dir> <package-dir> [package-name]" >&2
    exit 2
fi

BUILD_DIR=$(cd "$1" && pwd)
PACKAGE_ROOT=$(mkdir -p "$2" && cd "$2" && pwd)
PACKAGE_NAME=${3:-nomacs-portable-win64}
PACKAGE_DIR="$PACKAGE_ROOT/$PACKAGE_NAME"
QT_PLUGIN_DIR=$(cygpath -u "$(qtpaths6 --qt-query QT_INSTALL_PLUGINS | sed 's/^QT_INSTALL_PLUGINS://')")
QT_TRANSLATIONS_DIR=$(cygpath -u "$(qtpaths6 --qt-query QT_INSTALL_TRANSLATIONS | sed 's/^QT_INSTALL_TRANSLATIONS://')")

copy_file() {
    local source=$1
    local destination=$2

    if [[ -f "$source" ]]; then
        mkdir -p "$(dirname "$destination")"
        cp -f "$source" "$destination"
    fi
}

copy_directory() {
    local source=$1
    local destination=$2

    if [[ -d "$source" ]]; then
        mkdir -p "$(dirname "$destination")"
        cp -a "$source" "$destination"
    fi
}

collect_runtime_dlls() {
    local binary=$1

    ldd "$binary" \
        | awk '
            /\/ucrt64\// {
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^\/ucrt64\/.*\.dll$/) {
                        print $i
                    }
                }
            }
        '
}

copy_runtime_closure() {
    local -a queue=("$@")
    local -a seen=()

    while ((${#queue[@]} > 0)); do
        local binary=${queue[0]}
        queue=("${queue[@]:1}")

        while IFS= read -r dll; do
            [[ -n "$dll" ]] || continue

            local dll_name
            dll_name=$(basename "$dll")

            if printf '%s\n' "${seen[@]}" | grep -Fxq "$dll_name"; then
                continue
            fi

            seen+=("$dll_name")
            copy_file "$dll" "$PACKAGE_DIR/$dll_name"
            queue+=("$dll")
        done < <(collect_runtime_dlls "$binary")
    done
}

rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

copy_file "$BUILD_DIR/nomacs.exe" "$PACKAGE_DIR/nomacs.exe"
copy_file "$BUILD_DIR/libnomacsCore.dll" "$PACKAGE_DIR/libnomacsCore.dll"
copy_directory "$BUILD_DIR/themes" "$PACKAGE_DIR/themes"

mkdir -p "$PACKAGE_DIR/translations"
find "$BUILD_DIR" -maxdepth 1 -name 'nomacs_*.qm' -exec cp -f {} "$PACKAGE_DIR/translations/" \;
if [[ -d "$QT_TRANSLATIONS_DIR" ]]; then
    find "$QT_TRANSLATIONS_DIR" -maxdepth 1 \( -name 'qtbase_*.qm' -o -name 'qtmultimedia_*.qm' \) -exec cp -f {} "$PACKAGE_DIR/translations/" \;
fi

for plugin_dir in iconengines imageformats platforms printsupport styles tls; do
    copy_directory "$QT_PLUGIN_DIR/$plugin_dir" "$PACKAGE_DIR/$plugin_dir"
done

mkdir -p "$PACKAGE_DIR/plugins"
find "$BUILD_DIR/nomacs-plugins" -mindepth 2 -maxdepth 2 -name '*.dll' -exec cp -f {} "$PACKAGE_DIR/plugins/" \;

mapfile -t binaries < <(find "$PACKAGE_DIR" -type f \( -name '*.exe' -o -name '*.dll' \))
copy_runtime_closure "${binaries[@]}"

cat > "$PACKAGE_DIR/README.txt" <<'EOF'
nomacs Explorer Browser fork

Start nomacs.exe from this folder.

Fork-specific behavior:
- The file manager sidebar shows folders only.
- Clicking a folder opens its image thumbnails.
- Double-clicking a thumbnail opens the image view.
- Double-clicking the image view returns to thumbnails.
- Middle-clicking the image view toggles fullscreen.
EOF

echo "$PACKAGE_DIR"
