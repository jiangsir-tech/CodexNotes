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
trap 'rm -rf "$STAGING_DIRECTORY"' EXIT
BUILD_DIRECTORY="$STAGING_DIRECTORY/build"

zsh "$APP_ICON_BUILD_SCRIPT" >/dev/null
zsh "$LOCALIZATION_VERIFY_SCRIPT"

swift build \
    --package-path "$PROJECT_ROOT" \
    --scratch-path "$BUILD_DIRECTORY" \
    -c release \
    --product CodexNotesProbe
BIN_DIRECTORY="$(swift build \
    --package-path "$PROJECT_ROOT" \
    --scratch-path "$BUILD_DIRECTORY" \
    -c release \
    --show-bin-path)"

STAGED_APP="$STAGING_DIRECTORY/$APP_NAME"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIRECTORY/CodexNotesProbe" "$STAGED_APP/Contents/MacOS/CodexNotesProbe"
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
    RESOURCE_BUNDLE="$BIN_DIRECTORY/$RESOURCE_BUNDLE_NAME"
    if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
        echo "缺少应用资源包：$RESOURCE_BUNDLE" >&2
        exit 1
    fi
    ditto "$RESOURCE_BUNDLE" "$STAGED_APP/Contents/Resources/$RESOURCE_BUNDLE_NAME"
done
chmod 755 "$STAGED_APP/Contents/MacOS/CodexNotesProbe"

zsh "$LOCALIZATION_VERIFY_SCRIPT" "$STAGED_APP"

xattr -cr "$STAGED_APP" 2>/dev/null || true
codesign --force --deep --sign - "$STAGED_APP"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

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
    codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"

    if [[ "$LEGACY_APP" != "$INSTALLED_APP" && -e "$LEGACY_APP" ]]; then
        rm -rf "$LEGACY_APP"
    fi
    echo "$INSTALLED_APP"
fi
if [[ "$LEGACY_ARCHIVE" != "$ARCHIVE_PATH" && -e "$LEGACY_ARCHIVE" ]]; then
    rm -f "$LEGACY_ARCHIVE"
fi

echo "$ARCHIVE_PATH"
