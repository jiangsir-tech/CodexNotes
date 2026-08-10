#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCALIZATION_SOURCE="$PROJECT_ROOT/Sources/CodexNotesCore/Localization.swift"
RESOURCE_ROOT="$PROJECT_ROOT/Sources/CodexNotesCore/Resources"
LANGUAGES=("zh-Hans" "en")
TEMP_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/codexnotes-localizations.XXXXXX")"
trap 'rm -rf "$TEMP_DIRECTORY"' EXIT

for LANGUAGE in "${LANGUAGES[@]}"; do
    STRINGS_FILE="$RESOURCE_ROOT/$LANGUAGE.lproj/Localizable.strings"
    if [[ ! -f "$STRINGS_FILE" ]]; then
        echo "缺少本地化资源：$STRINGS_FILE" >&2
        exit 1
    fi
    plutil -lint "$STRINGS_FILE" >/dev/null
    if [[ -n "$(sed -n 's/^\("[^"]*"\)[[:space:]]*=.*/\1/p' "$STRINGS_FILE" | sort | uniq -d)" ]]; then
        echo "本地化资源存在重复键：$STRINGS_FILE" >&2
        exit 1
    fi
    plutil -convert json -o "$TEMP_DIRECTORY/$LANGUAGE.json" "$STRINGS_FILE"
    jq -r 'keys[]' "$TEMP_DIRECTORY/$LANGUAGE.json" | sort > "$TEMP_DIRECTORY/$LANGUAGE.keys"
    jq -r '
        to_entries[]
        | .key as $key
        | ([.value | scan("\\{[A-Za-z][A-Za-z0-9_]*\\}")] | sort | unique | join(",")) as $tokens
        | [$key, $tokens]
        | @tsv
    ' "$TEMP_DIRECTORY/$LANGUAGE.json" | sort > "$TEMP_DIRECTORY/$LANGUAGE.tokens"
done

sed -n '/public enum Key:/,/^    }/p' "$LOCALIZATION_SOURCE" \
    | sed -n 's/.*case [A-Za-z0-9_]* = "\([^"]*\)".*/\1/p' \
    | sort > "$TEMP_DIRECTORY/declared.keys"

diff -u "$TEMP_DIRECTORY/declared.keys" "$TEMP_DIRECTORY/zh-Hans.keys"
diff -u "$TEMP_DIRECTORY/zh-Hans.keys" "$TEMP_DIRECTORY/en.keys"
diff -u "$TEMP_DIRECTORY/zh-Hans.tokens" "$TEMP_DIRECTORY/en.tokens"

if rg -n '[一-龥]' \
    "$PROJECT_ROOT/Sources/CodexNotesCore" \
    "$PROJECT_ROOT/Sources/CodexNotesProbe" \
    "$PROJECT_ROOT/Sources/CodexNotesProbeCheck" \
    -g '*.swift'; then
    echo "生产 Swift 源码仍含中文文案，请迁移到 Localizable.strings。" >&2
    exit 1
fi

if [[ $# -gt 0 ]]; then
    APP_PATH="$1"
    if [[ ! -d "$APP_PATH" ]]; then
        echo "应用不存在：$APP_PATH" >&2
        exit 1
    fi
    for LANGUAGE in "${LANGUAGES[@]}"; do
        SOURCE_STRINGS="$RESOURCE_ROOT/$LANGUAGE.lproj/Localizable.strings"
        APP_STRINGS="$(find \
            "$APP_PATH/Contents/Resources" \
            -path "*/CodexNotesProbe_CodexNotesCore.bundle/*/$LANGUAGE.lproj/Localizable.strings" \
            -type f \
            -print \
            -quit)"
        if [[ -z "$APP_STRINGS" ]]; then
            echo "应用缺少 $LANGUAGE 本地化资源：$APP_PATH" >&2
            exit 1
        fi
        cmp -s "$SOURCE_STRINGS" "$APP_STRINGS" || {
            echo "应用中的 $LANGUAGE 文案与源码不一致" >&2
            exit 1
        }
    done
fi

echo "本地化验证通过：${#LANGUAGES[@]} 种语言，$(wc -l < "$TEMP_DIRECTORY/declared.keys" | tr -d ' ') 个键"
