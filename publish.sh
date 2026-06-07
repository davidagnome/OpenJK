#!/usr/bin/env bash
#============================================================================
# publish.sh - Build OpenJK and publish binaries to Publish/{platform}-{arch}/
#
# Usage:
#   ./publish.sh                          # Build for host platform
#   ./publish.sh --clean                  # Clean build
#   ./publish.sh --debug                  # Debug build (default: Release)
#   ./publish.sh --jk2                    # Include JK2 SP targets
#   ./publish.sh --jobs=8                 # Parallel build jobs
#   ./publish.sh --platform=macos         # Override platform detection
#   ./publish.sh --arch=arm64             # Override arch detection
#
# Output:
#   Publish/
#   ├── macOS-x86_64/
#   │   ├── JediAcademy/
#   │   │   ├── openjk.x86_64(.app)      # MP client
#   │   │   ├── openjk_sp.x86_64(.app)   # SP client
#   │   │   ├── openjkded.x86_64         # Dedicated server
#   │   │   ├── base/                     # Game modules
#   │   │   │   ├── jampgame*.dylib
#   │   │   │   ├── cgame*.dylib
#   │   │   │   ├── ui*.dylib
#   │   │   │   ├── jagame*.dylib
#   │   │   │   ├── rd-vanilla_*.dylib
#   │   │   │   ├── rd-rend2_*.dylib
#   │   │   │   └── rdsp-vanilla_*.dylib
#   │   │   └── JediOutcast/
#   │   │       └── base/
#   │   │           └── jospgame*.dylib
#   │   └── README.txt
#   ├── Linux-x86_64/
#   │   └── ...
#   └── Windows-x86_64/
#       └── ...
#============================================================================
set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"
PUBLISH_DIR="$ROOT_DIR/Publish"

#=============================================================================
# Defaults
#=============================================================================
BUILD_TYPE="Release"
CLEAN_BUILD=false
INCLUDE_JK2=true
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
PLATFORM=""
ARCH=""
CMAKE_EXTRA_FLAGS=""

#=============================================================================
# Argument parsing
#=============================================================================
for arg in "$@"; do
    case $arg in
        --clean)
            CLEAN_BUILD=true
            ;;
        --debug)
            BUILD_TYPE="Debug"
            ;;
        --release)
            BUILD_TYPE="Release"
            ;;
        --jk2)
            INCLUDE_JK2=true
            ;;
        --jobs=*)
            JOBS="${arg#*=}"
            ;;
        -j*)
            JOBS="${arg#-j}"
            ;;
        --platform=*)
            PLATFORM="${arg#*=}"
            ;;
        --arch=*)
            ARCH="${arg#*=}"
            ;;
        --portable)
            CMAKE_EXTRA_FLAGS="$CMAKE_EXTRA_FLAGS -DBuildPortableVersion=ON"
            ;;
        --no-rend2)
            CMAKE_EXTRA_FLAGS="$CMAKE_EXTRA_FLAGS -DBuildMPRend2=OFF"
            ;;
        --no-sp)
            CMAKE_EXTRA_FLAGS="$CMAKE_EXTRA_FLAGS -DBuildSPEngine=OFF -DBuildSPGame=OFF -DBuildSPRdVanilla=OFF"
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --clean           Remove build directory before building"
            echo "  --debug           Build Debug configuration (default: Release)"
            echo "  --release         Build Release configuration"
            echo "  --jk2             Include Jedi Outcast SP targets"
            echo "  --jobs=N, -jN     Number of parallel build jobs (default: $JOBS)"
            echo "  --platform=NAME   Target platform: macos, linux, windows"
            echo "  --arch=ARCH       Target architecture: x86_64, arm64, i386"
            echo "  --portable        Build portable version (no user-home writes)"
            echo "  --no-rend2        Exclude experimental rend2 renderer"
            echo "  --no-sp           Exclude single player engine"
            echo "  --help, -h        Show this help"
            echo ""
            echo "Output is placed in Publish/{platform}-{arch}/"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

#=============================================================================
# Platform detection
#=============================================================================
detect_platform() {
    local os
    os="$(uname -s)"
    case "$os" in
        Darwin)  echo "macOS" ;;
        Linux)   echo "Linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "Windows" ;;
        *)
            echo "ERROR: Unsupported platform: $os"
            echo "Use --platform=macos|linux|windows to override."
            exit 1
            ;;
    esac
}

detect_arch() {
    local machine
    machine="$(uname -m)"
    case "$machine" in
        x86_64|amd64)   echo "x86_64" ;;
        i386|i686)      echo "i386" ;;
        arm64|aarch64)  echo "arm64" ;;
        armv7l|arm*)    echo "arm" ;;
        *)
            echo "ERROR: Unknown architecture: $machine"
            echo "Use --arch=ARCH to override."
            exit 1
            ;;
    esac
}

if [ -z "$PLATFORM" ]; then
    PLATFORM="$(detect_platform)"
fi
if [ -z "$ARCH" ]; then
    ARCH="$(detect_arch)"
fi

#=============================================================================
# Derived variables
#=============================================================================
PUBLISH_TARGET="$PUBLISH_DIR/${PLATFORM}-${ARCH}"
BUILD_DIR="$ROOT_DIR/build_publish"
JKA_DIR="$PUBLISH_TARGET/JediAcademy"
JKA_BASE="$JKA_DIR/base"
JK2_DIR="$PUBLISH_TARGET/JediOutcast"
JK2_BASE="$JK2_DIR/base"

# Platform-specific settings
case "$PLATFORM" in
    macOS)
        EXE_EXT=""
        DLL_EXT=".dylib"
        ;;
    Linux)
        CMAKE_EXTRA_FLAGS="$CMAKE_EXTRA_FLAGS -DMakeApplicationBundles=OFF"
        EXE_EXT=""
        DLL_EXT=".so"
        ;;
    Windows)
        EXE_EXT=".exe"
        DLL_EXT=".dll"
        ;;
esac

#=============================================================================
# Print configuration
#=============================================================================
echo "============================================"
echo " OpenJK Publish Script"
echo "============================================"
echo " Platform:      $PLATFORM"
echo " Architecture:  $ARCH"
echo " Build type:    $BUILD_TYPE"
echo " Jobs:          $JOBS"
echo " Include JK2:   $INCLUDE_JK2"
echo " Clean build:   $CLEAN_BUILD"
echo " Output:        $PUBLISH_TARGET"
echo "============================================"
echo ""

#=============================================================================
# Clean
#=============================================================================
if $CLEAN_BUILD; then
    echo "==> Cleaning build directory..."
    rm -rf "$BUILD_DIR"
fi

#=============================================================================
# Configure
#=============================================================================
echo "==> Configuring CMake..."

CMAKE_FLAGS=""
CMAKE_FLAGS="$CMAKE_FLAGS -DCMAKE_BUILD_TYPE=$BUILD_TYPE"
CMAKE_FLAGS="$CMAKE_FLAGS -DBuildMPEngine=ON"
CMAKE_FLAGS="$CMAKE_FLAGS -DBuildMPDed=ON"
CMAKE_FLAGS="$CMAKE_FLAGS -DBuildMPGame=ON"
CMAKE_FLAGS="$CMAKE_FLAGS -DBuildMPCGame=ON"
CMAKE_FLAGS="$CMAKE_FLAGS -DBuildMPUI=ON"
CMAKE_FLAGS="$CMAKE_FLAGS -DBuildMPRdVanilla=ON"
CMAKE_FLAGS="$CMAKE_FLAGS -DBuildMPRend2=ON"
CMAKE_FLAGS="$CMAKE_FLAGS -DBuildSPEngine=ON"
CMAKE_FLAGS="$CMAKE_FLAGS -DBuildSPGame=ON"
CMAKE_FLAGS="$CMAKE_FLAGS -DBuildSPRdVanilla=ON"
CMAKE_FLAGS="$CMAKE_FLAGS $CMAKE_EXTRA_FLAGS"

if $INCLUDE_JK2; then
    CMAKE_FLAGS="$CMAKE_FLAGS -DBuildJK2SPEngine=ON"
    CMAKE_FLAGS="$CMAKE_FLAGS -DBuildJK2SPGame=ON"
    CMAKE_FLAGS="$CMAKE_FLAGS -DBuildJK2SPRdVanilla=ON"
fi

cmake -B "$BUILD_DIR" -S "$ROOT_DIR" $CMAKE_FLAGS

#=============================================================================
# Build
#=============================================================================
echo ""
echo "==> Building..."
cmake --build "$BUILD_DIR" --config "$BUILD_TYPE" --parallel "$JOBS"

#=============================================================================
# Publish
#=============================================================================
echo ""
echo "==> Publishing to $PUBLISH_TARGET..."

rm -rf "$PUBLISH_TARGET"
mkdir -p "$JKA_BASE"

#-----------------------------------------------------------------------------
# Copy MP client
#-----------------------------------------------------------------------------
echo "  - MP client..."
if [ "$PLATFORM" = "macOS" ] && [ -d "$BUILD_DIR/openjk.$ARCH.app" ]; then
    cp -R "$BUILD_DIR/openjk.$ARCH.app" "$JKA_DIR/OpenJK.app"
elif [ -f "$BUILD_DIR/openjk.$ARCH$EXE_EXT" ]; then
    cp "$BUILD_DIR/openjk.$ARCH$EXE_EXT" "$JKA_DIR/openjk"
fi

#-----------------------------------------------------------------------------
# Copy SP client
#-----------------------------------------------------------------------------
echo "  - SP client..."
if [ "$PLATFORM" = "macOS" ] && [ -d "$BUILD_DIR/openjk_sp.$ARCH.app" ]; then
    cp -R "$BUILD_DIR/openjk_sp.$ARCH.app" "$JKA_DIR/OpenJK-SP.app"
elif [ -f "$BUILD_DIR/openjk_sp.$ARCH$EXE_EXT" ]; then
    cp "$BUILD_DIR/openjk_sp.$ARCH$EXE_EXT" "$JKA_DIR/openjk_sp"
fi

#-----------------------------------------------------------------------------
# On macOS with .app bundles, redirect game module/ renderer paths into the apps
#-----------------------------------------------------------------------------
if [ "$PLATFORM" = "macOS" ] && [ -d "$JKA_DIR/OpenJK.app" ]; then
    JKA_DYLIB_DIR="$JKA_DIR/OpenJK.app/Contents/MacOS"
    SP_DYLIB_DIR="$JKA_DIR/OpenJK-SP.app/Contents/MacOS"
    mkdir -p "$JKA_DYLIB_DIR/base" "$SP_DYLIB_DIR/base"
    JKA_BASE="$JKA_DYLIB_DIR/base"
else
    JKA_DYLIB_DIR="$JKA_DIR"
    SP_DYLIB_DIR="$JKA_DIR"
fi

#-----------------------------------------------------------------------------
# Copy dedicated server
#-----------------------------------------------------------------------------
echo "  - Dedicated server..."
if [ -f "$BUILD_DIR/openjkded.$ARCH$EXE_EXT" ]; then
    cp "$BUILD_DIR/openjkded.$ARCH$EXE_EXT" "$JKA_DIR/openjkded"
fi

#-----------------------------------------------------------------------------
# Copy MP game modules to base/
#-----------------------------------------------------------------------------
echo "  - Game modules (base/)..."
for mod in jampgame cgame ui; do
    for f in $(find "$BUILD_DIR" -name "${mod}*$DLL_EXT" -type f); do
        if [ -f "$f" ]; then
            cp "$f" "$JKA_BASE/"
            [ "$PLATFORM" = "macOS" ] && cp "$f" "$JKA_DYLIB_DIR/"
            [ "$PLATFORM" = "macOS" ] && cp "$f" "$SP_DYLIB_DIR/"
        fi
    done
done

#-----------------------------------------------------------------------------
# Copy SP game module to base/
#-----------------------------------------------------------------------------
for f in $(find "$BUILD_DIR" -name "jagame*$DLL_EXT" -type f); do
    if [ -f "$f" ]; then
        cp "$f" "$JKA_BASE/"
        [ "$PLATFORM" = "macOS" ] && cp "$f" "$SP_DYLIB_DIR/"
    fi
done

#-----------------------------------------------------------------------------
# Copy MP renderers to base/
#-----------------------------------------------------------------------------
echo "  - Renderers (base/)..."
for rdr in rd-vanilla rd-rend2; do
    for f in $(find "$BUILD_DIR" -name "${rdr}_*$DLL_EXT" -type f); do
        if [ -f "$f" ]; then
            cp "$f" "$JKA_BASE/"
            [ "$PLATFORM" = "macOS" ] && cp "$f" "$JKA_DYLIB_DIR/"
            [ "$PLATFORM" = "macOS" ] && cp "$f" "$SP_DYLIB_DIR/"
        fi
    done
done

#-----------------------------------------------------------------------------
# Copy SP renderer to base/
#-----------------------------------------------------------------------------
for f in $(find "$BUILD_DIR" -name "rdsp-vanilla_*$DLL_EXT" -type f); do
    if [ -f "$f" ]; then
        cp "$f" "$JKA_BASE/"
        [ "$PLATFORM" = "macOS" ] && cp "$f" "$SP_DYLIB_DIR/"
    fi
done

#-----------------------------------------------------------------------------
# Copy SDL3 runtime (Windows)
#-----------------------------------------------------------------------------
if [ "$PLATFORM" = "Windows" ]; then
    for f in "$BUILD_DIR/SDL3"*".dll"; do
        if [ -f "$f" ]; then
            cp "$f" "$JKA_DIR/"
        fi
    done
fi

#-----------------------------------------------------------------------------
# Copy JK2 SP game module
#-----------------------------------------------------------------------------
if $INCLUDE_JK2; then
    echo "  - JK2 SP (JediOutcast/)..."
    mkdir -p "$JK2_BASE"

    # Copy JK2 SP engine
    if [ "$PLATFORM" = "macOS" ] && [ -d "$BUILD_DIR/openjo_sp.$ARCH.app" ]; then
        cp -R "$BUILD_DIR/openjo_sp.$ARCH.app" "$JK2_DIR/OpenJO-SP.app"
        JK2_DYLIB_DIR="$JK2_DIR/OpenJO-SP.app/Contents/MacOS"
        mkdir -p "$JK2_DYLIB_DIR/base"
        JK2_BASE="$JK2_DYLIB_DIR/base"
    elif [ -f "$BUILD_DIR/openjo_sp.$ARCH$EXE_EXT" ]; then
        cp "$BUILD_DIR/openjo_sp.$ARCH$EXE_EXT" "$JK2_DIR/openjo_sp"
        JK2_DYLIB_DIR="$JK2_DIR"
    else
        JK2_DYLIB_DIR="$JK2_DIR"
    fi

    # Copy JK2 game module
    for f in $(find "$BUILD_DIR" -name "jospgame*$DLL_EXT" -type f); do
        if [ -f "$f" ]; then
            cp "$f" "$JK2_BASE/"
            [ "$PLATFORM" = "macOS" ] && cp "$f" "$JK2_DYLIB_DIR/"
        fi
    done

    # Copy JK2 renderer
    for f in $(find "$BUILD_DIR" -name "rdjosp-vanilla_*$DLL_EXT" -type f); do
        if [ -f "$f" ]; then
            cp "$f" "$JK2_BASE/"
            [ "$PLATFORM" = "macOS" ] && cp "$f" "$JK2_DYLIB_DIR/"
        fi
    done
fi

#-----------------------------------------------------------------------------
# Create README
#-----------------------------------------------------------------------------
echo "  - README..."
cat > "$PUBLISH_TARGET/README.txt" << 'README_EOF'
OpenJK - Published Build
========================

This directory contains a pre-built OpenJK engine for your platform.

Directory structure:
  JediAcademy/               Jedi Academy files
    openjk.*                  Multiplayer client
    openjk_sp.*               Single player client
    openjkded.*               Dedicated server
    base/                     Game modules (place game assets here)
      jampgame*.*             MP server game module
      cgame*.*                MP client game module
      ui*.*                   MP UI module
      jagame*.*               SP game module
      rd-vanilla_*.*          Vanilla renderer
      rd-rend2_*.*            Rend2 renderer (experimental)
      rdsp-vanilla_*.*        SP vanilla renderer

To run:
  1. Copy your Jedi Academy game assets to JediAcademy/base/
     (assets0.pk3, assets1.pk3, assets2.pk3, assets3.pk3)
  2. Launch the client for your desired game mode
  3. For dedicated server: ./openjkded.* +set dedicated 2 +exec server.cfg

For more information, visit:
  https://github.com/JACoders/OpenJK
README_EOF

#=============================================================================
# Summary
#=============================================================================
echo ""
echo "============================================"
echo " Publish complete!"
echo " Output: $PUBLISH_TARGET"
echo "============================================"
echo ""
if [ -d "$JKA_DIR" ]; then
    echo "JediAcademy contents:"
    find "$JKA_DIR" -type f -maxdepth 2 | sort | while read -r f; do
        echo "  ${f#$PUBLISH_TARGET/}"
    done
fi
echo ""

# List .app bundles if any
if [ "$PLATFORM" = "macOS" ]; then
    find "$PUBLISH_TARGET" -name "*.app" -maxdepth 3 | sort | while read -r app; do
        echo "App bundle: ${app#$PUBLISH_TARGET/}"
    done
fi
