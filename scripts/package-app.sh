#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIRECTORY="$PROJECT_ROOT/dist"
APP_NAME="CodexNotes.app"
ARCHIVE_PATH="$OUTPUT_DIRECTORY/CodexNotes.zip"
APP_INFO_PLIST="$PROJECT_ROOT/AppBundle/Info.plist"
APP_ICON="$PROJECT_ROOT/AppBundle/Resources/CodexNotes.icns"
APP_ICON_BUILD_SCRIPT="$PROJECT_ROOT/scripts/build-app-icon.sh"
LOCALIZATION_VERIFY_SCRIPT="$PROJECT_ROOT/scripts/verify-localizations.sh"
UNIVERSAL_APP_VERIFY_SCRIPT="$PROJECT_ROOT/scripts/verify-universal-app.sh"
INSTALL_DIRECTORY="${CODEX_NOTES_INSTALL_DIRECTORY:-$HOME/Applications}"
INSTALL_LOCAL="${CODEX_NOTES_INSTALL_LOCAL:-0}"
ALLOW_WEAK_LOCAL_IDENTITY="${CODEX_NOTES_ALLOW_WEAK_LOCAL_IDENTITY:-0}"
INSTALLED_APP="$INSTALL_DIRECTORY/$APP_NAME"
LEGACY_APP="$INSTALL_DIRECTORY/Codex 跟随笔记.app"
LEGACY_ARCHIVE="$OUTPUT_DIRECTORY/Codex 跟随笔记.zip"
BUNDLE_IDENTIFIER="$(plutil -extract CFBundleIdentifier raw -o - "$APP_INFO_PLIST")"
# The locally installed development build needs a stable identity across the
# frequent overwrite cycle used on this Mac. Keep this weak, identifier-only
# ad-hoc requirement out of the ZIP: shared releases must use Developer ID.
LOCAL_INSTALL_REQUIREMENT="=designated => identifier \"$BUNDLE_IDENTIFIER\""

if [[ "$INSTALL_LOCAL" != "0" && "$INSTALL_LOCAL" != "1" ]]; then
    echo "CODEX_NOTES_INSTALL_LOCAL 必须是 0 或 1。" >&2
    exit 1
fi
if [[ "$ALLOW_WEAK_LOCAL_IDENTITY" != "0" && "$ALLOW_WEAK_LOCAL_IDENTITY" != "1" ]]; then
    echo "CODEX_NOTES_ALLOW_WEAK_LOCAL_IDENTITY 必须是 0 或 1。" >&2
    exit 1
fi
if [[ "$ALLOW_WEAK_LOCAL_IDENTITY" == "1" && "$INSTALL_LOCAL" != "1" ]]; then
    echo "弱本地身份只能与 CODEX_NOTES_INSTALL_LOCAL=1 一起使用。" >&2
    exit 1
fi

STAGING_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/codex-notes-probe.XXXXXX")"
ARM64_BUILD_DIRECTORY="$(mktemp -d /tmp/codex-notes-arm64.XXXXXX)"
X86_64_BUILD_DIRECTORY="$(mktemp -d /tmp/codex-notes-x86_64.XXXXXX)"

cleanup() {
    rm -rf \
        "$STAGING_DIRECTORY" \
        "$ARM64_BUILD_DIRECTORY" \
        "$X86_64_BUILD_DIRECTORY"
}
trap cleanup EXIT

verify_thin_binary() {
    local binary_path="$1"
    local expected_architecture="$2"
    local actual_architectures

    if [[ ! -f "$binary_path" ]]; then
        echo "缺少 $expected_architecture 构建产物：$binary_path" >&2
        exit 1
    fi
    actual_architectures="$(/usr/bin/lipo -archs "$binary_path")"
    if [[ "$actual_architectures" != "$expected_architecture" ]]; then
        echo \
            "意外的 $expected_architecture 输入架构：$actual_architectures" \
            >&2
        exit 1
    fi
}

zsh "$APP_ICON_BUILD_SCRIPT" >/dev/null
zsh "$LOCALIZATION_VERIFY_SCRIPT"

/usr/bin/xcrun swift build \
    --package-path "$PROJECT_ROOT" \
    --scratch-path "$ARM64_BUILD_DIRECTORY" \
    -c release \
    --arch arm64 \
    --product CodexNotesProbe
ARM64_BIN_DIRECTORY="$(/usr/bin/xcrun swift build \
    --package-path "$PROJECT_ROOT" \
    --scratch-path "$ARM64_BUILD_DIRECTORY" \
    -c release \
    --arch arm64 \
    --product CodexNotesProbe \
    --show-bin-path)"

/usr/bin/xcrun swift build \
    --package-path "$PROJECT_ROOT" \
    --scratch-path "$X86_64_BUILD_DIRECTORY" \
    -c release \
    --arch x86_64 \
    --product CodexNotesProbe
X86_64_BIN_DIRECTORY="$(/usr/bin/xcrun swift build \
    --package-path "$PROJECT_ROOT" \
    --scratch-path "$X86_64_BUILD_DIRECTORY" \
    -c release \
    --arch x86_64 \
    --product CodexNotesProbe \
    --show-bin-path)"

ARM64_BINARY="$ARM64_BIN_DIRECTORY/CodexNotesProbe"
X86_64_BINARY="$X86_64_BIN_DIRECTORY/CodexNotesProbe"
verify_thin_binary "$ARM64_BINARY" arm64
verify_thin_binary "$X86_64_BINARY" x86_64

STAGED_APP="$STAGING_DIRECTORY/$APP_NAME"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
/usr/bin/lipo -create \
    "$ARM64_BINARY" \
    "$X86_64_BINARY" \
    -output "$STAGED_APP/Contents/MacOS/CodexNotesProbe"
cp "$APP_INFO_PLIST" "$STAGED_APP/Contents/Info.plist"
if [[ ! -f "$APP_ICON" ]]; then
    echo "缺少应用图标：$APP_ICON" >&2
    exit 1
fi
cp "$APP_ICON" "$STAGED_APP/Contents/Resources/CodexNotes.icns"
RESOURCE_BUNDLE_NAMES=(
    "CodexNotesProbe_CodexNotesProbe.bundle"
    "CodexNotesProbe_CodexNotesCore.bundle"
)
for RESOURCE_BUNDLE_NAME in "${RESOURCE_BUNDLE_NAMES[@]}"; do
    ARM64_RESOURCE_BUNDLE="$ARM64_BIN_DIRECTORY/$RESOURCE_BUNDLE_NAME"
    X86_64_RESOURCE_BUNDLE="$X86_64_BIN_DIRECTORY/$RESOURCE_BUNDLE_NAME"
    if [[ ! -d "$ARM64_RESOURCE_BUNDLE" ]]; then
        echo "缺少 arm64 应用资源包：$ARM64_RESOURCE_BUNDLE" >&2
        exit 1
    fi
    if [[ ! -d "$X86_64_RESOURCE_BUNDLE" ]]; then
        echo "缺少 x86_64 应用资源包：$X86_64_RESOURCE_BUNDLE" >&2
        exit 1
    fi
    if ! /usr/bin/diff -qr \
        "$ARM64_RESOURCE_BUNDLE" \
        "$X86_64_RESOURCE_BUNDLE"
    then
        echo "两种架构生成的资源包不一致：$RESOURCE_BUNDLE_NAME" >&2
        exit 1
    fi
    ditto \
        "$ARM64_RESOURCE_BUNDLE" \
        "$STAGED_APP/Contents/Resources/$RESOURCE_BUNDLE_NAME"
done
chmod 755 "$STAGED_APP/Contents/MacOS/CodexNotesProbe"

zsh "$LOCALIZATION_VERIFY_SCRIPT" "$STAGED_APP"

xattr -cr "$STAGED_APP" 2>/dev/null || true
codesign --force --deep --sign - "$STAGED_APP"
zsh "$UNIVERSAL_APP_VERIFY_SCRIPT" "$STAGED_APP"

mkdir -p "$OUTPUT_DIRECTORY"
if [[ -e "$ARCHIVE_PATH" ]]; then
    rm -f "$ARCHIVE_PATH"
fi
ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$ARCHIVE_PATH"

if [[ "$INSTALL_LOCAL" == "1" ]]; then
    mkdir -p "$INSTALL_DIRECTORY"
    if [[ -e "$INSTALLED_APP" ]]; then
        rm -rf "$INSTALLED_APP"
    fi
    ditto "$STAGED_APP" "$INSTALLED_APP"
    xattr -cr "$INSTALLED_APP" 2>/dev/null || true

    if [[ "$ALLOW_WEAK_LOCAL_IDENTITY" == "1" ]]; then
        echo "警告：正在使用仅限本机开发的 identifier-only ad-hoc 身份。" >&2
        codesign \
            --force \
            --deep \
            --sign - \
            --requirements "$LOCAL_INSTALL_REQUIREMENT" \
            "$INSTALLED_APP"
    fi
    zsh "$UNIVERSAL_APP_VERIFY_SCRIPT" "$INSTALLED_APP"

    if [[ "$LEGACY_APP" != "$INSTALLED_APP" && -e "$LEGACY_APP" ]]; then
        rm -rf "$LEGACY_APP"
    fi
    echo "$INSTALLED_APP"
fi
if [[ "$LEGACY_ARCHIVE" != "$ARCHIVE_PATH" && -e "$LEGACY_ARCHIVE" ]]; then
    rm -f "$LEGACY_ARCHIVE"
fi

echo "$ARCHIVE_PATH"
