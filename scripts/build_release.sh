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
