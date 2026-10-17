export THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:16.5:16.0
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YTHUD YTHUDHost
YTHUD_FILES = avplayer-trial.m mini-player-layout.m stream-video-policy.m dedicated-output.m paused-frame.m playback-state.m
YTHUD_CFLAGS = -DYTAV_RELEASE=1 -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations
YTHUD_FRAMEWORKS = Foundation UIKit AVFoundation QuartzCore CoreMedia CoreGraphics CoreImage CoreVideo
YTHUDHost_FILES = dedicated-dashboard.m
YTHUDHost_CFLAGS = -DYTAV_RELEASE=1 -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations
YTHUDHost_FRAMEWORKS = Foundation UIKit QuartzCore CoreGraphics

include $(THEOS)/makefiles/tweak.mk
