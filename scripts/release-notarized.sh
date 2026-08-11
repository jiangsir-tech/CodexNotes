#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$PROJECT_ROOT/AppBundle/Info.plist"
UNIVERSAL_APP_VERIFIER="$PROJECT_ROOT/scripts/verify-universal-app.sh"
DIST_DIRECTORY="$PROJECT_ROOT/dist"
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw -o - "$INFO_PLIST")"
SOURCE_ARCHIVE="$DIST_DIRECTORY/CodexNotes.zip"
FINAL_ARCHIVE="$DIST_DIRECTORY/CodexNotes-v${VERSION}-macOS-universal.zip"
CHECKSUM_PATH="$FINAL_ARCHIVE.sha256"
SIGNING_IDENTITY="${CODEX_NOTES_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${CODEX_NOTES_NOTARY_PROFILE:-}"

verify_developer_id_runtime() {
    local app_path="$1"
    local architecture
    local signature_details

    codesign --verify --deep --strict --all-architectures --verbose=2 "$app_path"
    for architecture in arm64 x86_64; do
        if ! signature_details="$(codesign -d --architecture "$architecture" --verbose=4 "$app_path" 2>&1)"; then
            echo "无法读取 ${architecture} slice 的签名信息。" >&2
            return 1
        fi
        if ! grep -F "Authority=Developer ID Application:" <<<"$signature_details" >/dev/null; then
            echo "${architecture} slice 不是 Developer ID Application 签名。" >&2
            return 1
        fi
        if ! grep -F "Runtime Version" <<<"$signature_details" >/dev/null; then
            echo "${architecture} slice 未启用 Hardened Runtime。" >&2
            return 1
        fi
    done
}

if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "缺少 CODEX_NOTES_SIGNING_IDENTITY。" >&2
    exit 1
fi
if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "缺少 CODEX_NOTES_NOTARY_PROFILE。" >&2
    exit 1
fi
if [[ ! -f "$UNIVERSAL_APP_VERIFIER" ]]; then
    echo "缺少 Universal 2 验证脚本：$UNIVERSAL_APP_VERIFIER" >&2
    exit 1
fi
if ! git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "正式发布必须从 Git 仓库中的已提交源码构建。" >&2
    exit 1
fi
if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain --untracked-files=all)" ]]; then
    echo "正式发布要求干净的 Git 工作区。" >&2
    exit 1
fi
if [[ -e "$FINAL_ARCHIVE" || -e "$CHECKSUM_PATH" ]]; then
    echo "拒绝覆盖已有正式发布产物：$FINAL_ARCHIVE" >&2
    exit 1
fi
AVAILABLE_IDENTITIES="$(security find-identity -v -p codesigning)"
if ! grep -F "\"$SIGNING_IDENTITY\"" <<<"$AVAILABLE_IDENTITIES" >/dev/null; then
    echo "找不到有效签名身份：$SIGNING_IDENTITY" >&2
    exit 1
fi

# Authenticate the stored profile without exposing its credentials.
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null

CODEX_NOTES_INSTALL_LOCAL=0 zsh "$PROJECT_ROOT/scripts/package-app.sh"

STAGING_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/codexnotes-release.XXXXXX")"
trap 'rm -rf "$STAGING_DIRECTORY"' EXIT
ditto -x -k "$SOURCE_ARCHIVE" "$STAGING_DIRECTORY/input"

APP_PATH="$STAGING_DIRECTORY/input/CodexNotes.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "发布包中缺少 CodexNotes.app。" >&2
    exit 1
fi

xattr -cr "$APP_PATH" 2>/dev/null || true
codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$APP_PATH"
zsh "$UNIVERSAL_APP_VERIFIER" "$APP_PATH"
verify_developer_id_runtime "$APP_PATH"

NOTARY_ARCHIVE="$STAGING_DIRECTORY/CodexNotes-notary.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$NOTARY_ARCHIVE"
NOTARY_RESULT="$(xcrun notarytool submit \
    "$NOTARY_ARCHIVE" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --output-format json)"
NOTARY_STATUS="$(jq -r '.status // empty' <<<"$NOTARY_RESULT")"
if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
    echo "$NOTARY_RESULT" >&2
    echo "Apple notarization 未通过。" >&2
    exit 1
fi

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type exec --verbose=4 "$APP_PATH"
if command -v syspolicy_check >/dev/null 2>&1; then
    syspolicy_check distribution "$APP_PATH" --verbose
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$FINAL_ARCHIVE"

VERIFY_DIRECTORY="$STAGING_DIRECTORY/verify"
ditto -x -k "$FINAL_ARCHIVE" "$VERIFY_DIRECTORY"
VERIFIED_APP="$VERIFY_DIRECTORY/CodexNotes.app"
zsh "$UNIVERSAL_APP_VERIFIER" "$VERIFIED_APP"
verify_developer_id_runtime "$VERIFIED_APP"
xcrun stapler validate "$VERIFIED_APP"
spctl --assess --type exec --verbose=4 "$VERIFIED_APP"
if command -v syspolicy_check >/dev/null 2>&1; then
    syspolicy_check distribution "$VERIFIED_APP" --verbose
fi

(
    cd "$DIST_DIRECTORY"
    shasum -a 256 "${FINAL_ARCHIVE:t}" > "${CHECKSUM_PATH:t}"
)

echo "Notarized release: $FINAL_ARCHIVE"
echo "Version: $VERSION ($BUILD)"
echo "SHA-256: $(awk '{print $1}' "$CHECKSUM_PATH")"
