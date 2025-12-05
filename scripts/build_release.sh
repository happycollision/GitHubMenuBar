#!/bin/bash

# GitHubMenuBar Release Build Script
# Builds a distributable .app bundle and creates a ZIP file

set -e  # Exit on error

# Configuration
APP_NAME="GitHubMenuBar"
BUNDLE_ID="com.github.menubar"
BUILD_DIR=".build/release"
OUTPUT_DIR="dist"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
ZIP_FILE="${OUTPUT_DIR}/${APP_NAME}.zip"

# Get version from Info.plist
VERSION=$(defaults read "$(pwd)/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")

echo "🔨 Building ${APP_NAME} v${VERSION}..."

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

# Build with Swift Package Manager
echo "⚙️  Building release binary with Swift PM..."
swift build -c release

# Create .app bundle structure
echo "📦 Creating .app bundle structure..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy binary
echo "📋 Copying binary..."
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

# Copy Info.plist
echo "📋 Copying Info.plist..."
cp Info.plist "${APP_BUNDLE}/Contents/"

# Generate app icon from PNG
echo "🎨 Generating app icon from PNG..."
ICON_PNG="icons/AppIcon.png"
if [ -f "${ICON_PNG}" ]; then
    # Create iconset directory
    ICONSET_DIR="/tmp/GitHubMenuBar.iconset"
    rm -rf "${ICONSET_DIR}"
    mkdir -p "${ICONSET_DIR}"

    # Generate all required icon sizes using sips
    sips -z 16 16     "${ICON_PNG}" --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null
    sips -z 32 32     "${ICON_PNG}" --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null
    sips -z 32 32     "${ICON_PNG}" --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null
    sips -z 64 64     "${ICON_PNG}" --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null
    sips -z 128 128   "${ICON_PNG}" --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null
    sips -z 256 256   "${ICON_PNG}" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null
    sips -z 256 256   "${ICON_PNG}" --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null
    sips -z 512 512   "${ICON_PNG}" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null
    sips -z 512 512   "${ICON_PNG}" --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null
    sips -z 1024 1024 "${ICON_PNG}" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null

    # Convert iconset to icns
    iconutil -c icns "${ICONSET_DIR}" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

    if [ -f "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" ]; then
        echo "✅ App icon generated successfully"
    else
        echo "⚠️  Warning: Failed to generate AppIcon.icns"
    fi

    # Clean up temporary iconset
    rm -rf "${ICONSET_DIR}"
else
    echo "⚠️  Warning: ${ICON_PNG} not found, skipping icon generation"
fi

# Compile Liquid Glass icon bundle for macOS Tahoe
LIQUID_ICON="icons/GithubMenuBar.icon"
if [ -d "${LIQUID_ICON}" ]; then
    echo "🎨 Compiling Liquid Glass icon..."
    if xcrun --find actool > /dev/null 2>&1; then
        xcrun actool "${LIQUID_ICON}" \
            --app-icon GithubMenuBar \
            --compile "${APP_BUNDLE}/Contents/Resources" \
            --platform macosx \
            --target-device mac \
            --minimum-deployment-target 13.0 \
            --output-partial-info-plist /dev/null 2>&1 | grep -v "^$" || true
        if [ -f "${APP_BUNDLE}/Contents/Resources/Assets.car" ]; then
            echo "✅ Liquid Glass icon compiled successfully"
        else
            echo "⚠️  Warning: actool ran but Assets.car not found, copying bundle as fallback"
            cp -R "${LIQUID_ICON}" "${APP_BUNDLE}/Contents/Resources/"
        fi
    else
        echo "⚠️  Warning: actool not found (Xcode required), copying raw bundle as fallback"
        cp -R "${LIQUID_ICON}" "${APP_BUNDLE}/Contents/Resources/"
    fi
else
    echo "⚠️  Warning: ${LIQUID_ICON} not found, skipping Liquid Glass icon"
fi

# Create PkgInfo file (optional but traditional)
echo "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Make binary executable
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Create ZIP file
echo "🗜️  Creating ZIP archive..."
cd "${OUTPUT_DIR}"
zip -r "${APP_NAME}.zip" "${APP_NAME}.app" > /dev/null
cd ..

# Calculate file sizes
APP_SIZE=$(du -sh "${APP_BUNDLE}" | cut -f1)
ZIP_SIZE=$(du -sh "${ZIP_FILE}" | cut -f1)

echo "✅ Build complete!"
echo ""
echo "📊 Build Information:"
echo "   Version: ${VERSION}"
echo "   App size: ${APP_SIZE}"
echo "   ZIP size: ${ZIP_SIZE}"
echo ""
echo "📂 Output files:"
echo "   App bundle: ${APP_BUNDLE}"
echo "   ZIP file: ${ZIP_FILE}"
echo ""
echo "⚠️  Note: This is an unsigned build. Users will need to:"
echo "   1. Right-click the app and select 'Open' (first time only)"
echo "   2. Or run: xattr -cr ${APP_NAME}.app"
