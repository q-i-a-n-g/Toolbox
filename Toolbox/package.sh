#!/bin/bash
set -e

echo "Starting build process for Toolbox..."

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SCHEME="${TOOLBOX_SCHEME:-ScriptToolbox}"
HOST_ARCH="$(uname -m)"

if [ "$HOST_ARCH" = "arm64" ]; then
    BUILD_ARCH="arm64"
    BUILD_DIR="build/arm64"
    BUILD_LABEL="Apple Silicon"
else
    BUILD_ARCH="x86_64"
    BUILD_DIR="build/x86_64"
    BUILD_LABEL="Intel"
fi

mkdir -p build
rm -rf build/arm64 build/x86_64 build/Debug build/Release
rm -f build/Toolbox_AppleSilicon.zip build/Toolbox_Intel.zip
rm -f Toolbox_AppleSilicon.zip Toolbox_Intel.zip
find Toolbox/Resources -name __pycache__ -type d -prune -exec rm -rf {} +

OCR_SWIFT="Toolbox/Resources/Binaries/ocr_vision.swift"
OCR_BIN="Toolbox/Resources/Binaries/ocr_vision_bin"
if [ -f "$OCR_SWIFT" ]; then
    xcrun swiftc -O "$OCR_SWIFT" -o "$OCR_BIN"
    chmod +x "$OCR_BIN"
fi

thin_binary_if_possible() {
    local arch="$1"
    local path="$2"
    local info=""
    if [ -f "$path" ] && info="$(lipo -info "$path" 2>/dev/null)"; then
        if echo "$info" | grep -q "Architectures in the fat file:" && echo "$info" | grep -q "$arch"; then
            lipo -thin "$arch" "$path" -output "$path.thin" && mv "$path.thin" "$path"
            chmod +x "$path"
        fi
    fi
}

thin_check_pkg() {
    local arch="$1"
    local app="$2"
    local pkg="$app/Contents/Resources/Binaries/check_main_pkg"
    # Do not lipo-thin PyInstaller executables after build: their PKG archive is
    # appended to the Mach-O and thinning breaks the embedded archive offsets.
    thin_binary_if_possible "$arch" "$pkg/_internal/playwright/driver/node"
}

echo "Building for $BUILD_LABEL ($BUILD_ARCH)..."
xcodebuild -project Toolbox.xcodeproj -scheme "$SCHEME" -configuration Release \
    ARCHS="$BUILD_ARCH" ONLY_ACTIVE_ARCH=NO \
    CONFIGURATION_BUILD_DIR="$(pwd)/$BUILD_DIR" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES > /dev/null

# Clean up zips inside the app bundle
rm -f "$BUILD_DIR/Toolbox.app/Contents/Resources/Binaries/ffmpeg_arm.zip"
rm -f "$BUILD_DIR/Toolbox.app/Contents/Resources/Binaries/ffmpeg_intel.zip"
rm -f "$BUILD_DIR/Toolbox.app/Contents/Resources/Binaries/check_main_pkg.zip"
find "$BUILD_DIR/Toolbox.app" -name __pycache__ -type d -prune -exec rm -rf {} +
# Strip symbols
strip -x "$BUILD_DIR/Toolbox.app/Contents/Resources/Binaries/ffmpeg" 2>/dev/null || true
strip -x "$BUILD_DIR/Toolbox.app/Contents/Resources/Binaries/ocr_vision_bin" 2>/dev/null || true
thin_check_pkg "$BUILD_ARCH" "$BUILD_DIR/Toolbox.app"
APP_ICONSET_SRC="Toolbox/Resources/Assets.xcassets/AppIcon.appiconset"
APP_ICON_OUT="$BUILD_DIR/Toolbox.app/Contents/Resources/AppIcon.icns"
if [ -d "$APP_ICONSET_SRC" ]; then
    TMP_ICON_ROOT="$(mktemp -d)"
    TMP_ICONSET="$TMP_ICON_ROOT/AppIcon.iconset"
    mkdir -p "$TMP_ICONSET"
    cp "$APP_ICONSET_SRC"/icon_*.png "$TMP_ICONSET"/
    iconutil -c icns "$TMP_ICONSET" -o "$APP_ICON_OUT"
    rm -rf "$TMP_ICON_ROOT"
fi
# Re-sign after resource slimming; removing sealed resources invalidates the Xcode signature.
codesign --force --deep --sign - --timestamp=none "$BUILD_DIR/Toolbox.app"

# Cleanup the unpacked source binary and architecture log to keep workspace pristine
rm -f Toolbox/Resources/Binaries/ffmpeg
rm -f Toolbox/Resources/Binaries/.last_ffmpeg_arch

echo "Packaging complete! App is available at:"
echo "  $BUILD_DIR/Toolbox.app"
