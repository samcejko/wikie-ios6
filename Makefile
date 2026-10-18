# Kiwix - offline Wikipedia and ZIM reader for jailbroken iOS 6.x (armv7).
# Built with Theos. Deployment target iOS 6.0, compiled against the iOS 9.3 SDK.

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
TARGET := iphone:clang:16.5:14.0
ARCHS := arm64
else
TARGET := iphone:clang:9.3:6.0
ARCHS := armv7
endif
DEBUG ?= 0

ifeq ($(origin THEOS_DEVICE_IP),undefined)
KIWIX_LOCAL_IPAD := $(shell sed -n 's/.*"ipad"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' tools/local.json 2>/dev/null)
ifneq ($(KIWIX_LOCAL_IPAD),)
THEOS_DEVICE_IP := $(KIWIX_LOCAL_IPAD)
endif
endif
THEOS_DEVICE_USER ?= root

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := Wikie

ZSTD_FILES := $(wildcard vendor/zstd/*.c)
MBEDTLS_FILES := $(wildcard vendor/mbedtls/library/*.c)

Wikie_FILES := $(wildcard src/*.m) \
               $(wildcard src/*/*.m) \
               $(wildcard src/*/*/*.m) \
               $(ZSTD_FILES) \
               $(MBEDTLS_FILES) \
               vendor/mbedtls_glue.c

Wikie_FRAMEWORKS := UIKit Foundation CoreGraphics QuartzCore Security

Wikie_CFLAGS := -Isrc -Isrc/ZIM -Isrc/Model -Isrc/Protocol -Isrc/UI \
                -Isrc/UI/Library -Isrc/UI/Reader -Isrc/UI/Search -Isrc/UI/Catalog -Isrc/UI/Server \
                -Ivendor -Ivendor/mbedtls/include -Ivendor/mbedtls/library -Ivendor/zstd \
                -Os -fvisibility=hidden \
                -Wall -Wno-unused-variable -Wno-unused-function -Wno-unused-but-set-variable \
                -Wno-deprecated-declarations -Wno-unknown-warning-option \
                -Wno-nullability-completeness -Wno-nullability-completeness-on-arrays -Wno-error

Wikie_OBJCFLAGS := -fobjc-arc -Wunguarded-availability

Wikie_LDFLAGS := -lz

Wikie_CODESIGN_FLAGS := -SResources/entitlements.plist

include $(THEOS)/makefiles/application.mk

WIKIE_STAGED_APP := $(THEOS_STAGING_DIR)/Applications/Wikie.app
WIKIE_STAGED_BIN := $(WIKIE_STAGED_APP)/Wikie

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
after-stage::
	python3 "$(THEOS_PROJECT_DIR)/tools/modern_bundle.py" "$(WIKIE_STAGED_APP)"
	ldid -S"$(THEOS_PROJECT_DIR)/Resources/entitlements.plist" "$(WIKIE_STAGED_BIN)"
before-package::
	sed -i -e 's/^Depends: .*/Depends: firmware (>= 15.0)/' "$(THEOS_STAGING_DIR)/DEBIAN/control"
	printf '%s\n' '#!/bin/sh' '[ "$$1" = configure ] || exit 0' \
		'command -v uicache >/dev/null 2>&1 && { uicache -p /var/jb/Applications/Wikie.app >/dev/null 2>&1 || uicache -a >/dev/null 2>&1; }' \
		'exit 0' > "$(THEOS_STAGING_DIR)/DEBIAN/postinst"
	printf '%s\n' '#!/bin/sh' '[ "$$1" = remove ] || exit 0' \
		'command -v uicache >/dev/null 2>&1 && uicache -a >/dev/null 2>&1' \
		'exit 0' > "$(THEOS_STAGING_DIR)/DEBIAN/postrm"
	chmod 0755 "$(THEOS_STAGING_DIR)/DEBIAN/postinst" "$(THEOS_STAGING_DIR)/DEBIAN/postrm"
else
# The iOS 9.3 SDK places the NSURL* loading classes in CFNetwork; on iOS 6 they live in Foundation and dyld aborts at
# launch when the binary asks CFNetwork for them. Change CFNetwork reference to Foundation and resign.
after-stage::
	llvm-install-name-tool -change /System/Library/Frameworks/CFNetwork.framework/CFNetwork /System/Library/Frameworks/Foundation.framework/Foundation "$(WIKIE_STAGED_BIN)" || install_name_tool -change /System/Library/Frameworks/CFNetwork.framework/CFNetwork /System/Library/Frameworks/Foundation.framework/Foundation "$(WIKIE_STAGED_BIN)" || true
	ldid -S"$(THEOS_PROJECT_DIR)/Resources/entitlements.plist" "$(WIKIE_STAGED_BIN)"
endif

after-all::
	@echo "Wikie build complete."
