#import <Foundation/Foundation.h>
#import "speed-presentation.h"

extern const char *GVMPlacementStateName;
uint64_t GVMEncodePlacement(NSString *full, NSString *dashboard);
BOOL GVMDecodePlacement(uint64_t state, NSUInteger *full, BOOL *dashboardLeft);

extern const char *GVMSizeStateName;
extern const char *GVMSizeChangedName;
extern const char *GVMBubbleVisibilityStateName;
uint64_t GVMEncodeBubbleVisibility(id enabled,id full,id dashboard,id phone);
BOOL GVMDecodeBubbleVisibility(uint64_t state,NSUInteger surface);
BOOL GVMBubbleEnabled(NSUInteger surface);
// Bubble size per screen, in percent of its default size.
static const NSUInteger GVMSizePercentMin=50, GVMSizePercentMax=250;
NSUInteger GVMSizePercent(id value);
uint64_t GVMEncodeSizes(id full, id dashboard, id phone);
NSUInteger GVMDecodeSize(uint64_t state, NSUInteger surface);
void GVMPublishSavedSizes(void);

extern const char *GVMPhonePlacementStateName;
NSInteger GVMOffsetPercent(id value);
// The value a settings slider shows for a saved offset (signed) or size, as a float-safe double.
double GVMSliderPercent(id value,BOOL offset);
uint64_t GVMEncodePhonePlacement(NSString *corner,id x,id y,NSString *layout);
void GVMDecodePhonePlacement(uint64_t state,NSUInteger *corner,NSInteger *x,NSInteger *y,NSUInteger *layout);

NSInteger GVMOffsetPercentFromPoints(id value,double dimension);
void GVMMigratePhoneOffsets(double width,double height);

extern const char *GVMBubbleConfigurationStateName;
NSArray<NSString *> *GVMNormalizeModuleOrder(id value,BOOL vertical);
uint64_t GVMEncodeBubbleConfiguration(NSArray *layouts,NSArray *orders);
NSUInteger GVMDecodeBubbleLayout(uint64_t state,NSUInteger surface);
NSArray<NSString *> *GVMDecodeModuleOrder(uint64_t state,NSUInteger surface,BOOL vertical);

// Preference interfaceStyle: "halo" selects New UI (beta); anything else, or no value, is Classic.
extern const char *GVMInterfaceStyleName;
uint64_t GVMEncodeInterfaceStyle(id value);
GVMInterfaceStyle GVMDecodeInterfaceStyle(uint64_t state);
GVMInterfaceStyle GVMCurrentInterfaceStyle(void);
// New UI dial (preference haloDial: "limit" makes the large circle the speed limit sign and the small
// one the current speed; anything else keeps the speed dial), carried to Google Maps in one state.
extern const char *GVMPresentationOptionsName;
uint64_t GVMEncodePresentationOptions(id dial);
BOOL GVMDecodeLimitDial(uint64_t state);
uint64_t GVMCurrentPresentationOptions(void);

extern const char *GVMOverspeedModeName, *GVMOverspeedLeaseName;
NSUInteger GVMOverspeedMode(void);
uint64_t GVMEncodeOverspeedLease(NSDictionary *output,double now);
BOOL GVMOverspeedLeaseActive(uint64_t state,double now);
void GVMPublishOverspeedLease(uint64_t state);
