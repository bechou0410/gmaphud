export THEOS_PACKAGE_SCHEME ?= rootless
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
THEOS_PACKAGE_ARCH = iphoneos-arm64
else
THEOS_PACKAGE_ARCH = iphoneos-arm
endif
TARGET = iphone:clang:16.5:14.0
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk
GVM_PACKAGE_VERSION := $(shell sed -n 's/^Version: *//p' control)
GVM_VERSION_CFLAGS = -DGVM_PACKAGE_VERSION='"$(GVM_PACKAGE_VERSION)"'
TWEAK_NAME = VietMapGoogleMapsSource GoogleMapsVietMap GMapHUDPlacementRelay GMapHUDOverspeedScreen WazeGMapHUDSource GofaGMapHUDSource GMapHUDGuidanceRelay
VietMapGoogleMapsSource_FILES = source-output.m source-transport.m vietmap-output.m diagnostics.m background-location.m vietmap-source.x nav-source.m nav-payload.m speed-state.m alert-state.m vietmap-alert-assets.m
VietMapGoogleMapsSource_CFLAGS = -fobjc-arc -DVM_GOOGLE_MAPS_RELAY=1 $(GVM_VERSION_CFLAGS)
VietMapGoogleMapsSource_FRAMEWORKS = UIKit Foundation CoreLocation
GoogleMapsVietMap_FILES = overspeed-frame.m source-output.m source-transport.m vietmap-output.m refresh-loop.m phone-overlay.m diagnostics.m google-hook.m carplay-style.m classic-card.m halo-style.m halo-card.m halo-lanes.m halo-dock.m guidance-state.m speed-presentation.m speed-state.m alert-state.m vietmap-alert-assets.m test-state.m placement-state.m
GoogleMapsVietMap_CFLAGS = -fobjc-arc -Wall -Wextra $(GVM_VERSION_CFLAGS)
GoogleMapsVietMap_FRAMEWORKS = UIKit Foundation QuartzCore CoreText
GoogleMapsVietMap_LIBRARIES = substrate
GMapHUDPlacementRelay_FILES = source-output.m source-transport.m speed-state.m alert-state.m placement-relay.m placement-state.m background-supervisor.m
GMapHUDPlacementRelay_CFLAGS = -fobjc-arc -Wall -Wextra
GMapHUDPlacementRelay_FRAMEWORKS = Foundation CoreLocation UIKit
GMapHUDPlacementRelay_LIBRARIES = substrate
GMapHUDGuidanceRelay_FILES = guidance-relay.m guidance-state.m
GMapHUDGuidanceRelay_CFLAGS = -fobjc-arc -Wall -Wextra
GMapHUDGuidanceRelay_FRAMEWORKS = UIKit Foundation
GMapHUDOverspeedScreen_FILES = overspeed-screen.m overspeed-frame.m placement-state.m
GMapHUDOverspeedScreen_CFLAGS = -fobjc-arc -Wall -Wextra
GMapHUDOverspeedScreen_FRAMEWORKS = UIKit Foundation QuartzCore
WazeGMapHUDSource_FILES = background-location.m waze-source.m waze-startup.m waze-output.m waze-limit-search.c source-output.m source-transport.m speed-state.m alert-state.m
WazeGMapHUDSource_CFLAGS = -DGVM_WAZE_SOURCE=1 -fobjc-arc -Wall -Wextra
WazeGMapHUDSource_FRAMEWORKS = Foundation UIKit CoreLocation
WazeGMapHUDSource_LIBRARIES = substrate
GofaGMapHUDSource_FILES = background-location.m gofa-source.m gofa-payload.swift source-output.m source-transport.m speed-state.m alert-state.m
GofaGMapHUDSource_CFLAGS = -DGVM_GOFA_SOURCE=1 -fobjc-arc -Wall -Wextra
GofaGMapHUDSource_FRAMEWORKS = Foundation UIKit CoreLocation
GofaGMapHUDSource_LIBRARIES = substrate
include $(THEOS)/makefiles/tweak.mk

BUNDLE_NAME = GMapHUDPrefs
GMapHUDPrefs_FILES = source-output.m source-transport.m speed-state.m alert-state.m diagnostics.m prefs/diagnostics-controller.m prefs/modules-controller.m prefs/preferences-controller.m placement-state.m
GMapHUDPrefs_CFLAGS = -fobjc-arc -Wall -Wextra $(GVM_VERSION_CFLAGS)
GMapHUDPrefs_FRAMEWORKS = Foundation UIKit
GMapHUDPrefs_PRIVATE_FRAMEWORKS = Preferences
GMapHUDPrefs_INSTALL_PATH = /Library/PreferenceBundles
GMapHUDPrefs_RESOURCE_DIRS = prefs/Resources
include $(THEOS)/makefiles/bundle.mk

TOOL_NAME = gvm-test-speed
gvm-test-speed_FILES = placement-state.m test-speed.m test-state.m alert-state.m vietmap-alert-assets.m
gvm-test-speed_CFLAGS = -fobjc-arc -Wall -Wextra
gvm-test-speed_FRAMEWORKS = Foundation
gvm-test-speed_INSTALL_PATH = /usr/bin
include $(THEOS)/makefiles/tool.mk
