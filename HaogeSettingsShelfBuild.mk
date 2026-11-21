DEBUG ?= 0
FINALPACKAGE ?= 1
# iPhone 14 Pro Max / arm64e system processes; no arm64 fallback slice.
ARCHS = arm64e

# Rootless and Roothide require iOS 15 or newer.
ifneq ($(filter rootless roothide,$(THEOS_PACKAGE_SCHEME)),)
TARGET = iphone:clang:16.5:15.0
else
TARGET = iphone:clang:16.5:15.0
endif
