#!/bin/zsh
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "用法：zsh scripts/verify-universal-app.sh /path/to/CodexNotes.app" >&2
    exit 64
fi

APP_PATH="$1"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

if [[ ! -d "$APP_PATH" ]]; then
    echo "应用不存在：$APP_PATH" >&2
    exit 1
fi
if [[ ! -f "$INFO_PLIST" ]]; then
    echo "应用缺少 Info.plist：$INFO_PLIST" >&2
    exit 1
fi

EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
MINIMUM_SYSTEM_VERSION="$(
    plutil -extract LSMinimumSystemVersion raw -o - "$INFO_PLIST"
)"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"

if [[ ! -f "$EXECUTABLE_PATH" ]]; then
    echo "应用缺少主程序：$EXECUTABLE_PATH" >&2
    exit 1
fi

ARCHITECTURES="$(/usr/bin/lipo -archs "$EXECUTABLE_PATH")"
ARCHITECTURE_COUNT="$(
    /usr/bin/awk '{ print NF }' <<<"$ARCHITECTURES"
)"
if [[ "$ARCHITECTURE_COUNT" != "2" ]]; then
    echo "主程序必须恰好包含两个架构，实际为：$ARCHITECTURES" >&2
    exit 1
fi
if ! /usr/bin/lipo "$EXECUTABLE_PATH" -verify_arch arm64; then
    echo "主程序缺少 arm64 架构：$ARCHITECTURES" >&2
    exit 1
fi
if ! /usr/bin/lipo "$EXECUTABLE_PATH" -verify_arch x86_64; then
    echo "主程序缺少 x86_64 架构：$ARCHITECTURES" >&2
    exit 1
fi

normalize_version() {
    local raw_version="$1"

    /usr/bin/awk -v version="$raw_version" 'BEGIN {
        count = split(version, parts, ".")
        while (count > 1 && parts[count] == 0) {
            count--
        }
        normalized = parts[1]
        for (part_index = 2; part_index <= count; part_index++) {
            normalized = normalized "." parts[part_index]
        }
        print normalized
    }'
}

EXPECTED_MINIMUM_VERSION="$(normalize_version "$MINIMUM_SYSTEM_VERSION")"
for ARCHITECTURE in arm64 x86_64; do
    BUILD_DETAILS="$(
        /usr/bin/vtool \
            -arch "$ARCHITECTURE" \
            -show-build \
            "$EXECUTABLE_PATH"
    )"
    PLATFORM="$(
        /usr/bin/awk '$1 == "platform" { print $2; exit }' \
            <<<"$BUILD_DETAILS"
    )"
    SLICE_MINIMUM_VERSION="$(
        /usr/bin/awk '$1 == "minos" { print $2; exit }' \
            <<<"$BUILD_DETAILS"
    )"
    if [[ "$PLATFORM" != "MACOS" || -z "$SLICE_MINIMUM_VERSION" ]]; then
        echo "无法读取 $ARCHITECTURE 切片的 macOS 最低版本。" >&2
        exit 1
    fi

    NORMALIZED_SLICE_MINIMUM_VERSION="$(
        normalize_version "$SLICE_MINIMUM_VERSION"
    )"
    if [[ \
        "$NORMALIZED_SLICE_MINIMUM_VERSION" \
        != "$EXPECTED_MINIMUM_VERSION" \
    ]]; then
        echo \
            "$ARCHITECTURE 切片最低版本 $SLICE_MINIMUM_VERSION 与 Info.plist 的 $MINIMUM_SYSTEM_VERSION 不一致。" \
            >&2
        exit 1
    fi
done

codesign \
    --verify \
    --all-architectures \
    --deep \
    --strict \
    --verbose=2 \
    "$APP_PATH"

echo \
    "Universal App 验证通过：$ARCHITECTURES，macOS $MINIMUM_SYSTEM_VERSION+"
