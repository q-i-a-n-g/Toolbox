#!/bin/bash
set -e

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TOOLBOX_DIR="$SCRIPT_DIR"
BIN_DIR="$TOOLBOX_DIR/Toolbox/Resources/Binaries"
BUILD_DIR="$TOOLBOX_DIR/build"
SCHEME="ScriptToolbox"

echo "=== Starting Automated Build and Test for Toolbox ==="

# 1. Compile App
echo "Step 1: Compiling Toolbox.app..."
cd "$TOOLBOX_DIR"
mkdir -p build

# Clean build
xcodebuild -project Toolbox.xcodeproj -scheme "$SCHEME" clean

# Build for Debug (faster for testing)
xcodebuild -project Toolbox.xcodeproj -scheme "$SCHEME" -configuration Debug \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR/Debug" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES > build_debug.log 2>&1 || {
        echo "Compilation failed! Check build_debug.log"
        exit 1
    }

echo "Compilation successful: $BUILD_DIR/Debug/Toolbox.app"

# 2. Prepare Binaries in App Bundle
echo "Step 2: Preparing binaries in app bundle..."
APP_BIN_DIR="$BUILD_DIR/Debug/Toolbox.app/Contents/Resources/Binaries"

# Process ffmpeg
echo "Processing ffmpeg..."
cd "$APP_BIN_DIR"
if [ -f "ffmpeg.zip" ]; then
    unzip -o ffmpeg.zip
    if [ -f "Toolbox/Toolbox/Resources/Binaries/ffmpeg" ]; then
        mv Toolbox/Toolbox/Resources/Binaries/ffmpeg .
        rm -rf Toolbox
    fi
    chmod +x ffmpeg
    # Optimization: Strip symbols from ffmpeg
    strip ffmpeg
    rm -f ffmpeg.zip
    echo "✓ ffmpeg optimized (stripped symbols)"
fi

# Process check_main_pkg
echo "Processing check_main_pkg..."
if [ -f "check_main_pkg.zip" ]; then
    rm -rf check_main_pkg  # Remove old directory
    unzip -o check_main_pkg.zip
    chmod +x check_main_pkg/check_main_bin
    
    # Optimization: Strip Node.js binary (suppress code signature warning)
    strip check_main_pkg/_internal/playwright/driver/node 2>&1 | grep -v "code signature" || true
    
    # Optimization: Remove unnecessary Playwright files
    rm -f check_main_pkg/_internal/playwright/driver/package/api.json
    rm -rf check_main_pkg/_internal/playwright/driver/package/types
    rm -f check_main_pkg/_internal/playwright/driver/package/protocol.yml
    rm -f check_main_pkg/_internal/playwright/driver/package/ThirdPartyNotices.txt
    rm -rf check_main_pkg/_internal/playwright/driver/package/bin
    rm -rf check_main_pkg/_internal/playwright/driver/package/lib/vite
    
    rm -f check_main_pkg.zip
    echo "✓ check_main_pkg optimized"
fi

cd "$SCRIPT_DIR"

# 3. Run Tests
echo "Step 3: Running automated tests..."

if [ -f "test_pty.swift" ]; then
    echo "Running PTY Process test..."
    swift test_pty.swift > test_pty.log 2>&1
    if [ $? -eq 0 ]; then
        echo "PTY Process test passed."
    else
        echo "PTY Process test failed! Check test_pty.log"
    fi
fi

# 4. Verify Bundle
echo "Step 4: Verifying app bundle..."
APP_PATH="$BUILD_DIR/Debug/Toolbox.app"
if [ -d "$APP_PATH" ]; then
    echo "App bundle exists at $APP_PATH"
    if [ -f "$APP_BIN_DIR/ffmpeg" ]; then
        echo "Verification passed: ffmpeg included in bundle."
    else
        echo "Verification failed: ffmpeg missing from bundle!"
    fi
    
    if [ -d "$APP_BIN_DIR/check_main_pkg" ]; then
        echo "Verification passed: check_main_pkg included in bundle."
    else
        echo "Verification failed: check_main_pkg missing from bundle!"
    fi
else
    echo "Verification failed: App bundle not found!"
    exit 1
fi

# 5. Cleanup source directory
echo "Step 5: Cleaning up source directory..."
if [ -d "$BIN_DIR/ffmpeg" ]; then
    rm -rf "$BIN_DIR/ffmpeg"
fi
if [ -d "$BIN_DIR/check_main_pkg" ]; then
    rm -rf "$BIN_DIR/check_main_pkg"
fi

echo "=== Automated Build and Test Completed Successfully ==="
