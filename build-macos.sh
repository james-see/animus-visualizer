#!/bin/bash

# Animus Audio Visualizer - macOS Build, Sign, and Notarization Script
# 
# Setup:
#   cp env.example .env
#   # Edit .env with your credentials
#   ./build-macos.sh
#
# Usage:
#   ./build-macos.sh [--skip-notarize] [--install-deps]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# App configuration
APP_NAME="Animus"
BUNDLE_ID="com.animus.visualizer"
VERSION="2.0.0"

# Processing library paths
PROCESSING_LIBS="$HOME/Documents/Processing/libraries"

# Load environment variables from .env if exists
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
    echo -e "${GREEN}Loaded configuration from .env${NC}"
else
    echo -e "${YELLOW}No .env file found. Copy env.example to .env:${NC}"
    echo "  cp env.example .env"
    echo ""
fi

# Function to install prerequisites
install_prerequisites() {
    echo -e "${BLUE}Installing prerequisites for macOS...${NC}"
    echo ""
    
    # Check for Homebrew
    if ! command -v brew &> /dev/null; then
        echo -e "${YELLOW}Installing Homebrew...${NC}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        echo -e "${GREEN}✓ Homebrew${NC}"
    fi
    
    # Install Processing
    if [ ! -d "/Applications/Processing.app" ] && [ ! -d "$HOME/Applications/Processing.app" ]; then
        echo -e "${YELLOW}Installing Processing 4...${NC}"
        brew install --cask processing
    else
        echo -e "${GREEN}✓ Processing${NC}"
    fi
    
    # Create libraries directory if needed
    mkdir -p "$PROCESSING_LIBS"
    
    # Install Minim library (official URL from Processing contribution manager)
    if [ ! -d "$PROCESSING_LIBS/minim" ]; then
        echo -e "${YELLOW}Installing Minim library...${NC}"
        install_processing_library "minim" "http://code.compartmental.net/minim/distro/minim_for_processing.zip"
    else
        echo -e "${GREEN}✓ Minim${NC}"
    fi
    
    # Install ControlP5 library (official URL from Processing contribution manager)
    if [ ! -d "$PROCESSING_LIBS/controlP5" ]; then
        echo -e "${YELLOW}Installing ControlP5 library...${NC}"
        install_processing_library "controlP5" "http://www.sojamo.de/libraries/controlP5/controlP5.zip"
    else
        echo -e "${GREEN}✓ ControlP5${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}All prerequisites installed!${NC}"
    echo ""
}

# Helper function to download and install a Processing library
install_processing_library() {
    local lib_name=$1
    local url=$2
    local temp_dir=$(mktemp -d)
    local zip_file="$temp_dir/$lib_name.zip"
    
    # Try primary URL first, then fallback to GitHub
    if ! curl -fsSL -o "$zip_file" "$url" 2>/dev/null; then
        echo -e "${YELLOW}  Primary URL failed, trying alternative...${NC}"
        # Fallback URLs
        case "$lib_name" in
            minim)
                url="https://github.com/ddf/Minim/releases/latest/download/minim.zip"
                ;;
            controlP5)
                url="https://github.com/sojamo/controlp5/releases/latest/download/controlP5.zip"
                ;;
        esac
        
        if ! curl -fsSL -o "$zip_file" "$url" 2>/dev/null; then
            echo -e "${RED}  Failed to download $lib_name${NC}"
            echo -e "${YELLOW}  Please install manually: Processing → Sketch → Import Library → Manage Libraries → Search '$lib_name'${NC}"
            rm -rf "$temp_dir"
            return 1
        fi
    fi
    
    # Verify it's a valid zip
    if ! unzip -t "$zip_file" &>/dev/null; then
        echo -e "${RED}  Downloaded file is not a valid zip${NC}"
        echo -e "${YELLOW}  Please install manually: Processing → Sketch → Import Library → Manage Libraries → Search '$lib_name'${NC}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Extract to Processing libraries folder
    unzip -q "$zip_file" -d "$PROCESSING_LIBS/"
    rm -rf "$temp_dir"
    
    echo -e "${GREEN}  ✓ $lib_name installed${NC}"
}

# Check for required environment variables
check_env() {
    local var_name=$1
    local var_value="${!var_name}"
    if [ -z "$var_value" ]; then
        echo -e "${RED}Error: $var_name is not set${NC}"
        echo "Please set $var_name environment variable or add it to .env file"
        return 1
    fi
    return 0
}

# Parse arguments
SKIP_NOTARIZE=false
INSTALL_DEPS=false
for arg in "$@"; do
    case $arg in
        --skip-notarize)
            SKIP_NOTARIZE=true
            ;;
        --install-deps)
            INSTALL_DEPS=true
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --install-deps    Install prerequisites (Processing, Minim, ControlP5)"
            echo "  --skip-notarize   Skip Apple notarization step"
            echo "  --help, -h        Show this help message"
            exit 0
            ;;
    esac
done

# Install prerequisites if requested
if [ "$INSTALL_DEPS" = true ]; then
    install_prerequisites
fi

echo "=========================================="
echo "  Animus Audio Visualizer - macOS Build"
echo "=========================================="
echo ""

# Step 1: Create build directory
BUILD_DIR="build/macos"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo -e "${YELLOW}Step 1: Exporting from Processing...${NC}"
echo "Please export the application from Processing IDE:"
echo "  1. Open Animus.pde in Processing 4"
echo "  2. File → Export Application"
echo "  3. Select 'macOS' platform"
echo "  4. Check 'Embed Java for macOS'"
echo "  5. Export to: $(pwd)/$BUILD_DIR"
echo ""
read -p "Press Enter when export is complete..."

# Check if .app exists
APP_PATH="$BUILD_DIR/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    # Try alternate location
    APP_PATH="$BUILD_DIR/application.macosx/$APP_NAME.app"
fi

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: $APP_NAME.app not found in $BUILD_DIR${NC}"
    echo "Please export the application first"
    exit 1
fi

echo -e "${GREEN}Found: $APP_PATH${NC}"

# Step 2: Update Info.plist
echo -e "${YELLOW}Step 2: Updating Info.plist...${NC}"

PLIST_PATH="$APP_PATH/Contents/Info.plist"

# Add/update required keys for notarization
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST_PATH" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$PLIST_PATH"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST_PATH" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$PLIST_PATH"

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST_PATH" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $VERSION" "$PLIST_PATH"

/usr/libexec/PlistBuddy -c "Set :NSMicrophoneUsageDescription 'Animus needs microphone access to visualize audio'" "$PLIST_PATH" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string 'Animus needs microphone access to visualize audio'" "$PLIST_PATH"

/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 10.14" "$PLIST_PATH" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 10.14" "$PLIST_PATH"

echo -e "${GREEN}Info.plist updated${NC}"

# Step 3: Create entitlements file
echo -e "${YELLOW}Step 3: Creating entitlements...${NC}"

ENTITLEMENTS_PATH="$BUILD_DIR/entitlements.plist"
cat > "$ENTITLEMENTS_PATH" << EOF
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
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
EOF

echo -e "${GREEN}Entitlements created${NC}"

# Step 4: Code Signing
echo -e "${YELLOW}Step 4: Code signing...${NC}"

if ! check_env "DEVELOPER_ID"; then
    echo -e "${YELLOW}Skipping code signing (DEVELOPER_ID not set)${NC}"
    echo "To enable signing, set DEVELOPER_ID to your certificate name"
    echo "Example: export DEVELOPER_ID=\"Developer ID Application: Your Name (TEAMID)\""
else
    echo "Signing with: $DEVELOPER_ID"
    
    # Sign all embedded frameworks and dylibs first
    find "$APP_PATH/Contents" -type f \( -name "*.dylib" -o -name "*.jnilib" -o -name "*.framework" \) -print0 | while IFS= read -r -d '' file; do
        echo "  Signing: $file"
        codesign --force --verify --verbose --sign "$DEVELOPER_ID" \
            --options runtime \
            --entitlements "$ENTITLEMENTS_PATH" \
            "$file" 2>/dev/null || true
    done
    
    # Sign Java runtime if embedded
    if [ -d "$APP_PATH/Contents/PlugIns/jdk" ]; then
        echo "  Signing embedded JDK..."
        codesign --force --verify --verbose --sign "$DEVELOPER_ID" \
            --options runtime \
            --entitlements "$ENTITLEMENTS_PATH" \
            --deep \
            "$APP_PATH/Contents/PlugIns/jdk"
    fi
    
    # Sign the main app bundle
    echo "  Signing main app bundle..."
    codesign --force --verify --verbose --sign "$DEVELOPER_ID" \
        --options runtime \
        --entitlements "$ENTITLEMENTS_PATH" \
        --deep \
        "$APP_PATH"
    
    # Verify signature
    echo "  Verifying signature..."
    codesign --verify --verbose=2 "$APP_PATH"
    
    echo -e "${GREEN}Code signing complete${NC}"
fi

# Step 5: Notarization
if [ "$SKIP_NOTARIZE" = true ]; then
    echo -e "${YELLOW}Step 5: Skipping notarization (--skip-notarize flag)${NC}"
else
    echo -e "${YELLOW}Step 5: Notarization...${NC}"
    
    if ! check_env "DEVELOPER_ID" || ! check_env "APPLE_ID" || ! check_env "TEAM_ID" || ! check_env "APP_PASSWORD"; then
        echo -e "${YELLOW}Skipping notarization (missing credentials)${NC}"
        echo "Required environment variables: APPLE_ID, TEAM_ID, APP_PASSWORD"
    else
        # Create ZIP for notarization
        ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
        echo "  Creating ZIP archive..."
        ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
        
        # Submit for notarization
        echo "  Submitting to Apple for notarization..."
        echo "  This may take several minutes..."
        
        xcrun notarytool submit "$ZIP_PATH" \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID" \
            --password "$APP_PASSWORD" \
            --wait
        
        # Staple the notarization ticket
        echo "  Stapling notarization ticket..."
        xcrun stapler staple "$APP_PATH"
        
        # Verify stapling
        xcrun stapler validate "$APP_PATH"
        
        echo -e "${GREEN}Notarization complete${NC}"
        
        # Clean up ZIP
        rm "$ZIP_PATH"
    fi
fi

# Step 6: Create DMG for distribution
echo -e "${YELLOW}Step 6: Creating DMG...${NC}"

DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
DMG_TEMP="$BUILD_DIR/dmg_temp"

mkdir -p "$DMG_TEMP"
cp -R "$APP_PATH" "$DMG_TEMP/"

# Create symlink to Applications
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG
hdiutil create -volname "$APP_NAME $VERSION" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH"

# Clean up temp directory
rm -rf "$DMG_TEMP"

# Sign DMG if certificate available
if [ -n "$DEVELOPER_ID" ]; then
    echo "  Signing DMG..."
    codesign --force --sign "$DEVELOPER_ID" "$DMG_PATH"
fi

echo -e "${GREEN}DMG created: $DMG_PATH${NC}"

# Summary
echo ""
echo "=========================================="
echo "  Build Complete!"
echo "=========================================="
echo ""
echo "Output files:"
echo "  - App: $APP_PATH"
echo "  - DMG: $DMG_PATH"
echo ""
if [ -z "$DEVELOPER_ID" ]; then
    echo -e "${YELLOW}Note: App is NOT signed or notarized${NC}"
    echo "To enable signing, set these environment variables:"
    echo "  export DEVELOPER_ID=\"Developer ID Application: Your Name (TEAMID)\""
    echo "  export APPLE_ID=\"your@email.com\""
    echo "  export TEAM_ID=\"YOURTEAMID\""
    echo "  export APP_PASSWORD=\"xxxx-xxxx-xxxx-xxxx\""
fi
