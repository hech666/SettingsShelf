include ../HaogeSettingsShelfBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = HaogeSettingsShelfPrefs
HaogeSettingsShelfPrefs_FILES = $(wildcard *.m)
HaogeSettingsShelfPrefs_CFLAGS = -fobjc-arc -I../Headers -I../Sources
HaogeSettingsShelfPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
HaogeSettingsShelfPrefs_PRIVATE_FRAMEWORKS = Preferences
HaogeSettingsShelfPrefs_INSTALL_PATH = /Library/PreferenceBundles
HaogeSettingsShelfPrefs_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/bundle.mk
