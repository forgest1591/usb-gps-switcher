# Makefile for USB GPS Bridge - Termux Native Build
# Target: Android ARM64 (aarch64-linux-android)
#
# Build instructions (Termux):
#   pkg update && pkg install clang make binutils
#   cd src && make
#
# Output: usbgps (ARM64 binary)

CC      ?= clang
CFLAGS  ?= -O2 -Wall -Wextra -static
LDFLAGS ?= -static

# Host toolchain (for Termux on ARM64 Android)
HOST_AARCH64 = aarch64-linux-android
PREFIX       = $(HOME)/.termux/ndk/sys
# If NDK installed via termux-ndk:
NDK_PREFIX   ?= $(HOME)/android-ndk-clang

# Check if we're in Termux (Android)
ifeq ($(shell uname -o 2>/dev/null),Android)
    # Termux on Android - use clang with Android target
    CC = clang
    # Try Android target
    CFLAGS += --target=aarch64-linux-android21
    LDFLAGS += --target=aarch64-linux-android21
    # Disable static on Termux (some libraries needed)
    LDFLAGS := -static
else
    # Standalone NDK
    ifneq ($(wildcard $(NDK_PREFIX)/bin/aarch64-linux-android31-clang++),)
        CC := $(NDK_PREFIX)/bin/aarch64-linux-android31-clang++
    else ifneq ($(wildcard $(NDK_PREFIX)/bin/aarch64-linux-android30-clang++),)
        CC := $(NDK_PREFIX)/bin/aarch64-linux-android30-clang++
    else
        # Fallback: try system clang
        CC := clang
        CFLAGS += --target=aarch64-linux-gnu
        LDFLAGS += --target=aarch64-linux-gnu
    endif
endif

SRC      = usbgps.c
TARGET   = usbgps
OUTDIR   = ../system/vendor/bin

.PHONY: all clean install strip debug release

all: $(TARGET)

$(TARGET): $(SRC)
	@echo "Building for Android ARM64..."
	@echo "CC: $(CC)"
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC) $(LDFLAGS)
	@echo "Build complete: $(TARGET)"
	@echo "  Size: $$(wc -c < $(TARGET)) bytes"
	@file $(TARGET) 2>/dev/null || echo "  (file command not available)"

strip: $(TARGET)
	@echo "Stripping debug symbols..."
	strip -s $(TARGET) -o $(TARGET).stripped
	@echo "  Original:  $$(wc -c < $(TARGET)) bytes"
	@echo "  Stripped: $$(wc -c < $(TARGET).stripped) bytes"
	@mv $(TARGET).stripped $(TARGET)

install: $(TARGET)
	@echo "Installing to $(OUTDIR)..."
	@mkdir -p $(OUTDIR)
	cp $(TARGET) $(OUTDIR)/$(TARGET)
	chmod 755 $(OUTDIR)/$(TARGET)
	@echo "Installed: $(OUTDIR)/$(TARGET)"

debug:
	$(MAKE) CC="$(CC)" CFLAGS="-O0 -g -Wall --target=aarch64-linux-android21" LDFLAGS="" $(TARGET)

release: strip install

clean:
	rm -f $(TARGET) $(TARGET).stripped

# Cross-compile from Linux PC using NDK
cross:
	NDK_PATH ?= /opt/android-ndk
	NDK := $(shell find $(NDK_PATH) -name 'aarch64-linux-android*clang++' 2>/dev/null | head -1)
ifneq ($(NDK),)
	$(NDK) -O2 -Wall -o $(TARGET) $(SRC)
else
	@echo "NDK not found. Install NDK and set NDK_PATH"
endif
