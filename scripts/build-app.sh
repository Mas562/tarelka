#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p "$PWD/dist"

# Prefer Xcode's matching compiler and SDK; respect an explicit toolchain choice.
source scripts/toolchain.sh
# Keep the same build engine and output paths across Swift toolchain versions.
swift build --build-system native -c release --scratch-path .build --cache-path .build/cache --disable-sandbox
swift packaging/DrawIcon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o packaging/AppIcon.icns
TARELKA_BIN_DIR=$(swift build --build-system native -c release --scratch-path .build --show-bin-path)
# Sign outside iCloud Documents so Finder cannot race the signature with metadata.
TARELKA_STAGE=$(mktemp -d /private/tmp/tarelka-build.XXXXXX)
TARELKA_VERIFY_DIR=""
cleanup() {
    rm -rf "$TARELKA_STAGE"
    if [[ -n "$TARELKA_VERIFY_DIR" ]]; then rm -rf "$TARELKA_VERIFY_DIR"; fi
}
trap cleanup EXIT
TARELKA_BUNDLE="$TARELKA_STAGE/Тарелка.app"
mkdir -p "$TARELKA_BUNDLE/Contents/MacOS" "$TARELKA_BUNDLE/Contents/Resources" "$TARELKA_BUNDLE/Contents/PlugIns/TarelkaWidget.appex/Contents/MacOS"
cp "$TARELKA_BIN_DIR/Tarelka" "$TARELKA_BUNDLE/Contents/MacOS/Tarelka"
cp "$TARELKA_BIN_DIR/TarelkaWidget" "$TARELKA_BUNDLE/Contents/PlugIns/TarelkaWidget.appex/Contents/MacOS/TarelkaWidget"
cp packaging/WidgetInfo.plist "$TARELKA_BUNDLE/Contents/PlugIns/TarelkaWidget.appex/Contents/Info.plist"
ditto --norsrc --noextattr "$TARELKA_BIN_DIR/Tarelka_NutritionCore.bundle" "$TARELKA_BUNDLE/Contents/Resources/Tarelka_NutritionCore.bundle"
cp packaging/Info.plist "$TARELKA_BUNDLE/Contents/Info.plist"
cp docs/AppleWatch.md "$TARELKA_BUNDLE/Contents/Resources/AppleWatch.md"
cp docs/AppleWatch.md "$PWD/dist/Apple Watch.md"
if [[ -f packaging/AppIcon.icns ]]; then
    cp packaging/AppIcon.icns "$TARELKA_BUNDLE/Contents/Resources/AppIcon.icns"
fi
# Finder can add these attributes when the project is inside iCloud Documents.
xattr -rd com.apple.FinderInfo "$TARELKA_BUNDLE" 2>/dev/null || true
xattr -rd com.apple.ResourceFork "$TARELKA_BUNDLE" 2>/dev/null || true
codesign --force --sign - --identifier app.tarelka.personal.today-widget --entitlements packaging/Widget.entitlements "$TARELKA_BUNDLE/Contents/PlugIns/TarelkaWidget.appex"
codesign --force --sign - --identifier app.tarelka.personal "$TARELKA_BUNDLE"
codesign --verify --deep --strict "$TARELKA_BUNDLE"
ditto -c -k --norsrc --noextattr --keepParent "$TARELKA_BUNDLE" "$PWD/dist/Тарелка.zip"
ditto --norsrc --noextattr "$TARELKA_BUNDLE" "$PWD/dist/Тарелка.app"
xattr -rd com.apple.FinderInfo "$PWD/dist/Тарелка.app" 2>/dev/null || true
xattr -rd com.apple.ResourceFork "$PWD/dist/Тарелка.app" 2>/dev/null || true
# iCloud Drive may later add Finder attributes to the loose app copy. Verify the
# distributable archive after extraction outside iCloud, as users will install it.
TARELKA_VERIFY_DIR=$(mktemp -d /private/tmp/tarelka-verify.XXXXXX)
ditto -x -k "$PWD/dist/Тарелка.zip" "$TARELKA_VERIFY_DIR"
codesign --verify --deep --strict "$TARELKA_VERIFY_DIR/Тарелка.app"
print "Готово: $PWD/dist/Тарелка.zip"
