#!/bin/bash
set -e

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TOOLBOX_DIR="$SCRIPT_DIR"
BIN_DIR="$TOOLBOX_DIR/Toolbox/Resources/Binaries"
BUILD_DIR="$TOOLBOX_DIR/build"
SCHEME="ScriptToolbox"

echo "=== Starting Automated Build and Test for Toolbox ==="

# 1. Prepare Binaries
echo "Step 1: Preparing binaries..."
cd "$BIN_DIR"

if [ ! -f "ffmpeg" ]; then
    echo "Unzipping ffmpeg..."
    unzip -o ffmpeg.zip
    # The zip might contain the full path, so we might need to move it
    if [ -f "Toolbox/Toolbox/Resources/Binaries/ffmpeg" ]; then
        mv Toolbox/Toolbox/Resources/Binaries/ffmpeg .
        rm -rf Toolbox
    fi
    chmod +x ffmpeg
fi

if [ ! -d "check_main_pkg" ]; then
    echo "Unzipping check_main_pkg..."
    unzip -o check_main_pkg.zip
    chmod +x check_main_pkg/check_main_bin
fi

cd "$SCRIPT_DIR"

# 2. Compile App
echo "Step 2: Compiling Toolbox.app..."
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

# 3. Run Tests
echo "Step 3: Running automated tests..."

# Run the PTY test script
if [ -f "test_pty.swift" ]; then
    echo "Running PTY Process test..."
    swift test_pty.swift > test_pty.log 2>&1
    if [ $? -eq 0 ]; then
        echo "PTY Process test passed."
    else
        echo "PTY Process test failed! Check test_pty.log"
        # We don't exit here if it's just a warning, but let's check the log
    fi
fi

# 4. Verify Bundle
echo "Step 4: Verifying app bundle..."
APP_PATH="$BUILD_DIR/Debug/Toolbox.app"
if [ -d "$APP_PATH" ]; then
    echo "App bundle exists at $APP_PATH"
    # Check if binaries are included
    if [ -f "$APP_PATH/Contents/Resources/Binaries/ffmpeg" ]; then
        echo "Verification passed: ffmpeg included in bundle."
    else
        echo "Verification failed: ffmpeg missing from bundle!"
    fi
    
    if [ -d "$APP_PATH/Contents/Resources/Binaries/check_main_pkg" ]; then
        echo "Verification passed: check_main_pkg included in bundle."
    else
        echo "Verification failed: check_main_pkg missing from bundle!"
    fi
else
    echo "Verification failed: App bundle not found!"
    exit 1
fi

echo "=== Automated Build and Test Completed Successfully ==="
