#!/bin/bash
set -e

echo "Starting build process for Toolbox..."

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SCHEME="${TOOLBOX_SCHEME:-ScriptToolbox}"

mkdir -p build
rm -rf build/arm64 build/x86_64

echo "Building for Apple Silicon (arm64)..."
xcodebuild -project Toolbox.xcodeproj -scheme "$SCHEME" -configuration Release \
    ARCHS="arm64" ONLY_ACTIVE_ARCH=NO \
    CONFIGURATION_BUILD_DIR="$(pwd)/build/arm64" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES > /dev/null

# Clean up zips inside the arm64 app bundle
rm -f build/arm64/Toolbox.app/Contents/Resources/Binaries/ffmpeg_arm.zip
rm -f build/arm64/Toolbox.app/Contents/Resources/Binaries/ffmpeg_intel.zip
rm -f build/arm64/Toolbox.app/Contents/Resources/Binaries/check_main_pkg.zip
# Strip symbols
strip -x build/arm64/Toolbox.app/Contents/Resources/Binaries/ffmpeg 2>/dev/null || true
# Re-sign after resource slimming; removing sealed resources invalidates the Xcode signature.
codesign --force --deep --sign - --timestamp=none build/arm64/Toolbox.app

echo "Zipping arm64 app..."
pushd build/arm64 > /dev/null
zip -q9ry Toolbox_AppleSilicon.zip Toolbox.app
popd > /dev/null

echo "Building for Intel (x86_64)..."
xcodebuild -project Toolbox.xcodeproj -scheme "$SCHEME" -configuration Release \
    ARCHS="x86_64" ONLY_ACTIVE_ARCH=NO \
    CONFIGURATION_BUILD_DIR="$(pwd)/build/x86_64" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES > /dev/null

# Clean up zips inside the x86_64 app bundle
rm -f build/x86_64/Toolbox.app/Contents/Resources/Binaries/ffmpeg_arm.zip
rm -f build/x86_64/Toolbox.app/Contents/Resources/Binaries/ffmpeg_intel.zip
rm -f build/x86_64/Toolbox.app/Contents/Resources/Binaries/check_main_pkg.zip
# Strip symbols
strip -x build/x86_64/Toolbox.app/Contents/Resources/Binaries/ffmpeg 2>/dev/null || true
# Re-sign after resource slimming; removing sealed resources invalidates the Xcode signature.
codesign --force --deep --sign - --timestamp=none build/x86_64/Toolbox.app

echo "Zipping x86_64 app..."
pushd build/x86_64 > /dev/null
zip -q9ry Toolbox_Intel.zip Toolbox.app
popd > /dev/null

cp build/arm64/Toolbox_AppleSilicon.zip .
cp build/x86_64/Toolbox_Intel.zip .
if [ -n "$TOOLBOX_PACKAGE_OUTPUT_DIR" ] && [ -d "$TOOLBOX_PACKAGE_OUTPUT_DIR" ]; then
  cp build/arm64/Toolbox_AppleSilicon.zip "$TOOLBOX_PACKAGE_OUTPUT_DIR/"
  cp build/x86_64/Toolbox_Intel.zip "$TOOLBOX_PACKAGE_OUTPUT_DIR/"
fi

# Cleanup the unpacked source binary and architecture log to keep workspace pristine
rm -f Toolbox/Resources/Binaries/ffmpeg
rm -f Toolbox/Resources/Binaries/.last_ffmpeg_arch

echo "Packaging complete!"
