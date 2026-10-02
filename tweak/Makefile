export THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:16.5:14.0
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = VietMapGoogleMapsSource GoogleMapsVietMap
VietMapGoogleMapsSource_FILES = vietmap-source.x nav-source.m nav-payload.m speed-state.m
VietMapGoogleMapsSource_CFLAGS = -fobjc-arc -DVM_GOOGLE_MAPS_RELAY=1
VietMapGoogleMapsSource_FRAMEWORKS = UIKit Foundation
GoogleMapsVietMap_FILES = google-hook.m carplay-style.m speed-presentation.m speed-state.m test-state.m
GoogleMapsVietMap_CFLAGS = -fobjc-arc -Wall -Wextra
GoogleMapsVietMap_FRAMEWORKS = UIKit Foundation
GoogleMapsVietMap_LIBRARIES = substrate
include $(THEOS)/makefiles/tweak.mk

TOOL_NAME = gvm-test-speed
gvm-test-speed_FILES = test-speed.m test-state.m
gvm-test-speed_CFLAGS = -fobjc-arc -Wall -Wextra
gvm-test-speed_FRAMEWORKS = Foundation
gvm-test-speed_INSTALL_PATH = /usr/bin
include $(THEOS)/makefiles/tool.mk
