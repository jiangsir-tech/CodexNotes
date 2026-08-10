#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_IMAGE="$PROJECT_ROOT/design/app-icon/selected/CodexNotes-AppIcon-1024.png"
ICONSET_DIRECTORY="$PROJECT_ROOT/design/app-icon/selected/CodexNotes.iconset"
OUTPUT_DIRECTORY="$PROJECT_ROOT/AppBundle/Resources"
OUTPUT_ICON="$OUTPUT_DIRECTORY/CodexNotes.icns"

if [[ ! -f "$SOURCE_IMAGE" ]]; then
    echo "缺少应用图标母版：$SOURCE_IMAGE" >&2
    exit 1
fi

mkdir -p "$ICONSET_DIRECTORY" "$OUTPUT_DIRECTORY"

render_icon() {
    local pixels="$1"
    local filename="$2"
    sips -z "$pixels" "$pixels" "$SOURCE_IMAGE" \
        --out "$ICONSET_DIRECTORY/$filename" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIRECTORY" -o "$OUTPUT_ICON"
echo "$OUTPUT_ICON"
