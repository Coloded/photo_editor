#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_NAME="Photo_Editor"
APP_DIR="$PROJECT_DIR/dist/$APP_NAME.app"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
MODULE_CACHE="$PROJECT_DIR/.build/ModuleCache"

cd "$PROJECT_DIR"
env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" SDKROOT="$SDK_PATH" \
  swift build --disable-sandbox -c release --sdk "$SDK_PATH" \
  --triple arm64-apple-macosx13.0

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/.build/release/PhotoPrintEditor" "$APP_DIR/Contents/MacOS/PhotoPrintEditor"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

/usr/libexec/PlistBuddy -c "Clear dict" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string ru" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string PhotoPrintEditor" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string local.photoprint.editor" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.2" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 3" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSArchitecturePriority array" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSArchitecturePriority:0 string arm64" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSRequiresNativeExecution bool true" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" "$APP_DIR/Contents/Info.plist"

chmod +x "$APP_DIR/Contents/MacOS/PhotoPrintEditor"
file "$APP_DIR/Contents/MacOS/PhotoPrintEditor" | rg -q "arm64"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
