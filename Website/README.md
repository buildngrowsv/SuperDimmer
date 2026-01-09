# SuperDimmer Website

Marketing website for SuperDimmer - the intelligent screen dimming app for macOS.

## Overview

SuperDimmer is a macOS menu bar app that automatically detects and dims bright areas on your screen. This repository contains the marketing website for the product.

## Features Highlighted

- **Intelligent Detection** - Automatically finds bright areas using luminance analysis
- **Per-Region Dimming** - Dims specific bright areas within windows (unique feature)
- **Color Temperature** - f.lux-style blue light filter
- **Multi-Display Support** - Works across all connected displays
- **Active/Inactive Rules** - Different dim levels for foreground vs background windows

## Technology

The website is built as a single HTML file with:
- Pure CSS (no frameworks)
- Vanilla JavaScript for scroll animations
- Custom warm amber theme (appropriate for an eye-comfort app)
- Responsive design for all screen sizes
- Playfair Display + DM Sans typography

## Running Locally

Simply open `index.html` in a web browser:

```bash
open index.html
```

Or use any local server:

```bash
# Python 3
python3 -m http.server 8000

# Node.js (npx)
npx serve .
```

## Deployment

The site is designed for static hosting and works on:
- GitHub Pages
- Netlify
- Vercel
- Any static host

## Design Philosophy

The website uses a dark theme with warm amber accents, reflecting:
- The app's purpose (reducing eye strain)
- Night/evening usage patterns
- Premium, professional feel
- High contrast for accessibility

## Structure

```
SuperDimmer-Website/
├── index.html      # Complete website (HTML + CSS + JS)
└── README.md       # This file
```

## License

© 2026 SuperDimmer. All rights reserved.
