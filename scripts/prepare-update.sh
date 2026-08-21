#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_PATH="$PROJECT_DIR/dist/Photo_Editor.app"
RELEASES_DIR="$PROJECT_DIR/Releases"
UPDATES_DIR="$PROJECT_DIR/updates"
SPARKLE_TOOLS="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin"
KEY_ACCOUNT="photo_editor"
DOWNLOAD_PREFIX="https://github.com/Coloded/photo_editor/releases/latest/download/"

die() {
    print -u2 -- "✗ Ошибка: $1"
    [[ -z "${2:-}" ]] || print -u2 -- "  Что делать: $2"
    exit 1
}

[[ -d "$APP_PATH" ]] || die \
    "Не найдено собранное приложение dist/Photo_Editor.app." \
    "Сначала выполните ./scripts/build-app.sh --no-install"
[[ -x "$SPARKLE_TOOLS/generate_appcast" ]] || die \
    "Не найден инструмент Sparkle generate_appcast." \
    "Выполните swift package resolve и повторите сборку."
[[ -x "$SPARKLE_TOOLS/sign_update" ]] || die \
    "Не найден инструмент Sparkle sign_update." \
    "Выполните swift package resolve и повторите сборку."
[[ -f "$UPDATES_DIR/release-notes.md" ]] || die \
    "Не найден файл updates/release-notes.md." \
    "Добавьте описание новой версии на русском и английском языках."

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
VERSIONED_DMG="$RELEASES_DIR/Photo_Editor-$APP_VERSION-macOS-arm64.dmg"
STABLE_DMG="$RELEASES_DIR/Photo_Editor-stable.dmg"
APPCAST_PATH="$UPDATES_DIR/appcast.xml"

[[ -f "$VERSIONED_DMG" ]] || die \
    "Не найден DMG версии $APP_VERSION." \
    "Сначала выполните ./scripts/build-app.sh --no-install"

if ! "$SPARKLE_TOOLS/generate_keys" --account "$KEY_ACCOUNT" -p >/dev/null 2>&1; then
    die \
        "В Keychain не найден приватный ключ обновлений Photo_Editor." \
        "Создайте его командой: $SPARKLE_TOOLS/generate_keys --account $KEY_ACCOUNT"
fi

TEMP_DIR="$(mktemp -d "$PROJECT_DIR/.build/update-feed.XXXXXX")"
cleanup() {
    [[ -d "$TEMP_DIR" ]] && rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

cp "$VERSIONED_DMG" "$TEMP_DIR/Photo_Editor-stable.dmg"
cp "$UPDATES_DIR/release-notes.md" "$TEMP_DIR/Photo_Editor-stable.md"

print -- "▶ Создание подписанной ленты обновлений для Photo_Editor $APP_VERSION"
"$SPARKLE_TOOLS/generate_appcast" \
    --account "$KEY_ACCOUNT" \
    --embed-release-notes \
    --maximum-versions 1 \
    --maximum-deltas 0 \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    --link "https://github.com/Coloded/photo_editor" \
    -o "$TEMP_DIR/appcast.xml" \
    "$TEMP_DIR"

"$SPARKLE_TOOLS/sign_update" \
    --account "$KEY_ACCOUNT" \
    --verify \
    "$TEMP_DIR/appcast.xml"

cp "$TEMP_DIR/Photo_Editor-stable.dmg" "$STABLE_DMG"
cp "$TEMP_DIR/appcast.xml" "$APPCAST_PATH"
hdiutil verify "$STABLE_DMG" >/dev/null

print -- "✓ Stable DMG: $STABLE_DMG"
print -- "✓ Подписанный appcast: $APPCAST_PATH"
print -- "✓ Версия обновления: $APP_VERSION"
