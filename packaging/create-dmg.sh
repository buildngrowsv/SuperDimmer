#!/bin/bash

# ============================================================================
# SuperDimmer DMG Creator Script
# ============================================================================
# This script packages the SuperDimmer.app into a distributable DMG file.
# It creates a beautiful installer DMG with a custom background and icon layout.
#
# WHY: macOS users expect apps to be distributed as DMG files that show the app
# alongside an Applications folder alias. This provides a familiar drag-to-install
# experience that is intuitive and professional.
#
# PREREQUISITES:
# - Xcode command line tools installed
# - SuperDimmer.app built (via Xcode or xcodebuild)
# - Optional: create-dmg tool installed (brew install create-dmg)
#   If not installed, falls back to hdiutil method
#
# USAGE:
#   ./create-dmg.sh                    # Uses default Release build
#   ./create-dmg.sh /path/to/App.app   # Uses specified app bundle
#
# OUTPUT:
#   Creates SuperDimmer-vX.X.X.dmg in the packaging/output/ folder
#
# Created: January 8, 2026
# ============================================================================

set -e  # Exit on any error

# ============================================================================
# CONFIGURATION
# ============================================================================
# These values control the DMG appearance and metadata.
# Adjust as needed for different versions or branding changes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# App metadata - pulled from Info.plist if possible, with fallbacks
APP_NAME="SuperDimmer"
BUNDLE_ID="com.superdimmer.app"

# DMG window dimensions and icon positions
# These are carefully tuned to look good with the background image
DMG_WINDOW_WIDTH=660
DMG_WINDOW_HEIGHT=400
ICON_SIZE=128
APP_ICON_X=180      # X position of app icon
APP_ICON_Y=170      # Y position of app icon  
APPS_ICON_X=480     # X position of Applications alias
APPS_ICON_Y=170     # Y position of Applications alias

# Output directories
OUTPUT_DIR="$SCRIPT_DIR/output"
BUILD_DIR="$PROJECT_DIR/build"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Print colored status messages for better visibility in terminal
print_status() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🔧 $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_success() {
    echo ""
    echo "  ✅ $1"
    echo ""
}

print_error() {
    echo ""
    echo "  ❌ ERROR: $1"
    echo ""
    exit 1
}

print_warning() {
    echo ""
    echo "  ⚠️  WARNING: $1"
    echo ""
}

# Get version from Info.plist
# This reads the CFBundleShortVersionString from the app's Info.plist
# so the DMG filename automatically matches the app version.
get_app_version() {
    local app_path="$1"
    local plist_path="$app_path/Contents/Info.plist"
    
    if [ -f "$plist_path" ]; then
        /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$plist_path" 2>/dev/null || echo "1.0.0"
    else
        echo "1.0.0"
    fi
}

# Check if create-dmg is installed (preferred method)
# create-dmg is a npm/brew package that makes beautiful DMGs easily
has_create_dmg() {
    command -v create-dmg &> /dev/null
}

# ============================================================================
# FIND OR BUILD THE APP
# ============================================================================

find_app_bundle() {
    local app_path=""
    
    # If argument provided, use that
    if [ -n "$1" ]; then
        if [ -d "$1" ] && [[ "$1" == *.app ]]; then
            app_path="$1"
        else
            print_error "Provided path is not a valid .app bundle: $1"
        fi
    else
        # Look for app in common build locations
        # Priority: Archive export > Build/Products/Release > DerivedData
        
        # Check for exported archive first (most likely for distribution)
        if [ -d "$BUILD_DIR/export/${APP_NAME}.app" ]; then
            app_path="$BUILD_DIR/export/${APP_NAME}.app"
        
        # Check standard Xcode build output
        elif [ -d "$BUILD_DIR/Build/Products/Release/${APP_NAME}.app" ]; then
            app_path="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"
        
        # Check DerivedData (developer builds)
        else
            local derived_data_path=$(find ~/Library/Developer/Xcode/DerivedData -name "${APP_NAME}.app" -path "*/Release/*" 2>/dev/null | head -1)
            if [ -n "$derived_data_path" ]; then
                app_path="$derived_data_path"
            fi
        fi
    fi
    
    echo "$app_path"
}

# ============================================================================
# DMG CREATION METHODS
# ============================================================================

# Method 1: Use create-dmg tool (prettier, easier)
# This creates a professional-looking DMG with custom background,
# icon positioning, and proper window sizing.
create_dmg_with_tool() {
    local app_path="$1"
    local version="$2"
    local dmg_path="$OUTPUT_DIR/${APP_NAME}-v${version}.dmg"
    local background_path="$SCRIPT_DIR/background.png"
    
    print_status "Creating DMG using create-dmg tool..."
    
    # Build the create-dmg command with all options
    local cmd="create-dmg"
    cmd+=" --volname \"${APP_NAME}\""
    cmd+=" --window-pos 200 120"
    cmd+=" --window-size ${DMG_WINDOW_WIDTH} ${DMG_WINDOW_HEIGHT}"
    cmd+=" --icon-size ${ICON_SIZE}"
    cmd+=" --icon \"${APP_NAME}.app\" ${APP_ICON_X} ${APP_ICON_Y}"
    cmd+=" --app-drop-link ${APPS_ICON_X} ${APPS_ICON_Y}"
    cmd+=" --hide-extension \"${APP_NAME}.app\""
    
    # Add background if it exists
    if [ -f "$background_path" ]; then
        cmd+=" --background \"$background_path\""
    fi
    
    # Add text size
    cmd+=" --text-size 14"
    
    # Output path and source
    cmd+=" \"$dmg_path\""
    cmd+=" \"$app_path\""
    
    # Remove existing DMG if it exists
    rm -f "$dmg_path"
    
    # Execute the command
    eval $cmd
    
    echo "$dmg_path"
}

# Method 2: Use hdiutil directly (fallback, works everywhere)
# This is more manual but doesn't require additional tools.
# It creates a functional DMG but with less visual polish.
# WHY: Not everyone has create-dmg installed, so this provides a working fallback
# that uses only built-in macOS tools.
# NOTE: All status output goes to stderr so stdout only has the final dmg_path
create_dmg_with_hdiutil() {
    local app_path="$1"
    local version="$2"
    local dmg_path="$OUTPUT_DIR/${APP_NAME}-v${version}.dmg"
    local staging_dir="$OUTPUT_DIR/staging"
    
    # All echo/status goes to stderr so it doesn't interfere with return value
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "  🔧 Creating DMG using hdiutil (fallback method)..." >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    
    # Clean up any previous staging
    rm -rf "$staging_dir" 2>/dev/null || true
    rm -f "$dmg_path" 2>/dev/null || true
    
    # Create staging directory and copy app
    mkdir -p "$staging_dir"
    echo "  Copying app to staging..." >&2
    cp -R "$app_path" "$staging_dir/"
    
    # Create Applications symlink for drag-to-install
    # WHY: This allows users to drag the app to the Applications alias
    ln -s /Applications "$staging_dir/Applications"
    
    # Create the DMG directly from the staging folder
    # Using UDZO format for good compression
    # WHY: hdiutil create with -srcfolder is the simplest reliable approach
    echo "  Creating compressed DMG..." >&2
    hdiutil create \
        -srcfolder "$staging_dir" \
        -volname "${APP_NAME}" \
        -format UDZO \
        -o "$dmg_path" >&2
    
    # Clean up staging
    rm -rf "$staging_dir"
    
    # Return the path via stdout (captured by command substitution)
    echo "$dmg_path"
}

# ============================================================================
# NOTARIZATION (for distribution)
# ============================================================================

# Notarize the DMG for distribution outside the Mac App Store
# This is required for Gatekeeper to allow the app to run without warnings.
# Requires Apple Developer ID and app-specific password configured.
notarize_dmg() {
    local dmg_path="$1"
    
    # Check if credentials are configured
    if [ -z "$APPLE_ID" ] || [ -z "$APPLE_APP_PASSWORD" ] || [ -z "$APPLE_TEAM_ID" ]; then
        print_warning "Notarization skipped - credentials not configured"
        echo "To enable notarization, set these environment variables:"
        echo "  export APPLE_ID=\"your@email.com\""
        echo "  export APPLE_APP_PASSWORD=\"xxxx-xxxx-xxxx-xxxx\""
        echo "  export APPLE_TEAM_ID=\"XXXXXXXXXX\""
        return 0
    fi
    
    print_status "Submitting for notarization..."
    
    xcrun notarytool submit "$dmg_path" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait
    
    print_status "Stapling notarization ticket..."
    
    xcrun stapler staple "$dmg_path"
    
    print_success "Notarization complete!"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                    ║"
    echo "║              SuperDimmer DMG Package Creator                       ║"
    echo "║                                                                    ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Find the app bundle
    print_status "Locating ${APP_NAME}.app..."
    
    local app_path=$(find_app_bundle "$1")
    
    if [ -z "$app_path" ] || [ ! -d "$app_path" ]; then
        print_error "Could not find ${APP_NAME}.app bundle.
        
Please build the app first:
  xcodebuild -scheme SuperDimmer -configuration Release build
  
Or provide the path directly:
  $0 /path/to/${APP_NAME}.app"
    fi
    
    print_success "Found app: $app_path"
    
    # Get version
    local version=$(get_app_version "$app_path")
    echo "  Version: $version"
    
    # Check code signing
    print_status "Verifying code signature..."
    if codesign -v "$app_path" 2>/dev/null; then
        print_success "Code signature valid"
    else
        print_warning "App is not code signed - this is fine for development, but required for distribution"
    fi
    
    # Create the DMG
    local dmg_path=""
    if has_create_dmg; then
        dmg_path=$(create_dmg_with_tool "$app_path" "$version")
    else
        print_warning "create-dmg tool not found, using hdiutil fallback"
        echo "  For prettier DMGs, install: brew install create-dmg"
        dmg_path=$(create_dmg_with_hdiutil "$app_path" "$version")
    fi
    
    # Verify DMG was created
    if [ ! -f "$dmg_path" ]; then
        print_error "DMG creation failed"
    fi
    
    # Optional: Notarize for distribution
    if [ "$NOTARIZE" = "true" ]; then
        notarize_dmg "$dmg_path"
    fi
    
    # Print summary
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                         DMG Created Successfully!                  ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  📦 Output: $dmg_path"
    echo "  📏 Size: $(du -h "$dmg_path" | cut -f1)"
    echo ""
    echo "  To notarize for distribution, run:"
    echo "    NOTARIZE=true APPLE_ID=... APPLE_APP_PASSWORD=... APPLE_TEAM_ID=... $0"
    echo ""
    echo "  To test the DMG:"
    echo "    open \"$dmg_path\""
    echo ""
}

# Run main with all arguments
main "$@"
