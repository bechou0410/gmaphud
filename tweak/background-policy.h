#pragma once
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#define GVM_BACKGROUND_SIGNAL "com.chou.gmaphud.background.carplay"
#define GVM_BACKGROUND_PHONE_SIGNAL "com.chou.gmaphud.background.phone"
static inline bool GVMBackgroundActive(double now, uint64_t heartbeat) {
    double age = now - (double)heartbeat / 1000.0;
    return heartbeat && isfinite(now) && age >= 0 && age < 12;
}
// Waking the selected source: one launch every 3 seconds while it is not running. A launch that
// fails, or a process that disappears before the source has published, is a failed attempt; fresh
// output from the source clears the count. After 5 failed attempts (an app that keeps crashing, or
// one that is not installed) the supervisor moves to another source.
enum { GVMWakeAttempts=5 };
#define GVMWakeInterval 3.0
static inline bool GVMWakeMayLaunch(double now, double next, unsigned failures) {
    return isfinite(now) && isfinite(next) && now >= next && failures < GVMWakeAttempts;
}
static inline bool GVMWakeExhausted(unsigned failures) { return failures >= GVMWakeAttempts; }
// The fifth attempt gets its full interval too before the supervisor moves on.
static inline bool GVMWakeSwitchDue(double now, double next, unsigned failures) {
    return GVMWakeExhausted(failures) && isfinite(now) && isfinite(next) && now >= next;
}
// The source to move to: the first of VietMap Live (1), GOFA (3), Waze (2) that is `available`
// (bit n set when source n is installed and enabled) and not `exhausted` in this episode; 0 if none.
static inline unsigned GVMWakeFallbackSource(unsigned available, unsigned exhausted) {
    static const unsigned order[]={1,3,2};
    for (unsigned i=0;i<3;i++) {
        unsigned source=order[i];
        if (((available>>source)&1) && !((exhausted>>source)&1)) return source;
    }
    return 0;
}
// A wake is proven only by a process that has lived 10 s and output sampled after it started, so the
// last frame of a process that just crashed (still fresh for 5 s) never counts.
static inline bool GVMWakeProven(double now, double processSince, double newestSample) {
    return processSince > 0 && isfinite(now) && isfinite(newestSample) && now - processSince >= 10 &&
        newestSample >= processSince;
}
// A source process GMapHUD may close later: it appeared within 15 s of GMapHUD's own launch request.
// One the user opened, or one that has been on a screen, is never GMapHUD's to close.
static inline bool GVMWakeOwnsProcess(double launchRequestedAt, double processSince) {
    return launchRequestedAt > 0 && isfinite(processSince) && processSince >= launchRequestedAt &&
        processSince - launchRequestedAt <= 15;
}
// Google Maps closed (its process gone) for this long: the source it kept awake exits too.
static inline bool GVMHostExitDue(double now, double goneAt) {
    return goneAt > 0 && isfinite(now) && isfinite(goneAt) && now - goneAt >= 10;
}
// A heartbeat after a gap (the map was hidden, or this is the first) is also posted, so the supervisor
// wakes the source at once instead of on its next idle tick.
static inline bool GVMHeartbeatResumed(double now, double last) {
    return last < 0 || !isfinite(last) || now - last >= 6;
}
static inline bool GVMBackgroundAnyHostActive(double now, uint64_t carplay, uint64_t phone) {
    return GVMBackgroundActive(now,carplay) || GVMBackgroundActive(now,phone);
}
static inline double GVMBackgroundRetryDelay(unsigned attempts) {
    return attempts <= 1 ? 15 : attempts == 2 ? 30 : 60;
}

#define GVM_BACKGROUND_PERMISSION "com.chou.gmaphud.background.permission"
#define GVM_BACKGROUND_LOCATION_SESSION "com.chou.gmaphud.background.location-session"
static inline bool GVMBackgroundLocationAuthorized(int status) {
    // Core Location: 3 = Always; 4 = When In Use. Unknown/denied fail closed.
    return status==3 || status==4;
}
static inline bool GVMBackgroundNeedsUsageContext(int status, bool active) {
    return active && status==4;
}
static inline uint64_t GVMBackgroundPermissionState(double now, bool allowed) {
    if (!isfinite(now) || now<1 || now>UINT32_MAX) return 0;
    return ((uint64_t)now<<1) | (allowed ? 1 : 0);
}
static inline bool GVMBackgroundPermissionAllowed(double now, uint64_t state) {
    double age=now-(double)(state>>1);
    return (state&1) && isfinite(now) && age>=0 && age<6;
}

// A selected source may continue its own running GPS only while a real host is visible.
static inline bool GVMBackgroundSourceLocationActive(bool selected, int authorization, bool services,
    double now, uint64_t carplay, uint64_t phone) {
    return selected && services && GVMBackgroundLocationAuthorized(authorization) &&
        GVMBackgroundAnyHostActive(now,carplay,phone);
}

#define GVM_BACKGROUND_LOCATION_SOURCE "com.chou.gmaphud.background.location-source"
// A source app with a scene in the foreground, on the iPhone or on CarPlay, writes its pid here
// (`%u` is its source ID) and posts it. The supervisor never closes a process that has been shown.
#define GVM_BACKGROUND_SOURCE_SHOWN "com.chou.gmaphud.background.shown.%u"
#define GVM_BACKGROUND_BOOTSTRAP_CARPLAY "com.chou.gmaphud.background.bootstrap-carplay"
static inline bool GVMBackgroundDisconnectDue(double now,double disconnectedAt) {
    return disconnectedAt>0 && isfinite(now) && isfinite(disconnectedAt) && now-disconnectedAt>=20;
}
// Auto-exit after a CarPlay disconnect holds the source closed only while no Google Maps is
// visible on the iPhone; a visible phone map is still in use and may wake the source again.
static inline bool GVMBackgroundExitHolds(bool autoExit, bool connected, bool phoneVisible,
    double disconnectedAt, bool exitCompleted) {
    return autoExit && !connected && !phoneVisible && (disconnectedAt>0 || exitCompleted);
}

// Cold GPS recovery is bounded and ends once a genuinely fresh sample arrives.
static inline bool GVMBackgroundGPSRetryDue(double now, double next, unsigned attempts, bool confirmed) {
    return !confirmed && isfinite(now) && isfinite(next) && next>0 && now>=next && attempts>0 && attempts<3;
}
