#!/bin/bash
# ============================================================
# USB GPS Bridge - Termux One-Command Build
# ============================================================
# 
# STEP 1: On your Android head unit, install Termux from F-Droid
#         (Google Play version is deprecated)
#
# STEP 2: In Termux, paste and run these commands:
#
#   pkg update && pkg install -y git clang make
#   cd ~/storage/shared  # or wherever you extracted the zip
#   cd usb-gps-switcher/src
#   chmod +x build.sh
#   ./build.sh
#
# STEP 3: Copy the compiled usbgps binary to the module:
#   cp usbgps ../system/vendor/bin/usbgps
#   chmod 755 ../system/vendor/bin/usbgps
#
# STEP 4: Re-zip and install via Magisk
#
# ============================================================

set -e

echo "============================================"
echo " USB GPS Bridge - Termux Native Build"
echo "============================================"
echo ""

# Detect environment
ARCH=$(getprop ro.product.cpu.abi 2>/dev/null || uname -m)
OS=$(getprop ro.build.version.release 2>/dev/null || uname -r)
echo "  Device: $ARCH"
echo "  Android: $OS"
echo ""

# Check for NDK (if termux-ndk is installed)
NDK_PREFIX="$HOME/android-ndk"
if [ -d "$NDK_PREFIX" ]; then
    echo "[+] Found termux-ndk"
    NDK_PATH=$(find "$NDK_PREFIX" -name 'aarch64-linux-android*clang++' 2>/dev/null | head -1)
    if [ -n "$NDK_PATH" ]; then
        echo "[+] Using: $NDK_PATH"
        CC="$NDK_PATH"
        # Try to get API level from path
        API=$(echo "$NDK_PATH" | grep -o 'android[0-9]*' | head -1 | tr -d 'android')
        API="${API:-21}"
        CFLAGS="--target=aarch64-linux-android${API} -O2 -Wall"
        echo "[+] Target API: android-${API}"
    fi
fi

# Fallback: use clang directly with Android target
if [ -z "$CC" ]; then
    echo "[*] Using clang (Termux native)"
    CC="clang"
    # Detect Android API level
    if [ -f "$PREFIX/sysroot/usr/include/android/api-level.h" ]; then
        API=$(cat "$PREFIX/sysroot/usr/include/android/api-level.h" | head -1 | tr -d ' ')
    else
        API="21"
    fi
    CFLAGS="--target=aarch64-linux-android${API} -O2 -Wall -static"
fi

echo ""
echo "[*] Compiling usbgps.c..."
echo "    CC: $CC"
echo "    CFLAGS: $CFLAGS"

$CC $CFLAGS -o usbgps usbgps.c -static 2>&1

if [ -f usbgps ]; then
    SIZE=$(wc -c < usbgps)
    echo ""
    echo "[+] Build successful!"
    echo "    Binary: usbgps"
    echo "    Size: $SIZE bytes ($(echo "scale=1; $SIZE/1024" | bc) KB)"
    echo ""
    
    # Try to show file info
    if command -v file >/dev/null 2>&1; then
        echo "    $(file usbgps)"
    fi
    
    echo ""
    echo "============================================"
    echo " Next steps:"
    echo " 1. cp usbgps ../system/vendor/bin/usbgps"
    echo " 2. chmod 755 ../system/vendor/bin/usbgps"
    echo " 3. Re-zip and flash via Magisk"
    echo "============================================"
else
    echo ""
    echo "[-] Build failed! Check errors above."
    exit 1
fi
