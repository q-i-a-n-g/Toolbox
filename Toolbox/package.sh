#!/bin/bash
set -e

echo "Starting build process for Toolbox..."

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
BIN_DIR="Toolbox/Resources/Binaries"
FFMPEG_ORIG="$BIN_DIR/ffmpeg"
FFMPEG_BAK="$(pwd)/build/ffmpeg.universal.bak"
SCHEME="${TOOLBOX_SCHEME:-ScriptToolbox}"

mkdir -p build
rm -rf build/arm64 build/x86_64

cp "$FFMPEG_ORIG" "$FFMPEG_BAK"

echo "Building for Apple Silicon (arm64)..."
lipo -extract arm64 "$FFMPEG_BAK" -output "$FFMPEG_ORIG"
xcodebuild -project Toolbox.xcodeproj -scheme "$SCHEME" -configuration Release \
    ARCHS="arm64" ONLY_ACTIVE_ARCH=NO \
    CONFIGURATION_BUILD_DIR="$(pwd)/build/arm64" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES > /dev/null
rm -f build/arm64/Toolbox.app/Contents/Resources/Binaries/ffmpeg.bak
rm -f build/arm64/Toolbox.app/Contents/Resources/Binaries/ffmpeg.zip
rm -f build/arm64/Toolbox.app/Contents/Resources/Binaries/check_main_pkg.zip

echo "Zipping arm64 app..."
pushd build/arm64 > /dev/null
zip -q9ry Toolbox_AppleSilicon.zip Toolbox.app
popd > /dev/null

echo "Building for Intel (x86_64)..."
lipo -extract x86_64 "$FFMPEG_BAK" -output "$FFMPEG_ORIG"
xcodebuild -project Toolbox.xcodeproj -scheme "$SCHEME" -configuration Release \
    ARCHS="x86_64" ONLY_ACTIVE_ARCH=NO \
    CONFIGURATION_BUILD_DIR="$(pwd)/build/x86_64" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES > /dev/null
rm -f build/x86_64/Toolbox.app/Contents/Resources/Binaries/ffmpeg.bak
rm -f build/x86_64/Toolbox.app/Contents/Resources/Binaries/ffmpeg.zip
rm -f build/x86_64/Toolbox.app/Contents/Resources/Binaries/check_main_pkg.zip

echo "Zipping x86_64 app..."
pushd build/x86_64 > /dev/null
zip -q9ry Toolbox_Intel.zip Toolbox.app
popd > /dev/null

mv "$FFMPEG_BAK" "$FFMPEG_ORIG"

cp build/arm64/Toolbox_AppleSilicon.zip .
cp build/x86_64/Toolbox_Intel.zip .
if [ -n "$TOOLBOX_PACKAGE_OUTPUT_DIR" ] && [ -d "$TOOLBOX_PACKAGE_OUTPUT_DIR" ]; then
  cp build/arm64/Toolbox_AppleSilicon.zip "$TOOLBOX_PACKAGE_OUTPUT_DIR/"
  cp build/x86_64/Toolbox_Intel.zip "$TOOLBOX_PACKAGE_OUTPUT_DIR/"
fi

echo "Packaging complete!"
