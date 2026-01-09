#!/bin/bash

# ============================================================================
# SuperDimmer DMG Background Generator
# ============================================================================
# Creates a beautiful background image for the DMG installer window.
# Uses SVG converted to PNG for crisp rendering at any resolution.
#
# WHY: A custom DMG background provides visual polish and guides users
# to drag the app to the Applications folder. This matches the dark/warm
# aesthetic of SuperDimmer's branding.
#
# USAGE:
#   ./create-background.sh
#
# OUTPUT:
#   Creates background.png (660x400) in the packaging folder
#
# REQUIREMENTS:
#   - macOS with built-in tools (qlmanage for PNG conversion)
#   - Or: ImageMagick (brew install imagemagick) for higher quality
#
# Created: January 8, 2026
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="$SCRIPT_DIR/background.png"
SVG_FILE="$SCRIPT_DIR/background.svg"

# Create the SVG background
# Using warm amber/orange tones to match SuperDimmer branding
# Dark background that feels modern and matches dark mode aesthetic
cat > "$SVG_FILE" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="660" height="400" viewBox="0 0 660 400">
  <defs>
    <!-- Main gradient - dark with subtle warm tones -->
    <linearGradient id="bgGradient" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#1a1512;stop-opacity:1" />
      <stop offset="50%" style="stop-color:#0f0d0b;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#1a1512;stop-opacity:1" />
    </linearGradient>
    
    <!-- Radial glow behind the app icon area -->
    <radialGradient id="appGlow" cx="27%" cy="50%" r="35%">
      <stop offset="0%" style="stop-color:#d4a855;stop-opacity:0.08" />
      <stop offset="100%" style="stop-color:#d4a855;stop-opacity:0" />
    </radialGradient>
    
    <!-- Subtle pattern overlay -->
    <pattern id="grain" x="0" y="0" width="100" height="100" patternUnits="userSpaceOnUse">
      <rect width="100" height="100" fill="url(#bgGradient)"/>
      <circle cx="50" cy="50" r="1" fill="#d4a855" opacity="0.02"/>
    </pattern>
  </defs>
  
  <!-- Background -->
  <rect width="660" height="400" fill="url(#bgGradient)"/>
  
  <!-- Subtle glow behind app icon -->
  <rect width="660" height="400" fill="url(#appGlow)"/>
  
  <!-- Decorative border line at top -->
  <rect x="0" y="0" width="660" height="1" fill="#d4a855" opacity="0.3"/>
  
  <!-- Arrow from app to Applications -->
  <g transform="translate(280, 175)" opacity="0.4">
    <!-- Arrow line -->
    <line x1="0" y1="0" x2="100" y2="0" stroke="#d4a855" stroke-width="2" stroke-linecap="round" stroke-dasharray="8,4"/>
    <!-- Arrow head -->
    <polygon points="100,0 88,-8 88,8" fill="#d4a855"/>
  </g>
  
  <!-- "Drag to install" text -->
  <text x="330" y="290" text-anchor="middle" font-family="-apple-system, BlinkMacSystemFont, 'Helvetica Neue'" font-size="14" fill="#d4a855" opacity="0.6">
    Drag to Applications to install
  </text>
  
  <!-- SuperDimmer branding text at bottom -->
  <text x="330" y="375" text-anchor="middle" font-family="'Cormorant Garamond', Georgia, serif" font-size="16" fill="#d4a855" opacity="0.4" letter-spacing="3">
    SUPERDIMMER
  </text>
  
  <!-- Subtle corner accents -->
  <path d="M 0,0 L 40,0 L 0,40 Z" fill="#d4a855" opacity="0.05"/>
  <path d="M 660,400 L 620,400 L 660,360 Z" fill="#d4a855" opacity="0.05"/>
</svg>
EOF

echo "Created SVG: $SVG_FILE"

# Convert SVG to PNG
# Try different methods in order of quality

if command -v convert &> /dev/null; then
    # Best quality: ImageMagick
    echo "Converting with ImageMagick..."
    convert -background none -density 144 "$SVG_FILE" -resize 660x400 "$OUTPUT_FILE"
elif command -v rsvg-convert &> /dev/null; then
    # Good quality: librsvg
    echo "Converting with rsvg-convert..."
    rsvg-convert -w 660 -h 400 "$SVG_FILE" -o "$OUTPUT_FILE"
else
    # Fallback: Use macOS built-in (lower quality but works)
    echo "Converting with qlmanage (fallback)..."
    # Create a temporary HTML file that embeds the SVG for better rendering
    cat > "$SCRIPT_DIR/temp_bg.html" << HTMLEOF
<!DOCTYPE html>
<html>
<head><style>
body { margin: 0; padding: 0; background: #0f0d0b; }
img { width: 660px; height: 400px; }
</style></head>
<body>
<img src="background.svg">
</body>
</html>
HTMLEOF
    
    # Actually for SVG, let's just keep the SVG and note that create-dmg handles it
    echo ""
    echo "Note: For best results, install ImageMagick:"
    echo "  brew install imagemagick"
    echo ""
    echo "Or use the SVG directly if your create-dmg tool supports it."
    rm -f "$SCRIPT_DIR/temp_bg.html"
    
    # Create a simple PNG fallback using sips and a solid color
    # This is a placeholder - the SVG is the actual design
    sips -z 400 660 -s format png /System/Library/Desktop\ Pictures/*.heic 2>/dev/null | head -1 || true
fi

# Clean up SVG if PNG was created successfully
if [ -f "$OUTPUT_FILE" ]; then
    echo ""
    echo "✅ Created: $OUTPUT_FILE"
    echo "   Size: $(du -h "$OUTPUT_FILE" | cut -f1)"
    rm -f "$SVG_FILE"
else
    echo ""
    echo "⚠️  PNG conversion not available, keeping SVG file."
    echo "   You may need to convert it manually or install ImageMagick."
    mv "$SVG_FILE" "${SVG_FILE%.svg}.svg"
fi
