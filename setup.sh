#!/bin/bash
# =====================================================================
# SuperDimmer Project Setup Script
# =====================================================================
#
# This script sets up the SuperDimmer Xcode project.
#
# USAGE:
#   chmod +x setup.sh
#   ./setup.sh
#
# WHAT IT DOES:
#   1. Checks for XcodeGen (installs if needed)
#   2. Generates the Xcode project from project.yml
#   3. Opens the project in Xcode
#
# =====================================================================

set -e  # Exit on any error

echo "🌟 SuperDimmer Project Setup"
echo "============================="
echo ""

# Check if we're in the right directory
if [ ! -f "project.yml" ]; then
    echo "❌ Error: project.yml not found"
    echo "   Please run this script from the SuperDimmer-Mac-App directory"
    exit 1
fi

# Check for XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo "📦 XcodeGen not found. Installing via Homebrew..."
    
    # Check for Homebrew
    if ! command -v brew &> /dev/null; then
        echo "❌ Error: Homebrew is required to install XcodeGen"
        echo "   Install Homebrew first: https://brew.sh"
        exit 1
    fi
    
    brew install xcodegen
    echo "✅ XcodeGen installed"
else
    echo "✅ XcodeGen found"
fi

# Generate the Xcode project
echo ""
echo "🔨 Generating Xcode project..."
xcodegen generate

if [ -f "SuperDimmer.xcodeproj/project.pbxproj" ]; then
    echo "✅ Xcode project generated successfully!"
else
    echo "❌ Error: Project generation failed"
    exit 1
fi

# Ask to open in Xcode
echo ""
read -p "🚀 Open project in Xcode? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open SuperDimmer.xcodeproj
    echo "✅ Opened in Xcode"
fi

echo ""
echo "============================="
echo "📋 Next Steps:"
echo ""
echo "1. In Xcode, select your Development Team:"
echo "   SuperDimmer target > Signing & Capabilities > Team"
echo ""
echo "2. Build and run the project (⌘R)"
echo ""
echo "3. Grant Screen Recording permission when prompted"
echo ""
echo "🌟 Happy coding!"
