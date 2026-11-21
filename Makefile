DEBUG = 0
FINALPACKAGE = 1

ARCHS = arm64 arm64e

# Share the SDK and deployment targets with the PreferenceBundle.
include HaogeSettingsShelfBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HaogeSettingsShelf
HaogeSettingsShelf_FILES = $(wildcard Hooks/*.xm Sources/*.m)
HaogeSettingsShelf_CFLAGS = -fobjc-arc -I./Headers -I./Sources
HaogeSettingsShelf_FRAMEWORKS = UIKit Foundation CoreFoundation ImageIO
HaogeSettingsShelf_PRIVATE_FRAMEWORKS = Preferences
HaogeSettingsShelf_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += HaogeSettingsShelfPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
