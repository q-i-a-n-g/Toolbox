#!/bin/bash
set -e

echo "Starting build process for Toolbox..."

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
BIN_DIR="Toolbox/Resources/Binaries"
FFMPEG_ORIG="$BIN_DIR/ffmpeg"
FFMPEG_BAK="$(pwd)/build/ffmpeg.universal.bak"

mkdir -p build
rm -rf build/arm64 build/x86_64

cp "$FFMPEG_ORIG" "$FFMPEG_BAK"

echo "Building for Apple Silicon (arm64)..."
lipo -extract arm64 "$FFMPEG_BAK" -output "$FFMPEG_ORIG"
xcodebuild -project Toolbox.xcodeproj -scheme Toolbox -configuration Release \
    ARCHS="arm64" ONLY_ACTIVE_ARCH=NO \
    CONFIGURATION_BUILD_DIR="$(pwd)/build/arm64" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES > /dev/null
rm -f build/arm64/Toolbox.app/Contents/Resources/Binaries/ffmpeg.bak

echo "Zipping arm64 app..."
pushd build/arm64 > /dev/null
zip -qry Toolbox_AppleSilicon.zip Toolbox.app
popd > /dev/null

echo "Building for Intel (x86_64)..."
lipo -extract x86_64 "$FFMPEG_BAK" -output "$FFMPEG_ORIG"
xcodebuild -project Toolbox.xcodeproj -scheme Toolbox -configuration Release \
    ARCHS="x86_64" ONLY_ACTIVE_ARCH=NO \
    CONFIGURATION_BUILD_DIR="$(pwd)/build/x86_64" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES > /dev/null
rm -f build/x86_64/Toolbox.app/Contents/Resources/Binaries/ffmpeg.bak

echo "Zipping x86_64 app..."
pushd build/x86_64 > /dev/null
zip -qry Toolbox_Intel.zip Toolbox.app
popd > /dev/null

mv "$FFMPEG_BAK" "$FFMPEG_ORIG"

cp build/arm64/Toolbox_AppleSilicon.zip .
cp build/x86_64/Toolbox_Intel.zip .
cp build/arm64/Toolbox_AppleSilicon.zip /Users/liu/Desktop/
cp build/x86_64/Toolbox_Intel.zip /Users/liu/Desktop/

echo "Packaging complete!"
