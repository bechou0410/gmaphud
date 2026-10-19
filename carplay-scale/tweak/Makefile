export THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:16.5:14.0
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CarPlayScale
CarPlayScale_FILES = scale-hook.m scale-math.m
CarPlayScale_CFLAGS = -fno-objc-arc -Wall -Wextra -Werror
CarPlayScale_FRAMEWORKS = Foundation CoreGraphics
CarPlayScale_LIBRARIES = substrate
include $(THEOS)/makefiles/tweak.mk

BUNDLE_NAME = CarPlayScalePrefs
CarPlayScalePrefs_FILES = prefs/preferences-controller.m scale-math.m
CarPlayScalePrefs_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
CarPlayScalePrefs_FRAMEWORKS = Foundation UIKit CoreGraphics
CarPlayScalePrefs_PRIVATE_FRAMEWORKS = Preferences
CarPlayScalePrefs_INSTALL_PATH = /Library/PreferenceBundles
CarPlayScalePrefs_RESOURCE_DIRS = prefs/Resources
include $(THEOS)/makefiles/bundle.mk
