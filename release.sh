#!/bin/bash

# Animus Release Script
# Builds app, creates tag, pushes, and uploads to GitHub Release
#
# Usage: ./release.sh v2.1.0
#
# Requires: gh CLI (brew install gh)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VERSION="$1"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 v2.1.0"
    exit 1
fi

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo -e "${RED}Version must start with 'v' and be semver (e.g., v2.1.0)${NC}"
    exit 1
fi

# Check for gh CLI
if ! command -v gh &> /dev/null; then
    echo -e "${RED}GitHub CLI (gh) not found. Install with: brew install gh${NC}"
    exit 1
fi

# Check gh auth
if ! gh auth status &> /dev/null; then
    echo -e "${RED}Not logged into GitHub CLI. Run: gh auth login${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/dist"

echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}  Animus Release: ${VERSION}${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

# Create dist directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 1: Export from Processing
echo -e "${YELLOW}Step 1: Export macOS app from Processing${NC}"
echo ""
echo "Opening Processing... Please:"
echo "  1. File → Export Application"
echo "  2. Select macOS, check 'Embed Java for macOS'"
echo "  3. Click Export"
echo ""

open -a Processing "$SCRIPT_DIR/Animus.pde"

read -p "Press Enter when export is complete..."

# Find exported app
EXPORT_DIR="$SCRIPT_DIR/application.macosx"
if [ ! -d "$EXPORT_DIR/Animus.app" ]; then
    echo -e "${RED}Export not found at $EXPORT_DIR/Animus.app${NC}"
    echo "Make sure you exported for macOS"
    exit 1
fi

echo -e "${GREEN}✓ Found exported app${NC}"

# Step 2: Sign the app (optional)
echo ""
echo -e "${YELLOW}Step 2: Code signing (optional)${NC}"

if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

if [ -n "$DEVELOPER_ID" ]; then
    echo "Signing with: $DEVELOPER_ID"
    
    # Create entitlements
    cat > /tmp/entitlements.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
EOF
    
    codesign --deep --force --verify --verbose \
        --sign "$DEVELOPER_ID" \
        --options runtime \
        --entitlements /tmp/entitlements.plist \
        "$EXPORT_DIR/Animus.app" || echo "Signing failed, continuing unsigned"
    
    echo -e "${GREEN}✓ App signed${NC}"
else
    echo "No DEVELOPER_ID in .env, skipping signing"
fi

# Step 3: Create archives
echo ""
echo -e "${YELLOW}Step 3: Creating release archives${NC}"

# macOS app zip
cd "$EXPORT_DIR"
zip -r "$BUILD_DIR/Animus-${VERSION}-macos.zip" Animus.app
echo -e "${GREEN}✓ Animus-${VERSION}-macos.zip${NC}"

# Source zip
cd "$SCRIPT_DIR"
zip -r "$BUILD_DIR/Animus-${VERSION}-source.zip" \
    *.pde \
    data/ \
    README.md \
    build.sh \
    build-macos.sh \
    env.example \
    sketch.properties \
    -x "*.DS_Store"
echo -e "${GREEN}✓ Animus-${VERSION}-source.zip${NC}"

# Step 4: Git tag
echo ""
echo -e "${YELLOW}Step 4: Creating git tag${NC}"

git add -A
git commit -m "Release ${VERSION}" --allow-empty
git tag -a "$VERSION" -m "Release ${VERSION}"
git push origin master
git push origin "$VERSION"

echo -e "${GREEN}✓ Tag ${VERSION} pushed${NC}"

# Step 5: Create GitHub release
echo ""
echo -e "${YELLOW}Step 5: Creating GitHub release${NC}"

# Generate release notes
NOTES="## Animus Audio Visualizer ${VERSION}

### Downloads
- **macOS App**: Download \`Animus-${VERSION}-macos.zip\`, extract, and run
- **Source**: Download source and open in Processing 4

### Requirements
- macOS 10.14+ (for macOS app)
- For source: Processing 4.3+, Minim, ControlP5 libraries

### System Audio
To visualize Spotify/Apple Music:
- Use Loopback or SoundSource to create a virtual audio device
- Set it as your system input in System Settings → Sound → Input
"

gh release create "$VERSION" \
    --title "Animus ${VERSION}" \
    --notes "$NOTES" \
    "$BUILD_DIR/Animus-${VERSION}-macos.zip" \
    "$BUILD_DIR/Animus-${VERSION}-source.zip"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Release ${VERSION} complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo "View at: https://github.com/james-see/animus-visualizer/releases/tag/${VERSION}"
