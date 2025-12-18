#!/bin/bash

# Animus Audio Visualizer - Cross-Platform Build Script
#
# This script helps prepare builds for all platforms.
# Processing 4 handles the actual compilation and bundling.
#
# Usage:
#   ./build.sh [command] [options]
#
# Commands:
#   install - Install prerequisites for current OS
#   macos   - Build for macOS (calls build-macos.sh for signing)
#   windows - Build for Windows
#   linux   - Build for Linux
#   all     - Build for all platforms
#
# Options:
#   --help  - Show this help

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

APP_NAME="Animus"
VERSION="2.0.0"

# Processing library paths by OS
case "$(uname -s)" in
    Darwin)  PROCESSING_LIBS="$HOME/Documents/Processing/libraries" ;;
    Linux)   PROCESSING_LIBS="$HOME/sketchbook/libraries" ;;
    MINGW*|CYGWIN*|MSYS*) PROCESSING_LIBS="$HOME/Documents/Processing/libraries" ;;
esac

print_header() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo "  $1"
    echo -e "==========================================${NC}"
    echo ""
}

# Install prerequisites based on OS
install_deps() {
    print_header "Installing Prerequisites"
    
    OS="$(uname -s)"
    echo "Detected OS: $OS"
    echo ""
    
    case "$OS" in
        Darwin)
            install_macos_deps
            ;;
        Linux)
            install_linux_deps
            ;;
        MINGW*|CYGWIN*|MSYS*)
            install_windows_deps
            ;;
        *)
            echo -e "${RED}Unsupported OS: $OS${NC}"
            exit 1
            ;;
    esac
    
    # Install Processing libraries (cross-platform)
    install_processing_libs
    
    echo ""
    echo -e "${GREEN}All prerequisites installed!${NC}"
}

install_macos_deps() {
    echo -e "${BLUE}Installing macOS dependencies...${NC}"
    
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
}

install_linux_deps() {
    echo -e "${BLUE}Installing Linux dependencies...${NC}"
    
    # Detect package manager
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
    else
        echo -e "${YELLOW}Unknown package manager. Please install Processing manually.${NC}"
        return
    fi
    
    # Install Java if needed
    if ! command -v java &> /dev/null; then
        echo -e "${YELLOW}Installing Java...${NC}"
        case "$PKG_MANAGER" in
            apt)    sudo apt-get update && sudo apt-get install -y default-jdk ;;
            dnf)    sudo dnf install -y java-latest-openjdk ;;
            pacman) sudo pacman -S --noconfirm jdk-openjdk ;;
        esac
    else
        echo -e "${GREEN}✓ Java${NC}"
    fi
    
    # Check for Processing
    if ! command -v processing-java &> /dev/null && [ ! -d "$HOME/processing-4"* ]; then
        echo -e "${YELLOW}Processing not found.${NC}"
        echo "Please download from: https://processing.org/download"
        echo "Extract to ~/processing-4.x.x and add to PATH"
    else
        echo -e "${GREEN}✓ Processing${NC}"
    fi
}

install_windows_deps() {
    echo -e "${BLUE}Installing Windows dependencies...${NC}"
    
    # Check for Chocolatey or Scoop
    if command -v choco &> /dev/null; then
        if ! command -v processing-java &> /dev/null; then
            echo -e "${YELLOW}Installing Processing via Chocolatey...${NC}"
            choco install processing -y
        else
            echo -e "${GREEN}✓ Processing${NC}"
        fi
    elif command -v scoop &> /dev/null; then
        if ! command -v processing-java &> /dev/null; then
            echo -e "${YELLOW}Installing Processing via Scoop...${NC}"
            scoop bucket add extras
            scoop install processing
        else
            echo -e "${GREEN}✓ Processing${NC}"
        fi
    else
        echo -e "${YELLOW}Please install Processing manually:${NC}"
        echo "  https://processing.org/download"
        echo ""
        echo "Or install Chocolatey/Scoop for automatic installation:"
        echo "  Chocolatey: https://chocolatey.org/install"
        echo "  Scoop: https://scoop.sh"
    fi
}

install_processing_libs() {
    echo ""
    echo -e "${BLUE}Installing Processing libraries...${NC}"
    
    mkdir -p "$PROCESSING_LIBS"
    
    # Install Minim (official URL from Processing contribution manager)
    if [ ! -d "$PROCESSING_LIBS/minim" ]; then
        echo -e "${YELLOW}Installing Minim...${NC}"
        install_lib "minim" "http://code.compartmental.net/minim/distro/minim_for_processing.zip"
    else
        echo -e "${GREEN}✓ Minim${NC}"
    fi
    
    # Install ControlP5 (official URL from Processing contribution manager)
    if [ ! -d "$PROCESSING_LIBS/controlP5" ]; then
        echo -e "${YELLOW}Installing ControlP5...${NC}"
        install_lib "controlP5" "http://www.sojamo.de/libraries/controlP5/controlP5.zip"
    else
        echo -e "${GREEN}✓ ControlP5${NC}"
    fi
}

# Helper to download and install a library with fallbacks
install_lib() {
    local name=$1
    local url=$2
    local tmp="/tmp/${name}.zip"
    
    # Try download
    if curl -fsSL -o "$tmp" "$url" 2>/dev/null && unzip -t "$tmp" &>/dev/null; then
        unzip -q "$tmp" -d "$PROCESSING_LIBS/"
        rm -f "$tmp"
        echo -e "${GREEN}  ✓ $name installed${NC}"
    else
        rm -f "$tmp"
        echo -e "${RED}  Failed to download $name${NC}"
        echo -e "${YELLOW}  Install manually: Processing → Sketch → Import Library → Manage Libraries → '$name'${NC}"
    fi
}

check_processing() {
    # Check for Processing installation
    if command -v processing-java &> /dev/null; then
        echo -e "${GREEN}Found processing-java CLI${NC}"
        return 0
    fi
    
    # Check common installation paths
    PROCESSING_PATHS=(
        "/Applications/Processing.app/Contents/MacOS/processing-java"
        "$HOME/Applications/Processing.app/Contents/MacOS/processing-java"
        "/usr/local/bin/processing-java"
        "$HOME/processing-4.3/processing-java"
    )
    
    for path in "${PROCESSING_PATHS[@]}"; do
        if [ -x "$path" ]; then
            echo -e "${GREEN}Found Processing at: $path${NC}"
            PROCESSING_JAVA="$path"
            return 0
        fi
    done
    
    echo -e "${YELLOW}processing-java CLI not found${NC}"
    echo "Run: ./build.sh install"
    echo ""
    return 1
}

build_platform() {
    local platform=$1
    local output_dir="build/$platform"
    
    print_header "Building for $platform"
    
    # Create output directory
    mkdir -p "$output_dir"
    
    if [ -n "$PROCESSING_JAVA" ] || command -v processing-java &> /dev/null; then
        # Use CLI if available
        local cli="${PROCESSING_JAVA:-processing-java}"
        
        echo "Exporting with processing-java CLI..."
        "$cli" --sketch="$(pwd)" --output="$output_dir" --platform="$platform" --export
        
        echo -e "${GREEN}Export complete: $output_dir${NC}"
    else
        echo -e "${YELLOW}Manual export required:${NC}"
        echo "1. Open Animus.pde in Processing 4"
        echo "2. File → Export Application"
        echo "3. Select '$platform' platform"
        echo "4. Check 'Embed Java' if available"
        echo "5. Export to: $(pwd)/$output_dir"
        echo ""
        read -p "Press Enter when export is complete..."
    fi
}

case "${1:-help}" in
    install)
        install_deps
        ;;
    
    macos)
        print_header "macOS Build"
        if [ -f "build-macos.sh" ]; then
            chmod +x build-macos.sh
            ./build-macos.sh "${@:2}"
        else
            build_platform "macosx"
        fi
        ;;
    
    windows)
        build_platform "windows"
        
        # Create Windows distribution info
        cat > "build/windows/README.txt" << EOF
Animus Audio Visualizer v$VERSION

INSTALLATION:
1. Extract this folder to your preferred location
2. Run Animus.exe

REQUIREMENTS:
- Windows 10 or later
- Java is bundled (no separate installation needed)

For system audio visualization:
- Use a virtual audio cable like VB-Audio or Voicemeeter
- Route your audio app's output through the virtual cable
- Select the virtual cable as input in Animus

https://github.com/yourusername/animus-visualizer
EOF
        echo -e "${GREEN}Windows build prepared${NC}"
        ;;
    
    linux)
        build_platform "linux"
        
        # Create Linux distribution info
        cat > "build/linux/README.txt" << EOF
Animus Audio Visualizer v$VERSION

INSTALLATION:
1. Extract this folder to your preferred location
2. Make the executable runnable: chmod +x Animus
3. Run: ./Animus

REQUIREMENTS:
- Linux (Ubuntu 18.04+, Fedora 30+, or similar)
- Java is bundled (no separate installation needed)
- PulseAudio or ALSA for audio

For system audio visualization:
- Use PulseAudio's monitor devices
- Or use PipeWire with virtual sinks

https://github.com/yourusername/animus-visualizer
EOF
        echo -e "${GREEN}Linux build prepared${NC}"
        ;;
    
    all)
        print_header "Building All Platforms"
        check_processing || true
        
        echo "This will build for macOS, Windows, and Linux"
        echo ""
        
        $0 macos
        $0 windows  
        $0 linux
        
        print_header "All Builds Complete!"
        echo "Output directories:"
        echo "  - macOS:   build/macos/"
        echo "  - Windows: build/windows/"
        echo "  - Linux:   build/linux/"
        ;;
    
    help|--help|-h)
        echo "Animus Audio Visualizer - Build Script"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  install   Install prerequisites (Processing, Minim, ControlP5)"
        echo "  macos     Build for macOS (with signing/notarization)"
        echo "  windows   Build for Windows"
        echo "  linux     Build for Linux"
        echo "  all       Build for all platforms"
        echo "  help      Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 install              # Install dependencies"
        echo "  $0 macos                # Build signed macOS app"
        echo "  $0 macos --skip-notarize  # Build without notarization"
        echo "  $0 all                  # Build for all platforms"
        exit 0
        ;;
    
    *)
        echo "Unknown command: $1"
        echo "Run '$0 help' for usage"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Done!${NC}"
