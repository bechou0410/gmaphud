#import <Foundation/Foundation.h>

extern const NSUInteger GVMVietMapProviderID;
NSUInteger GVMVietMapKindForImage(NSData *image);
NSUInteger GVMVietMapKindForImageDigest(NSString *hash);
NSUInteger GVMVietMapKindForAssetName(NSString *name);
NSString *GVMVietMapAssetName(NSUInteger kind);
NSArray<NSDictionary *> *GVMVietMapAlertsFromPayload(id payload);
NSDictionary *GVMVietMapAlertObservation(id payload, NSUInteger acceptedCount);

NSDictionary *GVMVietMapOverlayObservation(id payload);
// Shape of one value (such as a JSON string): field names and short codes only, never free text.
NSDictionary *GVMVietMapValueObservation(id payload);
// Bytes carried by a channel value (NSData or Flutter typed data), else nil.
NSData *GVMVietMapDataValue(id item);
// The overlay patch (first argument of updateMapOverlayData), else nil.
NSDictionary *GVMVietMapOverlayPatch(id payload);
// Whether an overlay patch carries image bytes (VietMap's lane icons travel this way).
BOOL GVMVietMapOverlayCarriesImages(id payload);
NSArray<NSDictionary *> *GVMVietMapOverlayStickyAlerts(id payload);
// The overlay's laneInfo: the lanes VietMap Live shows, in effect on the stretch being driven, one
// bitmask string per lane, left to right. nil when a partial patch has no laneInfo (they stay as they
// are); empty when there are none or they cannot be read.
NSArray<NSNumber *> *GVMVietMapOverlayLaneCodes(id payload);
// One lane's direction bitmask from its updateLaneInfo imageId, `lane_<directions>_<to follow>`:
// VietMap's direction names joined by "-" in each group. Some names hold "_" themselves
// (UTURN_LEFT, SLIGHT_RIGHT), so the id is read name by name. 0 when it cannot be read.
NSUInteger GVMVietMapLaneCodeForImage(id imageId);
// updateLaneInfo, VietMap's advance lane countdown: `{distance, laneItems:[{enabled, imageId}]}` as a
// JSON string or a dictionary. Returns {distance, items:[{code, enabled}]}, or an empty dictionary when
// there is no countdown to show: VietMap cleared it (no lanes), or it cannot be used (unreadable,
// distance missing, more than 12 lanes, or no lane direction recognised), so the panel in effect
// shows instead of a stale or blank countdown.
NSDictionary *GVMVietMapAdvanceLanes(id payload);
