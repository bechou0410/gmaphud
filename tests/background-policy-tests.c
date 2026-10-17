#include "../tweak/background-policy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    assert(!GVMBackgroundDisconnectDue(100,0));
    assert(!GVMBackgroundDisconnectDue(119.999,100));
    assert(GVMBackgroundDisconnectDue(120,100));
    assert(GVMBackgroundDisconnectDue(125,100));
    assert(!GVMBackgroundDisconnectDue(99,100));
    assert(!GVMBackgroundDisconnectDue(NAN,100));
    assert(!GVMBackgroundDisconnectDue(120,NAN));
    // Auto-exit holds only while neither CarPlay nor the iPhone map is in use.
    assert(GVMBackgroundExitHolds(true,false,false,100,false));
    assert(GVMBackgroundExitHolds(true,false,false,0,true));
    assert(!GVMBackgroundExitHolds(true,false,true,100,false));
    assert(!GVMBackgroundExitHolds(true,false,true,0,true));
    assert(!GVMBackgroundExitHolds(true,true,false,100,true));
    assert(!GVMBackgroundExitHolds(false,false,false,100,true));
    assert(!GVMBackgroundExitHolds(true,false,false,0,false));
    assert(GVMBackgroundSourceLocationActive(true,4,true,10,10000,0));
    assert(GVMBackgroundSourceLocationActive(true,3,true,10,0,10000));
    assert(!GVMBackgroundSourceLocationActive(false,4,true,10,10000,0));
    assert(!GVMBackgroundSourceLocationActive(true,2,true,10,10000,0));
    assert(!GVMBackgroundSourceLocationActive(true,4,false,10,10000,0));
    assert(!GVMBackgroundSourceLocationActive(true,4,true,22,10000,0));
    assert(!GVMBackgroundSourceLocationActive(true,4,true,9,10000,0));
    assert(!GVMBackgroundSourceLocationActive(true,4,true,10,0,0));

    assert(GVMBackgroundLocationAuthorized(3));
    assert(GVMBackgroundLocationAuthorized(4));
    for (int status=-1;status<=2;status++) assert(!GVMBackgroundLocationAuthorized(status));
    assert(!GVMBackgroundLocationAuthorized(5));
    assert(GVMBackgroundNeedsUsageContext(4,true));
    assert(!GVMBackgroundNeedsUsageContext(4,false));
    for (int status=-1;status<=5;status++) {
        if (status!=4) assert(!GVMBackgroundNeedsUsageContext(status,true));
    }
    // A heartbeat is posted when it resumes after a gap (or is the first), not on every beat.
    assert(GVMHeartbeatResumed(10,-1) && GVMHeartbeatResumed(10,NAN));
    assert(GVMHeartbeatResumed(16,10) && !GVMHeartbeatResumed(13,10) && !GVMHeartbeatResumed(15.9,10));
    assert(!GVMBackgroundActive(10,0));
    assert(GVMBackgroundActive(10,10000));
    assert(GVMBackgroundActive(21.999,10000));
    assert(!GVMBackgroundActive(22,10000));
    assert(!GVMBackgroundActive(9,10000));
    assert(!GVMBackgroundActive(NAN,10000));
    assert(GVMBackgroundAnyHostActive(10,10000,0));
    assert(GVMBackgroundAnyHostActive(10,0,10000));
    assert(GVMBackgroundAnyHostActive(22,10000,21000));
    assert(GVMBackgroundAnyHostActive(22,21000,10000));
    assert(!GVMBackgroundAnyHostActive(22,10000,10000));
    assert(!GVMBackgroundAnyHostActive(10,0,0));
    assert(!GVMBackgroundAnyHostActive(10,11000,0));
    assert(!GVMBackgroundAnyHostActive(NAN,10000,10000));
    // Wake: every 3 s, five failed attempts, then another source.
    assert(GVMWakeMayLaunch(15,15,0) && GVMWakeMayLaunch(18,15,4));
    assert(!GVMWakeMayLaunch(14.9,15,1) && !GVMWakeMayLaunch(100,15,5) && !GVMWakeMayLaunch(NAN,15,0) && !GVMWakeMayLaunch(15,NAN,0));
    assert(!GVMWakeExhausted(4) && GVMWakeExhausted(5) && GVMWakeInterval==3.0);
    // The fifth attempt also gets its 3 s before the supervisor moves on.
    assert(!GVMWakeSwitchDue(20.9,21,5) && GVMWakeSwitchDue(21,21,5) && !GVMWakeSwitchDue(30,21,4));
    assert(!GVMWakeSwitchDue(NAN,21,5) && !GVMWakeSwitchDue(21,NAN,5));
    // Fallback order VietMap Live, GOFA, Waze among installed sources not already given up.
    assert(GVMWakeFallbackSource((1u<<1)|(1u<<2)|(1u<<3),1u<<2)==1);
    assert(GVMWakeFallbackSource((1u<<1)|(1u<<2)|(1u<<3),1u<<1)==3);
    assert(GVMWakeFallbackSource((1u<<1)|(1u<<2)|(1u<<3),(1u<<1)|(1u<<3))==2);
    assert(GVMWakeFallbackSource(1u<<2,1u<<1)==2 && GVMWakeFallbackSource(1u<<3,1u<<3)==0 && GVMWakeFallbackSource(0,0)==0);
    // A wake is proven by a process alive 10 s with output sampled after it started.
    assert(GVMWakeProven(110,100,105) && !GVMWakeProven(109,100,105) && !GVMWakeProven(120,100,99.9) && !GVMWakeProven(120,0,105));
    assert(!GVMWakeProven(NAN,100,105) && !GVMWakeProven(120,100,NAN));
    // Only a process that appeared after GMapHUD's own launch request is GMapHUD's.
    assert(GVMWakeOwnsProcess(100,101) && GVMWakeOwnsProcess(100,115) && !GVMWakeOwnsProcess(100,116) && !GVMWakeOwnsProcess(100,99) && !GVMWakeOwnsProcess(0,5));
    // Google Maps closed for 10 s: its source exits.
    assert(!GVMHostExitDue(100,0) && !GVMHostExitDue(109.9,100) && GVMHostExitDue(110,100) && !GVMHostExitDue(NAN,100));
    assert(GVMBackgroundRetryDelay(2)>GVMBackgroundRetryDelay(1));
    assert(GVMBackgroundPermissionAllowed(100,GVMBackgroundPermissionState(100,true)));
    assert(!GVMBackgroundPermissionAllowed(106,GVMBackgroundPermissionState(100,true)));
    assert(!GVMBackgroundPermissionAllowed(99,GVMBackgroundPermissionState(100,true)));
    assert(!GVMBackgroundPermissionAllowed(100,GVMBackgroundPermissionState(100,false)));
    assert(!GVMBackgroundPermissionAllowed(100,0));
    assert(!GVMBackgroundPermissionAllowed(NAN,201));
    assert(GVMBackgroundPermissionState(NAN,true)==0);
    assert(!GVMBackgroundGPSRetryDue(29,30,1,false));
    assert(GVMBackgroundGPSRetryDue(30,30,1,false));
    assert(GVMBackgroundGPSRetryDue(90,90,2,false));
    assert(!GVMBackgroundGPSRetryDue(200,90,3,false));
    assert(!GVMBackgroundGPSRetryDue(30,30,1,true));
    assert(!GVMBackgroundGPSRetryDue(NAN,30,1,false));
    assert(!GVMBackgroundGPSRetryDue(30,NAN,1,false));
    assert(!GVMBackgroundGPSRetryDue(30,0,1,false));
    assert(!GVMBackgroundGPSRetryDue(30,30,0,false));
    puts("background policy tests passed");
}
