#!/bin/bash

# Animus Release Script
# Builds app, creates tag, pushes, and uploads to GitHub Release
#
# Usage: ./release.sh [version]
#   If no version provided, auto-detects and suggests next version
#
# Requires: 
#   - gh CLI (brew install gh)
#   - processing-java CLI (install from Processing: Tools > Install "processing-java")
#   - Java 17 (brew install --cask temurin@17)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to get latest version tag
get_latest_version() {
    git fetch --tags 2>/dev/null
    git tag -l 'v*' | sort -V | tail -1
}

# Function to increment version
increment_version() {
    local version=$1
    local part=${2:-patch}  # major, minor, or patch (default)
    
    # Remove 'v' prefix
    version="${version#v}"
    
    IFS='.' read -r major minor patch <<< "$version"
    
    case $part in
        major) ((major++)); minor=0; patch=0 ;;
        minor) ((minor++)); patch=0 ;;
        patch) ((patch++)) ;;
    esac
    
    echo "v${major}.${minor}.${patch}"
}

VERSION="$1"

# Auto-detect version if not provided
if [ -z "$VERSION" ]; then
    LATEST=$(get_latest_version)
    
    if [ -z "$LATEST" ]; then
        SUGGESTED="v1.0.0"
    else
        SUGGESTED=$(increment_version "$LATEST" patch)
    fi
    
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Animus Release Tool${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""
    echo -e "Current version: ${CYAN}${LATEST:-none}${NC}"
    echo -e "Suggested next:  ${GREEN}${SUGGESTED}${NC}"
    echo ""
    echo -e "Version options:"
    echo -e "  ${CYAN}1${NC}) Patch release: $(increment_version "$LATEST" patch)"
    echo -e "  ${CYAN}2${NC}) Minor release: $(increment_version "$LATEST" minor)"
    echo -e "  ${CYAN}3${NC}) Major release: $(increment_version "$LATEST" major)"
    echo -e "  ${CYAN}4${NC}) Custom version"
    echo ""
    read -p "Select option [1-4] or press Enter for patch: " choice
    
    case $choice in
        1|"") VERSION=$(increment_version "$LATEST" patch) ;;
        2) VERSION=$(increment_version "$LATEST" minor) ;;
        3) VERSION=$(increment_version "$LATEST" major) ;;
        4) 
            read -p "Enter version (e.g., v2.1.0): " VERSION
            ;;
        *) 
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac
fi

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo -e "${RED}Version must start with 'v' and be semver (e.g., v2.1.0)${NC}"
    exit 1
fi

# Confirm
echo ""
echo -e "Will release: ${GREEN}${VERSION}${NC}"
read -p "Continue? [Y/n] " confirm
if [[ "$confirm" =~ ^[Nn] ]]; then
    echo "Aborted."
    exit 0
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

# Check for processing-java CLI
if ! command -v processing-java &> /dev/null; then
    echo -e "${RED}processing-java CLI not found.${NC}"
    echo "Install from Processing IDE: Tools > Install \"processing-java\""
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/dist"
TEMP_SKETCH="/tmp/Animus"

echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}  Animus Release: ${VERSION}${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

# Create dist directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 1: Prepare sketch (folder name must match main .pde file)
echo -e "${YELLOW}Step 1: Preparing sketch for export${NC}"
rm -rf "$TEMP_SKETCH"
mkdir -p "$TEMP_SKETCH"
cp "$SCRIPT_DIR"/*.pde "$TEMP_SKETCH/"
cp -r "$SCRIPT_DIR/data" "$TEMP_SKETCH/"
echo -e "${GREEN}✓ Sketch prepared${NC}"

# Step 2: Export macOS app using CLI
echo ""
echo -e "${YELLOW}Step 2: Exporting macOS application${NC}"
EXPORT_DIR="/tmp/Animus-export"
rm -rf "$EXPORT_DIR"

# Export without embedded Java (CLI bug workaround)
# Users will need Java installed to run
processing-java --sketch="$TEMP_SKETCH" --output="$EXPORT_DIR" --no-java --export

if [ ! -d "$EXPORT_DIR/Animus.app" ]; then
    echo -e "${RED}Export failed - Animus.app not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Application exported${NC}"

# Step 3: Sign the app (optional)
echo ""
echo -e "${YELLOW}Step 3: Code signing (optional)${NC}"

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

# Step 4: Create archives
echo ""
echo -e "${YELLOW}Step 4: Creating release archives${NC}"

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
    release.sh \
    -x "*.DS_Store"
echo -e "${GREEN}✓ Animus-${VERSION}-source.zip${NC}"

# Step 5: Git tag
echo ""
echo -e "${YELLOW}Step 5: Creating git tag${NC}"

git add -A
git commit -m "Release ${VERSION}" --allow-empty
git tag -a "$VERSION" -m "Release ${VERSION}"
git push origin master
git push origin "$VERSION"

echo -e "${GREEN}✓ Tag ${VERSION} pushed${NC}"

# Step 6: Create GitHub release
echo ""
echo -e "${YELLOW}Step 6: Creating GitHub release${NC}"

# Generate release notes
NOTES="## Animus Audio Visualizer ${VERSION}

### Downloads
- **macOS App**: Download \`Animus-${VERSION}-macos.zip\`, extract, and run
- **Source**: Download source and open in Processing 4

### Requirements
- macOS 10.14+ (for macOS app)
- Java 17+ runtime (install via \`brew install --cask temurin@17\`)
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
