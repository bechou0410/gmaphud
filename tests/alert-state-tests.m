#import "alert-state.h"
#import "vietmap-alert-assets.h"
#include <assert.h>
#include <math.h>
int main(int argc, const char **argv) { @autoreleasepool {
    NSDictionary *sample=@{@"provider":@1,@"kind":@2,@"distance":@200};
    uint64_t state=GVMEncodeAlert(sample,100);
    assert([GVMDecodeAlert(state,104.999) isEqual:sample]);
    assert(!GVMDecodeAlert(state,105)); assert(!GVMDecodeAlert(state,99));
    assert(GVMDecodeAlertWithin(state,105,300));
    assert(!GVMDecodeAlertWithin(state,400,300));
    assert(!GVMEncodeAlert(@{@"provider":@0,@"kind":@2},100));
    assert(!GVMEncodeAlert(@{@"provider":@1,@"kind":@2,@"distance":@10001},100));
    assert(!GVMDecodeAlert(0,100)); assert(!GVMDecodeAlert(state,NAN));
    assert(GVMVietMapAlertsFromPayload(@[]).count==0);
    NSData *unknown=[@"unknown-sign" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *raw=@{@"image":[unknown base64EncodedStringWithOptions:0],@"distance":NSNull.null,
        @"speedLimit":@60,@"latitude":@12.34,@"account":@"private-value"};
    NSDictionary *observation=GVMVietMapAlertObservation(@[raw],0);
    NSDictionary *observed=observation[@"items"][0];
    assert([observed[@"imageSHA256"] length]==64 && !observed[@"recognizedAsset"]);
    assert([observed[@"distanceState"] isEqual:@"null"] && !observed[@"distance"]);
    assert([observed[@"speedLimit"] isEqual:@60]);
    NSString *safe=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:observation options:0 error:nil] encoding:NSUTF8StringEncoding];
    assert(![safe containsString:@"private-value"] && ![safe containsString:@"latitude"] && ![safe containsString:@"image\""]);
    NSMutableArray *many=[NSMutableArray new];
    for (NSUInteger i=0;i<32;i++) [many addObject:raw];
    NSDictionary *bounded=GVMVietMapAlertObservation(many,2);
    assert([bounded[@"count"] unsignedIntegerValue]==32 && [bounded[@"items"] count]==8 && [bounded[@"truncated"] boolValue]);
    NSData *encoded=[NSJSONSerialization dataWithJSONObject:raw options:0 error:nil];
    NSString *json=[[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
    assert([GVMVietMapAlertObservation(@[json],0)[@"items"][0][@"jsonString"] boolValue]);
    assert(![GVMVietMapAlertObservation(@"private-value",0)[@"array"] boolValue]);
    NSDictionary *overlay=GVMVietMapOverlayObservation(@[@{@"stickyAlerts":@[raw],@"latitude":@12.34,
        @"parkingInfo":@{@"account":@"private-value"},
        @"laneGuidance":@[@{@"direction":@"straight",@"latitude":@1,@"userName":@"private-value"}],
        @"junctionView":@{@"image":@"private-value",@"location":@"private-value"},
        @"laneInfo":@[@"straight_right",@"Hẻm 71 private-value",@12,@YES,
            @"{\"type\":\"straight\",\"highlight\":true,\"streetName\":\"private-value\",\"image\":\"QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVphYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5ejAxMjM0NTY3ODk=\"}"]},@NO]);
    assert([overlay[@"fields"] count]==2);
    assert([overlay[@"fields"][@"stickyAlerts"][@"count"] isEqual:@1]);
    // Unknown fields are listed by name and shape only; names that could point at a place or a person are left out.
    NSArray *others=overlay[@"otherFields"];
    assert(others.count==3 && [others[0][@"key"] isEqual:@"junctionView"] && [others[0][@"keys"] isEqual:@[@"image"]]);
    assert([others[1][@"key"] isEqual:@"laneGuidance"] && [others[1][@"count"] isEqual:@1] && [others[1][@"itemKeys"] isEqual:@[@"direction"]]);
    // Short codes show how a field is encoded; free text is replaced by "?".
    assert([others[1][@"itemCodes"] isEqual:@{@"direction":@"straight"}]);
    assert([others[2][@"key"] isEqual:@"laneInfo"] && [others[2][@"itemShape"] isEqual:@"string"]);
    NSArray *laneCodes=others[2][@"codes"];
    assert(laneCodes.count==5 && [laneCodes[0] isEqual:@"straight_right"] && [laneCodes[2] isEqual:@12] && [laneCodes[3] isEqual:@YES]);
    assert([laneCodes[1] isEqual:(@{@"len":@20,@"kind":@"text"})]); // Free text: length only.
    // A JSON lane string is decoded to its field names and short codes; the image is just a length.
    assert([laneCodes[4][@"keys"] isEqual:(@[@"highlight",@"image",@"type"])]);
    assert([laneCodes[4][@"codes"][@"type"] isEqual:@"straight"] && [laneCodes[4][@"codes"][@"highlight"] isEqual:@YES]);
    assert([laneCodes[4][@"codes"][@"image"][@"kind"] isEqual:@"base64"]);
    NSDictionary *laneValue=GVMVietMapValueObservation(@"[{\"type\":\"left\",\"streetName\":\"private-value\"},\"Hẻm 71 private-value\"]");
    assert([laneValue[@"shape"] isEqual:@"string"] && [laneValue[@"value"][@"count"] isEqual:@2]);
    assert([laneValue[@"value"][@"codes"][0][@"codes"][@"type"] isEqual:@"left"] && [laneValue[@"value"][@"codes"][1][@"kind"] isEqual:@"text"]);
    // VietMap's lane message: a JSON string with the distance and a list of lane items three levels deep.
    NSDictionary *laneMessage=GVMVietMapValueObservation(@"{\"distance\":58,\"laneItems\":[{\"type\":2,\"active\":true,\"streetName\":\"private-value\"},{\"type\":\"1\",\"active\":false}]}");
    NSDictionary *items=laneMessage[@"value"][@"codes"][@"laneItems"];
    assert([laneMessage[@"value"][@"codes"][@"distance"] isEqual:@58] && [items[@"count"] isEqual:@2]);
    assert([items[@"codes"][0][@"codes"][@"type"] isEqual:@2] && [items[@"codes"][0][@"codes"][@"active"] isEqual:@YES]);
    assert([items[@"codes"][1][@"codes"][@"type"] isEqual:@"1"] && ![items[@"codes"][0][@"keys"] containsObject:@"streetName"]);
    // Images registered for CarPlay views are described by size and digest only.
    NSDictionary *image=GVMVietMapValueObservation(@{@"5":[@"abc" dataUsingEncoding:NSUTF8StringEncoding]});
    assert([image[@"value"][@"codes"][@"5"][@"bytes"] isEqual:@3]);
    assert([image[@"value"][@"codes"][@"5"][@"sha256"] isEqual:@"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"]);
    assert(GVMVietMapDataValue(@"text")==nil && GVMVietMapDataValue([NSData data]));
    // VietMap sends its lane icons inside the overlay patch, keyed by the lane code.
    NSArray *iconPatch=@[@{@"laneInfo":@[@"1",@"5"],@"5":[@"abc" dataUsingEncoding:NSUTF8StringEncoding]},@NO];
    assert(GVMVietMapOverlayCarriesImages(iconPatch) && !GVMVietMapOverlayCarriesImages(@[@{@"laneInfo":@[]},@NO]));
    NSDictionary *iconEntry=nil;
    for (NSDictionary *entry in GVMVietMapOverlayObservation(iconPatch)[@"otherFields"]) if ([entry[@"key"] isEqual:@"5"]) iconEntry=entry;
    assert([iconEntry[@"shape"] isEqual:@"data"] && [iconEntry[@"bytes"] isEqual:@3]);
    assert([iconEntry[@"sha256"] isEqual:@"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"]);
    // Single-character lane codes are kept as they are.
    assert([GVMVietMapOverlayObservation(@[@{@"laneInfo":@[@"1",@"↑",@"3"]},@NO])[@"otherFields"][0][@"codes"] isEqual:(@[@"1",@"↑",@"3"])]);
    NSString *overlayJSON=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:overlay options:0 error:nil] encoding:NSUTF8StringEncoding];
    assert(![overlayJSON containsString:@"latitude"] && ![overlayJSON containsString:@"private-value"] && ![overlayJSON containsString:@"71"]);
    NSArray *nextLimit=GVMVietMapAlertsFromPayload(@[@{@"image":@"",@"speedLimit":@80,@"distance":@200}]);
    assert(nextLimit.count==1);
    // The overlay's laneInfo: the lanes VietMap Live shows, in effect on the stretch being driven.
    assert([GVMVietMapOverlayLaneCodes(@[@{@"laneInfo":@[@"1",@"1",@"1",@"5"]},@NO]) isEqual:(@[@1,@1,@1,@5])]);
    assert([GVMVietMapOverlayLaneCodes(@[@{@"laneInfo":@[@257,@"85"]},@NO]) isEqual:(@[@257,@85])]);
    assert(GVMVietMapOverlayLaneCodes(@[@{@"speed":@40},@NO])==nil && GVMVietMapOverlayLaneCodes(@[@{@"speed":@40},@YES]).count==0);
    assert(GVMVietMapOverlayLaneCodes(@[@{@"laneInfo":NSNull.null},@NO]).count==0 && GVMVietMapOverlayLaneCodes(@[@{@"laneInfo":@[]},@NO]).count==0);
    // updateLaneInfo ids as captured on 16/10, and VietMap's names that hold "_" themselves.
    assert(GVMVietMapLaneCodeForImage(@"lane_STRAIGHT_STRAIGHT")==1 && GVMVietMapLaneCodeForImage(@"lane_RIGHT_RIGHT")==4);
    assert(GVMVietMapLaneCodeForImage(@"lane_STRAIGHT-RIGHT_STRAIGHT-RIGHT")==5 && GVMVietMapLaneCodeForImage(@"lane_STRAIGHT-RIGHT_RIGHT")==5);
    assert(GVMVietMapLaneCodeForImage(@"lane_UTURN_LEFT_UTURN_LEFT")==16 && GVMVietMapLaneCodeForImage(@"lane_STRAIGHT-UTURN_RIGHT_STRAIGHT")==257);
    assert(GVMVietMapLaneCodeForImage(@"lane_SLIGHT_LEFT-STRAIGHT_STRAIGHT")==65 && GVMVietMapLaneCodeForImage(@"lane_LEFT-RIGHT-STRAIGHT_LEFT")==69);
    assert(GVMVietMapLaneCodeForImage(@"lane_SHARP_RIGHT_NONE")==4 && GVMVietMapLaneCodeForImage(@"lane_STRAIGHT")==1);
    assert(GVMVietMapLaneCodeForImage(@"lane_NONE_NONE")==0 && GVMVietMapLaneCodeForImage(@"lane_FOO_FOO")==0 &&
        GVMVietMapLaneCodeForImage(@"lane_STRAIGHT+RIGHT_X")==0 && GVMVietMapLaneCodeForImage(@"maneuver_left")==0 &&
        GVMVietMapLaneCodeForImage(nil)==0 && GVMVietMapLaneCodeForImage(@5)==0);
    NSDictionary *advance=GVMVietMapAdvanceLanes(@"{\"distance\":166,\"laneItems\":[{\"enabled\":true,\"imageId\":\"lane_STRAIGHT_STRAIGHT\"},"
        "{\"enabled\":true,\"imageId\":\"lane_STRAIGHT_STRAIGHT\"},{\"enabled\":true,\"imageId\":\"lane_STRAIGHT_STRAIGHT\"},"
        "{\"enabled\":true,\"imageId\":\"lane_STRAIGHT-RIGHT_STRAIGHT-RIGHT\"},{\"enabled\":false,\"imageId\":\"lane_RIGHT_RIGHT\"}]}");
    assert([advance[@"distance"] isEqual:@166] && [advance[@"items"] count]==5);
    assert([[advance[@"items"] valueForKey:@"code"] isEqual:(@[@1,@1,@1,@5,@4])]);
    assert([[advance[@"items"] valueForKey:@"enabled"] isEqual:(@[@YES,@YES,@YES,@YES,@NO])]);
    assert([GVMVietMapAdvanceLanes(@{@"distance":@44.6,@"laneItems":@[@{@"imageId":@"lane_LEFT_LEFT"}]})[@"distance"] isEqual:@45]);
    assert(GVMVietMapAdvanceLanes(@"{\"distance\":0,\"laneItems\":[]}").count==0 && GVMVietMapAdvanceLanes(@{@"distance":@0}).count==0);
    // Anything that cannot be shown as a countdown leaves the panel in effect: never nil.
    assert(GVMVietMapAdvanceLanes(@"not json").count==0 && GVMVietMapAdvanceLanes(@[]).count==0 &&
        GVMVietMapAdvanceLanes(@{@"distance":@"x",@"laneItems":@[@{@"imageId":@"lane_LEFT_LEFT"}]}).count==0 &&
        GVMVietMapAdvanceLanes(@{@"distance":@(-4),@"laneItems":@[@{@"imageId":@"lane_LEFT_LEFT"}]}).count==0 &&
        GVMVietMapAdvanceLanes(@{@"laneItems":@[@{@"imageId":@"lane_LEFT_LEFT"}]}).count==0 &&
        GVMVietMapAdvanceLanes(@{@"distance":@40,@"laneItems":@[@"x"]}).count==0);
    // No direction recognised in any lane: a blank countdown would hide the readable panel.
    assert(GVMVietMapAdvanceLanes(@{@"distance":@120,@"laneItems":@[@{@"imageId":@"lane_KEEP_LEFT_KEEP_LEFT"},@{@"imageId":@"lane_NONE_NONE"}]}).count==0);
    assert([GVMVietMapAdvanceLanes(@{@"distance":@120,@"laneItems":@[@{@"imageId":@"lane_KEEP_LEFT_KEEP_LEFT"},@{@"imageId":@"lane_STRAIGHT_STRAIGHT"}]})[@"items"] count]==2);
    for (id bad in @[@[@"1",@"↑"],@[@"1",@"512"],@[@"1",@YES],@[@"-1"],@[@"1.5"],@"1"])
        assert(GVMVietMapOverlayLaneCodes(@[@{@"laneInfo":bad},@NO]).count==0);
    // updateLaneInfo (only observed) keeps its lane image ids whole in the log.
    assert([GVMVietMapValueObservation(@{@"imageId":@"lane_STRAIGHT_RIGHT_STRAIGHT_RIGHT"})[@"value"][@"codes"][@"imageId"] isEqual:@"lane_STRAIGHT_RIGHT_STRAIGHT_RIGHT"]);
    assert([GVMVietMapValueObservation(@{@"imageId":@"lane_STRAIGHT-RIGHT_STRAIGHT-RIGHT"})[@"value"][@"codes"][@"imageId"] isEqual:@"lane_STRAIGHT-RIGHT_STRAIGHT-RIGHT"]);
    assert(GVMVietMapOverlayStickyAlerts(@[@{},@NO])==nil);
    assert(GVMVietMapOverlayStickyAlerts(@[@{@"stickyAlerts":@[]},@NO]).count==0);
    assert(GVMVietMapOverlayStickyAlerts(@[@{@"stickyAlerts":NSNull.null},@NO]).count==0);
    assert(GVMVietMapOverlayStickyAlerts(@[@{@"stickyAlerts":@"invalid"},@NO])==nil);
    // Overlay signs without images (as VietMap sends them) must not clear the sticky signs.
    assert(GVMVietMapOverlayStickyAlerts(@[@{@"stickyAlerts":@[@{@"distance":@0}]},@NO])==nil);
    assert(GVMVietMapOverlayStickyAlerts(@[@{@"stickyAlerts":@[@{@"distance":@0},@{@"speedLimit":@60,@"distance":NSNull.null}]},@NO])==nil);
    NSArray *overlaySigns=GVMVietMapOverlayStickyAlerts(@[@{@"stickyAlerts":@[@{@"speedLimit":@60,@"distance":NSNull.null}]},@NO]);
    assert(overlaySigns.count==1 && overlaySigns[0][@"distance"]==NSNull.null);
    NSArray *noDistance=GVMVietMapAlertsFromPayload(@[@{@"speedLimit":@60,@"distance":NSNull.null}]);
    assert(noDistance.count==1 && noDistance[0][@"distance"]==NSNull.null);
    assert(GVMVietMapAlertsFromPayload(@[@{@"speedLimit":@60,@"distance":@"invalid"}]).count==0);
    assert([nextLimit[0][@"kind"] isEqual:@(GVMVietMapKindForAssetName(@"speed_limit_80.png"))]);
    assert([nextLimit[0][@"distance"] isEqual:@200]);
    assert(GVMVietMapAlertsFromPayload(@[@{@"image":@"",@"speedLimit":@81,@"distance":@200}]).count==0);
    assert(GVMVietMapAlertsFromPayload(@[@{@"image":@"invalid",@"speedLimit":@80,@"distance":@200}]).count==0);
    if (argc>3) {
        NSData *camera=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        NSData *speed=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];
        assert(camera && speed);
        NSUInteger cameraKind=GVMVietMapKindForAssetName(@"traffic_camera.png");
        NSUInteger speedKind=GVMVietMapKindForAssetName(@"speed_limit_60.png");
        assert(cameraKind && speedKind && cameraKind!=speedKind);
        assert(GVMVietMapKindForImageDigest(@"4d8213184ad18e2846098454a19f8aa928be279f37a2d2a38a0b2c8c6dc0622d")==cameraKind);
        assert(GVMVietMapKindForImageDigest(@"f2274ca1457d7bd91ca3af373b160d09edfdde143a313b305856112684a57c36")==speedKind);
        assert(!GVMVietMapKindForImageDigest(@"invalid"));
        assert([GVMVietMapAssetName(cameraKind) isEqual:@"traffic_camera.png"]);
        assert([GVMVietMapAssetName(speedKind) isEqual:@"speed_limit_60.png"]);
        NSArray *alerts=GVMVietMapAlertsFromPayload(@[
            @{@"image":@"",@"speedLimit":@80,@"distance":@400},
            @{@"image":@"",@"speedLimit":@60,@"distance":@200}
        ]);
        assert(alerts.count==2);
        assert([alerts[0][@"kind"] isEqual:@(speedKind)]);
        assert([alerts[0][@"distance"] isEqual:@200]);
        assert([alerts[1][@"distance"] isEqual:@400]);
        assert(!GVMVietMapKindForImage([@"unrecognized" dataUsingEncoding:NSUTF8StringEncoding]));
        NSString *assetDirectory=[NSString stringWithUTF8String:argv[3]];
        NSArray<NSString *> *names=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:assetDirectory error:nil];
        assert(names.count>=40);
        NSUInteger vietMapCount=0;
        for (NSString *name in names) {
            if (![name.pathExtension isEqualToString:@"png"]) continue;
            NSData *bytes=[NSData dataWithContentsOfFile:[assetDirectory stringByAppendingPathComponent:name]];
            assert(bytes.length>8);
            const unsigned char *png=bytes.bytes;
            assert(png[0]==0x89 && png[1]=='P' && png[2]=='N' && png[3]=='G');
            if (GVMVietMapKindForAssetName(name)>0) vietMapCount++;
            // Redesigned PNGs are display-only; they must not replace source digests.
            assert(GVMVietMapKindForImage(bytes)==0);
        }
        assert(vietMapCount==46);
    }
    puts("alert state and VietMap assets passed");
} return 0; }
