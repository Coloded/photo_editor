#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_NAME="Photo_Editor"
EXECUTABLE_NAME="PhotoPrintEditor"
APP_VERSION="1.4.2"
BUILD_NUMBER="7"
APP_DIR="$PROJECT_DIR/dist/$APP_NAME.app"
MODULE_CACHE="$PROJECT_DIR/.build/ModuleCache"
ARCHIVE_DIR="$PROJECT_DIR/Releases"
ARCHIVE_PATH="$ARCHIVE_DIR/$APP_NAME-$APP_VERSION-macOS-arm64.zip"
DMG_PATH="$ARCHIVE_DIR/$APP_NAME-$APP_VERSION-macOS-arm64.dmg"
INSTALL_PATH="/Applications/$APP_NAME.app"
TARGET="arm64-apple-macosx13.0"

CREATE_ARCHIVE=false
INSTALL_APP=true
ASSUME_YES=false
SELECTED_SDK=""
CURRENT_STAGE="запуск скрипта"
TEMP_PATHS=()

cleanup_temp_paths() {
    local temp_path
    for temp_path in "${TEMP_PATHS[@]}"; do
        [[ -e "$temp_path" ]] || continue
        case "$temp_path" in
            "$PROJECT_DIR/.build/"*|"$ARCHIVE_DIR/."*) rm -rf -- "$temp_path" ;;
        esac
    done
}

TRAPEXIT() {
    if (( ZSH_SUBSHELL == 0 )); then
        cleanup_temp_paths
    fi
}

TRAPZERR() {
    local exit_code=$?
    print -u2 -- ""
    print -u2 -- "✗ Непредвиденная ошибка на этапе: $CURRENT_STAGE"
    print -u2 -- "  Код завершения: $exit_code"
    print -u2 -- "  Проверьте системное сообщение выше. Если оно непонятно, приложите весь вывод скрипта."
    return "$exit_code"
}

info() { print -- "▶ $1"; }
success() { print -- "✓ $1"; }
warn() { print -u2 -- "⚠ $1"; }

die() {
    print -u2 -- ""
    print -u2 -- "✗ Ошибка: $1"
    if [[ -n "${2:-}" ]]; then
        print -u2 -- "  Что делать: $2"
    fi
    exit 1
}

usage() {
    cat <<'EOF'
Сборка Photo_Editor для Apple Silicon

Использование:
  ./scripts/build-app.sh [параметры]

Параметры:
  --archive   дополнительно создать ZIP в папке Releases
  --install   установить приложение в /Applications (по умолчанию)
  --no-install  только собрать приложение и DMG, не устанавливать
  --yes, -y   не спрашивать подтверждение установки
  --help, -h  показать эту справку

Переменные окружения:
  PHOTO_EDITOR_SDK_PATH   использовать конкретный macOS SDK

Примеры:
  ./scripts/build-app.sh              # приложение, DMG и установка
  ./scripts/build-app.sh --no-install # приложение и DMG без установки
  ./scripts/build-app.sh --archive
  ./scripts/build-app.sh --archive --install
EOF
}

ask_yes_no() {
    local prompt="$1"
    local answer=""

    if [[ "$ASSUME_YES" == true ]]; then
        return 0
    fi
    if [[ ! -t 0 ]]; then
        return 1
    fi
    read -r "answer?$prompt [y/N]: "
    [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] || "$answer" == [дД] || "$answer" == [дД][аА] ]]
}

offer_command_line_tools_install() {
    warn "Не установлены Apple Command Line Tools. Без них недоступны Swift, SDK и codesign."
    print -u2 -- "  Требуется бесплатный комплект Apple Command Line Tools."

    if ask_yes_no "Открыть системный установщик Command Line Tools?"; then
        /usr/bin/xcode-select --install || true
        print -- "Установщик Apple открыт. После завершения установки снова запустите этот скрипт."
    else
        print -u2 -- "  Установите вручную командой: xcode-select --install"
        print -u2 -- "  После установки снова запустите этот скрипт."
    fi
    exit 1
}

require_command() {
    local command_name="$1"
    local install_hint="$2"
    command -v "$command_name" >/dev/null 2>&1 || die \
        "Не найдена команда «$command_name»." \
        "$install_hint"
}

sdk_is_compatible() {
    local sdk="$1"
    [[ -d "$sdk" ]] || return 1
    print 'import SwiftUI' | env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
        swiftc -sdk "$sdk" -target "$TARGET" -typecheck - >/dev/null 2>&1
}

select_compatible_sdk() {
    local -a candidates
    local sdk developer_dir default_sdk
    local -A seen

    mkdir -p "$MODULE_CACHE"

    if [[ -n "${PHOTO_EDITOR_SDK_PATH:-}" ]]; then
        [[ -d "$PHOTO_EDITOR_SDK_PATH" ]] || die \
            "SDK из PHOTO_EDITOR_SDK_PATH не найден: $PHOTO_EDITOR_SDK_PATH" \
            "Исправьте путь или удалите переменную PHOTO_EDITOR_SDK_PATH."
        candidates+=("$PHOTO_EDITOR_SDK_PATH")
    fi

    developer_dir="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
    candidates+=(
        "$developer_dir/SDKs/MacOSX15.4.sdk"
        "$developer_dir/Platforms/MacOSX.platform/Developer/SDKs/MacOSX15.4.sdk"
    )

    default_sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
    [[ -n "$default_sdk" ]] && candidates+=("$default_sdk")

    candidates+=(
        /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk(N)
        /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk(N)
    )

    for sdk in "${candidates[@]}"; do
        [[ -n "$sdk" && -z "${seen[$sdk]:-}" ]] || continue
        seen[$sdk]=1
        if sdk_is_compatible "$sdk"; then
            SELECTED_SDK="$sdk"
            return 0
        fi
    done

    print -u2 -- "Проверенная версия Swift: $(swift --version 2>/dev/null | head -n 1)"
    print -u2 -- "Ни один установленный macOS SDK не совместим с этой версией Swift."
    die \
        "Не найден совместимый macOS SDK." \
        "Обновите Command Line Tools через «Системные настройки → Основные → Обновление ПО» или установите актуальный Xcode."
}

for argument in "$@"; do
    case "$argument" in
        --archive) CREATE_ARCHIVE=true ;;
        --install) INSTALL_APP=true ;;
        --no-install) INSTALL_APP=false ;;
        --yes|-y) ASSUME_YES=true ;;
        --help|-h) usage; exit 0 ;;
        *) die "Неизвестный параметр: $argument" "Запустите ./scripts/build-app.sh --help" ;;
    esac
done

CURRENT_STAGE="проверка окружения"
info "Проверка окружения"
[[ "$(uname -s)" == "Darwin" ]] || die \
    "Сборка поддерживается только в macOS." \
    "Запустите скрипт на Mac с macOS 13 или новее."

if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    offer_command_line_tools_install
fi

require_command swift "Установите Apple Command Line Tools: xcode-select --install"
require_command swiftc "Установите Apple Command Line Tools: xcode-select --install"
require_command codesign "Переустановите или обновите Apple Command Line Tools."
require_command file "Команда file входит в macOS. Восстановите системные утилиты или обновите macOS."
require_command ditto "Команда ditto входит в macOS. Восстановите системные утилиты или обновите macOS."
require_command hdiutil "Команда hdiutil входит в macOS. Восстановите системные утилиты или обновите macOS."
require_command install_name_tool "Команда install_name_tool входит в Apple Command Line Tools. Переустановите или обновите их."
require_command otool "Команда otool входит в Apple Command Line Tools. Переустановите или обновите их."
if [[ "$CREATE_ARCHIVE" == true ]]; then
    require_command unzip "Команда unzip входит в macOS. Восстановите системные утилиты или обновите macOS."
fi

[[ -x /usr/libexec/PlistBuddy ]] || die \
    "Не найдена системная утилита PlistBuddy." \
    "Обновите или восстановите macOS."
[[ -x /usr/bin/plutil ]] || die \
    "Не найдена системная утилита plutil." \
    "Обновите или восстановите macOS."
[[ -f "$PROJECT_DIR/Package.swift" ]] || die \
    "Не найден Package.swift." \
    "Запускайте скрипт из полного репозитория Photo_Editor."
[[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]] || die \
    "Не найдена иконка Resources/AppIcon.icns." \
    "Восстановите файл из репозитория."
SPARKLE_FRAMEWORK="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

if [[ "$(uname -m)" != "arm64" ]]; then
    warn "Сборка выполняется не на Apple Silicon. Будет создан ARM64-файл, но запустить его на этом Mac нельзя."
fi

select_compatible_sdk
success "Найден совместимый SDK: $SELECTED_SDK"
success "Swift: $(swift --version 2>&1 | head -n 1)"

cd "$PROJECT_DIR"
mkdir -p "$MODULE_CACHE" "$PROJECT_DIR/dist"

CURRENT_STAGE="компиляция Swift"
info "Компиляция Photo_Editor $APP_VERSION для Apple Silicon"
BUILD_ENV=(CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" SDKROOT="$SELECTED_SDK")
BUILD_ARGUMENTS=(--disable-sandbox -c release --sdk "$SELECTED_SDK" --triple "$TARGET")

if ! env "${BUILD_ENV[@]}" swift build "${BUILD_ARGUMENTS[@]}"; then
    die \
        "Swift не смог скомпилировать проект." \
        "Посмотрите сообщения компилятора выше. Проверьте исходный код и совместимость Command Line Tools."
fi

BIN_PATH="$(env "${BUILD_ENV[@]}" swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path 2>/dev/null)"
BUILT_EXECUTABLE="$BIN_PATH/$EXECUTABLE_NAME"
[[ -x "$BUILT_EXECUTABLE" ]] || die \
    "После сборки не найден файл $EXECUTABLE_NAME." \
    "Удалите каталог .build и повторите сборку."

CURRENT_STAGE="создание пакета приложения"
info "Создание пакета приложения"
STAGING_ROOT="$(mktemp -d "$PROJECT_DIR/.build/app-bundle.XXXXXX")"
TEMP_PATHS+=("$STAGING_ROOT")
STAGING_APP="$STAGING_ROOT/$APP_NAME.app"
mkdir -p "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources" "$STAGING_APP/Contents/Frameworks"
cp "$BUILT_EXECUTABLE" "$STAGING_APP/Contents/MacOS/$EXECUTABLE_NAME"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$STAGING_APP/Contents/Resources/AppIcon.icns"
[[ -d "$SPARKLE_FRAMEWORK" ]] || die \
    "После сборки не найден Sparkle.framework." \
    "Проверьте доступ к GitHub и выполните swift package resolve."
ditto "$SPARKLE_FRAMEWORK" "$STAGING_APP/Contents/Frameworks/Sparkle.framework"

# SwiftPM links Sparkle through @rpath, but its standalone executable does not
# automatically inherit the conventional application-bundle Frameworks path.
# Embed it explicitly so the app launches on clean Macs without developer tools.
if ! otool -l "$STAGING_APP/Contents/MacOS/$EXECUTABLE_NAME" | grep -Fq "path @executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" \
        "$STAGING_APP/Contents/MacOS/$EXECUTABLE_NAME" || die \
        "Не удалось добавить путь загрузки встроенных framework." \
        "Проверьте Apple Command Line Tools и повторите сборку."
fi
otool -l "$STAGING_APP/Contents/MacOS/$EXECUTABLE_NAME" | \
    grep -Fq "path @executable_path/../Frameworks" || die \
    "В приложении отсутствует путь Contents/Frameworks." \
    "Сборка остановлена, чтобы не публиковать приложение, которое не запускается на чистом Mac."

INFO_PLIST="$STAGING_APP/Contents/Info.plist"
/usr/bin/plutil -create xml1 "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string ru" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $EXECUTABLE_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string local.photoprint.editor" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :LSArchitecturePriority array" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :LSArchitecturePriority:0 string arm64" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :LSRequiresNativeExecution bool true" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string https://github.com/Coloded/photo_editor/releases/latest/download/appcast.xml" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string ropoWqly4lY5ugC6KFxGAs6bLXi/ISF6Cnlh0eKwSX8=" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :SURequireSignedFeed bool true" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :SUVerifyUpdateBeforeExtraction bool true" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :SUAllowsAutomaticUpdates bool true" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :SUScheduledCheckInterval integer 86400" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :SUShowReleaseNotes bool true" "$INFO_PLIST"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :SURequireSignedFeed' "$INFO_PLIST")" == true ]] || die \
    "Отключена проверка подписи ленты обновлений." \
    "Не публикуйте сборку без SURequireSignedFeed."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUVerifyUpdateBeforeExtraction' "$INFO_PLIST")" == true ]] || die \
    "Не включена проверка обновления до распаковки." \
    "Sparkle не запустится без SUVerifyUpdateBeforeExtraction при подписанной ленте."

chmod +x "$STAGING_APP/Contents/MacOS/$EXECUTABLE_NAME"
EXECUTABLE_INFO="$(file "$STAGING_APP/Contents/MacOS/$EXECUTABLE_NAME")"
[[ "$EXECUTABLE_INFO" == *"arm64"* ]] || die \
    "Создан исполняемый файл неправильной архитектуры: $EXECUTABLE_INFO" \
    "Проверьте Swift toolchain и целевую архитектуру."

codesign --force --deep --sign - "$STAGING_APP/Contents/Frameworks/Sparkle.framework" || die \
    "Не удалось подписать Sparkle.framework локальной подписью." \
    "Проверьте установленный комплект Apple Command Line Tools и права на каталог проекта."
codesign --force --deep --sign - "$STAGING_APP" || die \
    "Не удалось подписать приложение локальной подписью." \
    "Проверьте установленный комплект Apple Command Line Tools и права на каталог проекта."
codesign --verify --deep --strict "$STAGING_APP" || die \
    "Не удалось проверить подпись приложения." \
    "Проверьте установленный комплект Apple Command Line Tools."

if [[ -e "$APP_DIR" ]]; then
    rm -rf "$APP_DIR"
fi
mv "$STAGING_APP" "$APP_DIR"
rmdir "$STAGING_ROOT"
success "Приложение создано: $APP_DIR"

CURRENT_STAGE="создание DMG-образа"
info "Создание установочного DMG-образа"
mkdir -p "$ARCHIVE_DIR"
DMG_STAGING="$(mktemp -d "$PROJECT_DIR/.build/dmg-root.XXXXXX")"
TEMP_PATHS+=("$DMG_STAGING")
ditto "$APP_DIR" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"
TEMP_DMG="$ARCHIVE_DIR/.$APP_NAME-$APP_VERSION-$$.dmg"
TEMP_PATHS+=("$TEMP_DMG")
hdiutil create \
    -volname "$APP_NAME $APP_VERSION" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$TEMP_DMG" >/dev/null || die \
        "Не удалось создать DMG-образ." \
        "Проверьте свободное место на диске и доступность системной утилиты hdiutil."
hdiutil verify "$TEMP_DMG" >/dev/null || die \
    "Созданный DMG-образ повреждён." \
    "Проверьте диск и повторите сборку."
mv -f "$TEMP_DMG" "$DMG_PATH"
rm -rf "$DMG_STAGING"
success "DMG создан и проверен: $DMG_PATH"

if [[ "$CREATE_ARCHIVE" == true ]]; then
    CURRENT_STAGE="создание ZIP-архива"
    info "Создание ZIP-архива"
    mkdir -p "$ARCHIVE_DIR"
    TEMP_ARCHIVE="$ARCHIVE_DIR/.$APP_NAME-$APP_VERSION-$$.zip"
    TEMP_PATHS+=("$TEMP_ARCHIVE")
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$TEMP_ARCHIVE"
    unzip -t "$TEMP_ARCHIVE" >/dev/null || die \
        "Проверка ZIP-архива завершилась ошибкой." \
        "Проверьте свободное место на диске и повторите сборку."
    mv -f "$TEMP_ARCHIVE" "$ARCHIVE_PATH"
    success "Архив создан: $ARCHIVE_PATH"
fi

if [[ "$INSTALL_APP" == true ]]; then
    CURRENT_STAGE="установка приложения"
    if ! ask_yes_no "Установить Photo_Editor $APP_VERSION в /Applications?"; then
        die \
            "Установка отменена или требует подтверждения." \
            "Запустите с --install в терминале либо добавьте --yes."
    fi
    info "Установка в /Applications"
    if ! ditto "$APP_DIR" "$INSTALL_PATH"; then
        die \
            "Не удалось записать приложение в /Applications." \
            "Проверьте права доступа или скопируйте dist/Photo_Editor.app в папку «Программы» вручную."
    fi
    codesign --verify --deep --strict "$INSTALL_PATH" || die \
        "Установленная копия не прошла проверку подписи." \
        "Удалите её и повторите установку."
    success "Установлено: $INSTALL_PATH"
fi

print -- ""
success "Сборка Photo_Editor $APP_VERSION завершена"
