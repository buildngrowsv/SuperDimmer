#!/bin/bash

# ============================================================================
# SuperDimmer Release Builder
# ============================================================================
# One-command script to build the app AND create a DMG for distribution.
# This is the main script you'll use for creating releases.
#
# WHY: Combines multiple steps into one reliable process:
# 1. Clean build directory
# 2. Build Release configuration
# 3. Create DMG installer
# 4. (Optional) Sign and notarize
#
# USAGE:
#   ./build-release.sh              # Build and create DMG
#   ./build-release.sh --sign       # Build, sign, and create DMG
#   ./build-release.sh --notarize   # Build, sign, notarize, and create DMG
#
# PREREQUISITES:
#   - Xcode and command line tools
#   - For signing: Developer ID certificate in Keychain
#   - For notarization: APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID env vars
#
# Created: January 8, 2026
# ============================================================================

set -e  # Exit on any error

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="SuperDimmer"
SCHEME="SuperDimmer"
BUILD_DIR="$PROJECT_DIR/build"

# Code signing identity - update this with your actual Developer ID
# To list available identities: security find-identity -v -p codesigning
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"

# Parse arguments
DO_SIGN=false
DO_NOTARIZE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --sign)
            DO_SIGN=true
            shift
            ;;
        --notarize)
            DO_SIGN=true
            DO_NOTARIZE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--sign] [--notarize]"
            exit 1
            ;;
    esac
done

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_header() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║  $1"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""
}

print_step() {
    echo ""
    echo "▶ $1"
    echo "──────────────────────────────────────────────────────────────────────"
}

print_success() {
    echo "✅ $1"
}

print_error() {
    echo "❌ $1"
    exit 1
}

# ============================================================================
# BUILD PROCESS
# ============================================================================

print_header "SuperDimmer Release Builder"

# Step 1: Clean build directory
print_step "Step 1: Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/Release"
print_success "Build directory cleaned"

# Step 2: Build Release configuration
print_step "Step 2: Building ${APP_NAME} (Release)..."

cd "$PROJECT_DIR"

# Build using xcodebuild with explicit output directory
# CONFIGURATION_BUILD_DIR puts the .app directly where we want it
xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR/Release" \
    clean build 2>&1 | tail -n 30

# Verify app was built
APP_PATH="$BUILD_DIR/Release/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    print_error "Build failed - ${APP_NAME}.app not found at $APP_PATH"
fi

print_success "Build complete: $APP_PATH"

# Get version from built app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0.0")
echo "   Version: $VERSION"

# Step 3: Code signing (optional)
if [ "$DO_SIGN" = true ]; then
    print_step "Step 3: Code signing..."
    
    # Sign all frameworks first (if any)
    find "$APP_PATH/Contents/Frameworks" -name "*.framework" -o -name "*.dylib" 2>/dev/null | while read framework; do
        codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$framework"
    done
    
    # Sign the main app
    codesign --force --deep --verify --verbose \
        --sign "$SIGNING_IDENTITY" \
        --options runtime \
        --entitlements "$PROJECT_DIR/${APP_NAME}/Supporting Files/${APP_NAME}.entitlements" \
        "$APP_PATH"
    
    # Verify signature
    codesign -v "$APP_PATH"
    print_success "Code signing complete"
else
    print_step "Step 3: Skipping code signing (use --sign to enable)"
fi

# Step 4: Create DMG
print_step "Step 4: Creating DMG installer..."

cd "$SCRIPT_DIR"
./create-dmg.sh "$APP_PATH"

DMG_PATH="$SCRIPT_DIR/output/${APP_NAME}-v${VERSION}.dmg"

if [ ! -f "$DMG_PATH" ]; then
    print_error "DMG creation failed"
fi

print_success "DMG created: $DMG_PATH"

# Step 5: Sign DMG (if signing enabled)
if [ "$DO_SIGN" = true ]; then
    print_step "Step 5: Signing DMG..."
    codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"
    print_success "DMG signed"
fi

# Step 6: Notarize (if enabled)
if [ "$DO_NOTARIZE" = true ]; then
    print_step "Step 6: Notarizing..."
    
    if [ -z "$APPLE_ID" ] || [ -z "$APPLE_APP_PASSWORD" ] || [ -z "$APPLE_TEAM_ID" ]; then
        print_error "Notarization requires APPLE_ID, APPLE_APP_PASSWORD, and APPLE_TEAM_ID environment variables"
    fi
    
    # Submit for notarization
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait
    
    # Staple the ticket
    xcrun stapler staple "$DMG_PATH"
    
    print_success "Notarization complete"
fi

# ============================================================================
# SUMMARY
# ============================================================================

print_header "Release Build Complete!"

echo "  📦 App: $APP_PATH"
echo "  💿 DMG: $DMG_PATH"
echo "  📏 Size: $(du -h "$DMG_PATH" | cut -f1)"
echo "  🏷  Version: $VERSION"
echo ""

if [ "$DO_SIGN" = true ]; then
    echo "  ✅ Signed: Yes"
else
    echo "  ⚠️  Signed: No (use --sign for distribution)"
fi

if [ "$DO_NOTARIZE" = true ]; then
    echo "  ✅ Notarized: Yes"
else
    echo "  ⚠️  Notarized: No (use --notarize for public distribution)"
fi

echo ""
echo "  To test the DMG:"
echo "    open \"$DMG_PATH\""
echo ""

# Copy to website releases folder if it exists
RELEASES_DIR="$PROJECT_DIR/../SuperDimmer-Website/releases"
if [ -d "$(dirname "$RELEASES_DIR")" ]; then
    mkdir -p "$RELEASES_DIR"
    cp "$DMG_PATH" "$RELEASES_DIR/"
    echo "  📋 Also copied to: $RELEASES_DIR/"
fi

echo ""
