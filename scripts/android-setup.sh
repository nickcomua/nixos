#!/usr/bin/env bash
# Android Emulator Setup with KernelSU and GPhotosUnlimited
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_HOME="${ANDROID_HOME:-$HOME/.android}"
EMULATOR_NAME="rooted_android"
DOWNLOADS_DIR="$HOME/Downloads/android-setup"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    command -v adb >/dev/null 2>&1 || error "ADB not found. Please rebuild NixOS with android-emulator enabled."
    command -v emulator >/dev/null 2>&1 || error "Android emulator not found. Please rebuild NixOS."
    command -v wget >/dev/null 2>&1 || error "wget not found"
    command -v unzip >/dev/null 2>&1 || error "unzip not found"
    
    # Check KVM acceleration
    if [[ -c /dev/kvm ]]; then
        log "KVM acceleration available"
    else
        warn "KVM acceleration not available. Emulation will be slow."
    fi
}

setup_directories() {
    log "Setting up directories..."
    mkdir -p "$DOWNLOADS_DIR"
    mkdir -p "$ANDROID_HOME/emulator"
    mkdir -p "$ANDROID_HOME/system-images"
}

download_android_image() {
    log "Setting up Android system image with Google APIs..."
    
    # Note: You'll need to use Android Studio or sdkmanager to download system images
    # This script provides the framework, but actual image downloads require proper licensing
    warn "You need to download Android system images manually through Android Studio:"
    warn "1. Install Android Studio"
    warn "2. Use AVD Manager to download a system image with Google APIs"
    warn "3. Create an emulator with the downloaded image"
    warn "4. Continue with rooting process below"
}

setup_kernelsu() {
    log "Setting up KernelSU and rooting tools..."
    
    cat << 'EOF'
ROOTING PROCESS:

1. Download KernelSU:
   - Visit: https://github.com/tiann/KernelSU/releases
   - Download the latest KernelSU APK and kernel image

2. Boot from KernelSU kernel:
   - Use custom recovery or bootloader unlock
   - Flash KernelSU kernel image

3. Install Zygisk Next:
   - Download from: https://github.com/Dr-TSNG/ZygiskNext/releases
   - Install as a KernelSU module

4. Install GPhotosUnlimited:
   - Download from: https://github.com/Rev4N1/GPhotosUnlimited/releases
   - Install as a Zygisk module

EMULATOR-SPECIFIC NOTES:
- Use x86_64 Android image for better performance
- Enable hardware acceleration in AVD settings
- Some rooting methods may require custom kernels not available for emulator
- Consider using Magisk instead of KernelSU for emulator environments
EOF
}

setup_gphotos_unlimited() {
    log "Downloading GPhotosUnlimited module..."
    
    local repo_url="https://github.com/Rev4N1/GPhotosUnlimited"
    local download_url="$repo_url/releases/latest/download"
    
    cd "$DOWNLOADS_DIR"
    
    # Download the module (check releases page for actual filename)
    warn "Please download the GPhotosUnlimited module manually from:"
    warn "$repo_url/releases"
    
    cat << 'EOF'

INSTALLATION STEPS FOR GPHOTOS UNLIMITED:

1. Download the module from the GitHub releases page
2. Install in your rooted Android environment:
   - For KernelSU: Use KernelSU Manager app
   - For Magisk: Use Magisk Manager app
3. Reboot the device/emulator
4. Install Google Photos from Play Store
5. The module should automatically provide unlimited storage

CONFIGURATION:
- Module logs: adb shell "logcat | grep 'FGP/'"
- Custom config: /data/adb/modules/unlimitedphotos/custom.fgp.json
- Verbose logging: Add "verboseLogs": "1" to config

TROUBLESHOOTING:
- Ensure Google Photos is NOT in Magisk DenyList
- Check module logs for errors
- Verify Zygisk is enabled and working
- Test with a small photo upload first
EOF
}

create_emulator_script() {
    log "Creating emulator launch script..."
    
    cat > "$HOME/.local/bin/android-emu" << 'EOF'
#!/bin/bash
# Launch rooted Android emulator
EMULATOR_NAME="${1:-rooted_android}"

echo "Starting Android emulator: $EMULATOR_NAME"
echo "To connect via ADB: adb connect localhost:5555"

emulator -avd "$EMULATOR_NAME" \
    -gpu auto \
    -memory 4096 \
    -partition-size 8192 \
    -writable-system \
    -selinux permissive \
    -qemu -enable-kvm
EOF
    
    chmod +x "$HOME/.local/bin/android-emu"
    log "Created launcher: android-emu [emulator_name]"
}

main() {
    log "Starting Android rooted emulator setup..."
    
    check_prerequisites
    setup_directories
    download_android_image
    setup_kernelsu
    setup_gphotos_unlimited
    create_emulator_script
    
    cat << EOF

${GREEN}Setup script completed!${NC}

NEXT STEPS:
1. Rebuild NixOS to apply Android emulator configuration
2. Install Android Studio and create an AVD with Google APIs
3. Follow the rooting instructions provided above
4. Install and configure the GPhotosUnlimited module
5. Use 'android-emu' command to launch your emulator

FILES CREATED:
- Android setup downloads: $DOWNLOADS_DIR
- Emulator launcher: $HOME/.local/bin/android-emu

${YELLOW}IMPORTANT NOTES:${NC}
- This setup is for educational/development purposes
- Modifying Google Photos may violate Google's Terms of Service
- Use at your own risk and responsibility
- Ensure you comply with applicable laws and terms

EOF
}

main "$@"