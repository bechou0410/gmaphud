#import "placement-state.h"

const char *GVMPlacementStateName = "com.chou.gmaphud.placement-state";

uint64_t GVMEncodePlacement(NSString *full, NSString *dashboard) {
    NSUInteger corner=[full isEqualToString:@"top-left"] ? 0 :
        [full isEqualToString:@"bottom-left"] ? 2 :
        [full isEqualToString:@"bottom-right"] ? 3 : 1;
    return 1 + corner + ([dashboard isEqualToString:@"left"] ? 4 : 0);
}
BOOL GVMDecodePlacement(uint64_t state, NSUInteger *full, BOOL *dashboardLeft) {
    if (state<1 || state>8) return NO;
    if (full) *full=(NSUInteger)((state-1)%4);
    if (dashboardLeft) *dashboardLeft=(state-1)>=4;
    return YES;
}

#include <math.h>
#include <notify.h>
const char *GVMSizeStateName="com.chou.gmaphud.size-state";
const char *GVMSizeChangedName="com.chou.gmaphud.size-changed";
const char *GVMBubbleVisibilityStateName="com.chou.gmaphud.bubble-visibility";
static BOOL BubbleToggle(id value) {
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : YES;
}
uint64_t GVMEncodeBubbleVisibility(id enabled,id full,id dashboard,id phone) {
    return (1ULL<<8) | BubbleToggle(enabled) | (BubbleToggle(full)<<1) |
        (BubbleToggle(dashboard)<<2) | (BubbleToggle(phone)<<3);
}
BOOL GVMDecodeBubbleVisibility(uint64_t state,NSUInteger surface) {
    if (surface>2) return NO;
    // Missing or legacy state preserves the previously always-visible behavior.
    if ((state>>8)!=1 || (state&0xf0)) return YES;
    return (state&1) && (state&(1ULL<<(surface+1)));
}
BOOL GVMBubbleEnabled(NSUInteger surface) {
    static int token=-1; uint64_t state=0;
    if (token<0) notify_register_check(GVMBubbleVisibilityStateName,&token);
    if (token>=0) notify_get_state(token,&state);
    return GVMDecodeBubbleVisibility(state,surface);
}
NSUInteger GVMSizePercent(id value) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()) return 100;
    double number=[value doubleValue];
    return isfinite(number) ? (NSUInteger)lround(MAX(GVMSizePercentMin,MIN(GVMSizePercentMax,number))) : 100;
}
uint64_t GVMEncodeSizes(id full,id dashboard,id phone) {
    return (1ULL<<24) | GVMSizePercent(full) | (GVMSizePercent(dashboard)<<8) | (GVMSizePercent(phone)<<16);
}
NSUInteger GVMDecodeSize(uint64_t state,NSUInteger surface) {
    if (state>>24!=1 || surface>2) return 100;
    NSUInteger value=(state>>(surface*8))&255;
    return value>=GVMSizePercentMin && value<=GVMSizePercentMax ? value : 100;
}
const char *GVMInterfaceStyleName="com.chou.gmaphud.interface-style";
uint64_t GVMEncodeInterfaceStyle(id value) {
    return (1ULL<<8) | ([value isEqual:@"halo"] ? GVMInterfaceHalo : GVMInterfaceClassic);
}
GVMInterfaceStyle GVMDecodeInterfaceStyle(uint64_t state) {
    return (state>>8)==1 && (state&255)==GVMInterfaceHalo ? GVMInterfaceHalo : GVMInterfaceClassic;
}
GVMInterfaceStyle GVMCurrentInterfaceStyle(void) {
    static int token=-1; uint64_t state=0;
    if (token<0) notify_register_check(GVMInterfaceStyleName,&token);
    if (token>=0) notify_get_state(token,&state);
    return GVMDecodeInterfaceStyle(state);
}
const char *GVMPresentationOptionsName="com.chou.gmaphud.presentation-options";
uint64_t GVMEncodePresentationOptions(id dial) {
    return (1ULL<<8) | ([dial isEqual:@"limit"] ? 1 : 0);
}
BOOL GVMDecodeLimitDial(uint64_t state) { return (state>>8)==1 && (state&1); }
uint64_t GVMCurrentPresentationOptions(void) {
    static int token=-1; uint64_t state=0;
    if (token<0) notify_register_check(GVMPresentationOptionsName,&token);
    if (token>=0) notify_get_state(token,&state);
    return state;
}
void GVMPublishSavedSizes(void) {
    CFStringRef domain=CFSTR("com.chou.gmaphud");
    CFPreferencesAppSynchronize(domain);
    id scope=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("overspeedScope"),domain));
    NSUInteger mode=[scope isEqual:@"map"] ? 1 : [scope isEqual:@"screen"] ? 2 : 0;
    static int overspeedToken=-1;
    if (overspeedToken<0) notify_register_check(GVMOverspeedModeName,&overspeedToken);
    if (overspeedToken>=0) { notify_set_state(overspeedToken,mode); notify_post(GVMOverspeedModeName); }
    id style=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("interfaceStyle"),domain));
    static int styleToken=-1;
    if (styleToken<0) notify_register_check(GVMInterfaceStyleName,&styleToken);
    if (styleToken>=0) { notify_set_state(styleToken,GVMEncodeInterfaceStyle(style)); notify_post(GVMInterfaceStyleName); }
    id dial=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("haloDial"),domain));
    static int optionsToken=-1;
    if (optionsToken<0) notify_register_check(GVMPresentationOptionsName,&optionsToken);
    if (optionsToken>=0) { notify_set_state(optionsToken,GVMEncodePresentationOptions(dial)); notify_post(GVMPresentationOptionsName); }
    id enabled=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("bubbleEnabled"),domain));
    id fullEnabled=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("fullEnabled"),domain));
    id dashboardEnabled=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("dashboardEnabled"),domain));
    id phoneEnabled=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("phoneEnabled"),domain));
    static int visibilityToken=-1;
    if (visibilityToken<0) notify_register_check(GVMBubbleVisibilityStateName,&visibilityToken);
    if (visibilityToken>=0) {
        notify_set_state(visibilityToken,GVMEncodeBubbleVisibility(enabled,fullEnabled,dashboardEnabled,phoneEnabled));
        notify_post(GVMBubbleVisibilityStateName);
    }
    id full=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("fullScale"),domain));
    id dashboard=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("dashboardScale"),domain));
    id phone=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("phoneScale"),domain));
    static int token=-1;
    if (token<0 && notify_register_check(GVMSizeStateName,&token)!=NOTIFY_STATUS_OK) return;
    notify_set_state(token,GVMEncodeSizes(full,dashboard,phone));
    notify_post(GVMSizeStateName);
    static int phoneToken=-1;
    if (phoneToken<0 && notify_register_check(GVMPhonePlacementStateName,&phoneToken)!=NOTIFY_STATUS_OK) return;
    id corner=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("phonePosition"),domain));
    id x=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("phoneXPercent"),domain));
    id y=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("phoneYPercent"),domain));
    id layout=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("phoneLayout"),domain));
    notify_set_state(phoneToken,GVMEncodePhonePlacement(corner,x,y,layout));
    notify_post(GVMPhonePlacementStateName);
    NSMutableArray *layouts=[NSMutableArray new];
    NSMutableArray *orders=[NSMutableArray new];
    for (NSString *prefix in @[@"full",@"dashboard",@"phone"]) {
        NSString *layoutKey=[prefix stringByAppendingString:@"Layout"];
        NSString *modulesKey=[prefix stringByAppendingString:@"Modules"];
        id layoutValue=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)layoutKey,domain));
        id modulesValue=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)modulesKey,domain));
        [layouts addObject:layoutValue ?: NSNull.null];
        [orders addObject:modulesValue ?: NSNull.null];
    }
    static int configurationToken=-1;
    if (configurationToken<0 && notify_register_check(GVMBubbleConfigurationStateName,&configurationToken)!=NOTIFY_STATUS_OK) return;
    notify_set_state(configurationToken,GVMEncodeBubbleConfiguration(layouts,orders));
    notify_post(GVMBubbleConfigurationStateName);
}

const char *GVMPhonePlacementStateName="com.chou.gmaphud.phone-placement-percent";
NSInteger GVMOffsetPercent(id value) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()) return 0;
    double number=[value doubleValue];
    return isfinite(number) ? (NSInteger)lround(MAX(-100,MIN(100,number))) : 0;
}
// Each branch converts on its own: a shared ternary of NSInteger and NSUInteger is unsigned, so
// a negative offset would turn huge and the slider would pin at its maximum.
double GVMSliderPercent(id value,BOOL offset) { return offset ? (double)GVMOffsetPercent(value) : (double)GVMSizePercent(value); }
uint64_t GVMEncodePhonePlacement(NSString *corner,id x,id y,NSString *layout) {
    if (![corner isKindOfClass:NSString.class]) corner=nil;
    NSUInteger mode=[layout isKindOfClass:NSString.class] ? ([layout isEqual:@"horizontal"] ? 1 : [layout isEqual:@"vertical"] ? 2 : 0) : 0;
    return (2ULL<<32) | (GVMEncodePlacement(corner,nil)-1) | ((uint64_t)(GVMOffsetPercent(x)+100)<<2) | ((uint64_t)(GVMOffsetPercent(y)+100)<<10) | ((uint64_t)mode<<18);
}
void GVMDecodePhonePlacement(uint64_t state,NSUInteger *corner,NSInteger *x,NSInteger *y,NSUInteger *layout) {
    NSUInteger c=1,mode=0; NSInteger dx=0,dy=0;
    if ((state>>32)==2 && ((state>>20)&4095)==0 && ((state>>2)&255)<=200 && ((state>>10)&255)<=200 && ((state>>18)&3)<=2) {
        c=state&3; dx=(NSInteger)((state>>2)&255)-100; dy=(NSInteger)((state>>10)&255)-100; mode=(state>>18)&3;
    }
    if (corner) *corner=c; if (x) *x=dx; if (y) *y=dy; if (layout) *layout=mode;
}
NSInteger GVMOffsetPercentFromPoints(id value,double dimension) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID() || !isfinite(dimension) || dimension<=0) return 0;
    return GVMOffsetPercent(@([value doubleValue]*100.0/dimension));
}
void GVMMigratePhoneOffsets(double width,double height) {
    if (!isfinite(width) || !isfinite(height) || width<=0 || height<=0) return;
    CFStringRef domain=CFSTR("com.chou.gmaphud");
    CFPreferencesAppSynchronize(domain);
    NSArray *oldKeys=@[@"phoneX",@"phoneY"], *keys=@[@"phoneXPercent",@"phoneYPercent"];
    for (NSUInteger i=0;i<2;i++) {
        id saved=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)keys[i],domain));
        if (saved) continue;
        id old=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)oldKeys[i],domain));
        NSNumber *percent=@(GVMOffsetPercentFromPoints(old,i==0 ? width : height));
        CFPreferencesSetAppValue((__bridge CFStringRef)keys[i],(__bridge CFNumberRef)percent,domain);
    }
    CFPreferencesAppSynchronize(domain);
}

const char *GVMBubbleConfigurationStateName="com.chou.gmaphud.bubble-configuration";
static NSArray *ModulePermutations(void) {
    static NSArray *permutations;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        permutations=@[@[@"speed",@"limit",@"alerts"],@[@"speed",@"alerts",@"limit"],
            @[@"limit",@"speed",@"alerts"],@[@"limit",@"alerts",@"speed"],
            @[@"alerts",@"speed",@"limit"],@[@"alerts",@"limit",@"speed"]];
    });
    return permutations;
}
NSArray<NSString *> *GVMNormalizeModuleOrder(id value,BOOL vertical) {
    if ([value isKindOfClass:NSArray.class] && [ModulePermutations() containsObject:value]) return value;
    return ModulePermutations()[vertical ? 2 : 0];
}
uint64_t GVMEncodeBubbleConfiguration(NSArray *layouts,NSArray *orders) {
    uint64_t state=1ULL<<24;
    for (NSUInteger i=0;i<3;i++) {
        id layout=i<layouts.count ? layouts[i] : NSNull.null;
        NSUInteger mode=[layout isEqual:@"horizontal"] ? 1 : [layout isEqual:@"vertical"] ? 2 : 0;
        id order=i<orders.count ? orders[i] : NSNull.null;
        NSUInteger permutation=[ModulePermutations() indexOfObject:order];
        state|=((mode<<4)|(permutation==NSNotFound ? 0 : permutation+1))<<(i*8);
    }
    return state;
}
static NSUInteger BubbleByte(uint64_t state,NSUInteger surface) {
    if (surface>2 || state>>24!=1) return 0;
    NSUInteger value=(state>>(surface*8))&255;
    return (value&15)<=6 && (value>>4)<=2 ? value : 0;
}
NSUInteger GVMDecodeBubbleLayout(uint64_t state,NSUInteger surface) { return BubbleByte(state,surface)>>4; }
NSArray<NSString *> *GVMDecodeModuleOrder(uint64_t state,NSUInteger surface,BOOL vertical) {
    NSUInteger permutation=BubbleByte(state,surface)&15;
    return permutation ? ModulePermutations()[permutation-1] : GVMNormalizeModuleOrder(nil,vertical);
}

const char *GVMOverspeedModeName="com.chou.gmaphud.overspeed.mode";
const char *GVMOverspeedLeaseName="com.chou.gmaphud.overspeed.lease";
NSUInteger GVMOverspeedMode(void) {
    static int token=-1; uint64_t state=0;
    if (token<0) notify_register_check(GVMOverspeedModeName,&token);
    if (token>=0) notify_get_state(token,&state);
    return state<=2 ? (NSUInteger)state : 0;
}
static BOOL OverspeedNumber(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value)!=CFBooleanGetTypeID() && isfinite([value doubleValue]);
}
uint64_t GVMEncodeOverspeedLease(NSDictionary *output,double now) {
    if (![output isKindOfClass:NSDictionary.class] || !isfinite(now) || now<0) return 0;
    id speed=output[@"speed"],limit=output[@"speedLimit"];
    if (![speed isKindOfClass:NSDictionary.class] || ![limit isKindOfClass:NSDictionary.class]) return 0;
    double expiry=now+1;
    for (NSDictionary *sample in @[speed,limit]) {
        if (!OverspeedNumber(sample[@"value"]) || !OverspeedNumber(sample[@"receivedAt"])) return 0;
        double received=[sample[@"receivedAt"] doubleValue];
        double value=[sample[@"value"] doubleValue];
        if (received<0 || received>now || now-received>=5 || value<0 || value>400 || floor(value)!=value) return 0;
        expiry=MIN(expiry,received+5);
    }
    if ([limit[@"value"] doubleValue]<=0 || [speed[@"value"] doubleValue]<=[limit[@"value"] doubleValue] ||
        expiry>=(double)(UINT64_MAX>>2)/1000) return 0;
    double excess=[speed[@"value"] doubleValue]-[limit[@"value"] doubleValue];
    NSUInteger level=excess<5 ? 1 : excess<10 ? 2 : 3;
    return ((uint64_t)floor(expiry*1000)<<2)|level;
}
BOOL GVMOverspeedLeaseActive(uint64_t state,double now) {
    double deadline=(double)(state>>2)/1000;
    return (state&3) && isfinite(now) && now>=0 && now<deadline && deadline-now<=1.001;
}
void GVMPublishOverspeedLease(uint64_t state) {
    static int token=-1; static uint64_t last=UINT64_MAX;
    if (token<0) notify_register_check(GVMOverspeedLeaseName,&token);
    if (token>=0 && state!=last) { notify_set_state(token,state); notify_post(GVMOverspeedLeaseName); last=state; }
}
