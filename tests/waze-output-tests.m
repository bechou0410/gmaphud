#import <Foundation/Foundation.h>
#import "waze-output.h"
#include <math.h>
static void Require(BOOL ok,NSString *message) { if (!ok) { NSLog(@"FAIL %@",message); exit(1); } }
static void Camera(GVMWazeOutputStore *s,NSString *key,NSInteger meters,BOOL valid,BOOL passed,double time) {
    [s updateIdentifier:key icon:@"icon_alerter_cam_red_light" type:10 subtype:1 trait:0
        distance:meters valid:valid passed:passed atUptime:time];
}
int main(void) { @autoreleasepool {
    GVMWazeOutputStore *store=[GVMWazeOutputStore new];
    Camera(store,@"A",500,YES,NO,100); Camera(store,@"B",300,YES,NO,101);
    NSDictionary *output=[store outputAtUptime:101];
    Require([output[@"sourceID"] isEqual:@2],@"Waze owns its envelope");
    Require([output[@"alerts"] count]==2 && [output[@"alerts"][0][@"distance"] isEqual:@300],@"nearest two cameras");
    Require([output[@"alerts"][0][@"type"] isEqual:@(GVMRoadAlertRedLightCamera)],@"red light is not AI camera");
    Camera(store,@"B",0,NO,YES,102);
    Require([[store outputAtUptime:102][@"alerts"] count]==1,@"pass clears only its identity");
    Camera(store,@"A",200,YES,NO,99);
    Require([[store outputAtUptime:104][@"alerts"][0][@"distance"] isEqual:@500],@"late callback cannot replace newer sample");
    Require([[store outputAtUptime:105][@"alerts"] count]==0,@"polling does not renew TTL");
    Camera(store,@"A",601,YES,NO,106);
    Require([[store outputAtUptime:106][@"alerts"] count]==1,@"valid native descriptor is available before UI trigger distance");
    Camera(store,@"A",-1,NO,YES,106);
    [store updateIdentifier:@"U" icon:@"icon_alerter_cam_speed" type:10 subtype:1 trait:0 distance:10 valid:YES passed:NO atUptime:106];
    [store updateIdentifier:@"V" icon:@"icon_alerter_cam_red_light" type:10 subtype:2 trait:0 distance:10 valid:YES passed:NO atUptime:106];
        Require([[store outputAtUptime:106][@"alerts"] count]==1 &&
        [[store outputAtUptime:106][@"alerts"][0][@"type"] isEqual:@(GVMRoadAlertSpeedCamera)],@"exact speed camera artwork maps in internal trial; unmeasured red-light tuple rejected");
    [store updateIdentifier:@"U" icon:@"icon_alerter_cam_speed" type:10 subtype:1 trait:0 distance:0 valid:NO passed:YES atUptime:107];
    [store updateIdentifier:@"X" icon:@"unknown_camera_speed" type:10 subtype:1 trait:0 distance:100 valid:YES passed:NO atUptime:107];
    Require([[store outputAtUptime:107][@"alerts"] count]==0,@"unknown icon does not guess camera semantics");
    GVMWazeOutputStore *trial=[GVMWazeOutputStore new];
    [trial updateIdentifier:@"phone" icon:@"icon_alerter_cam_phone" type:10 subtype:5 trait:0 distance:350 valid:YES passed:NO atUptime:100];
    [trial updateIdentifier:@"pothole" icon:@"icon_report_hazard_pothole" type:1 subtype:2 trait:0 distance:50 valid:YES passed:NO atUptime:100];
    NSDictionary *trialOutput=[trial outputAtUptime:100];
    Require([trialOutput[@"alerts"] count]==2 && [GVMRoadAlertName([trialOutput[@"alerts"][0][@"type"] unsignedIntegerValue]) isEqual:@"hazard-pothole"],@"exact hazard artwork keeps semantic and distance");
    Require([[trial outputAtUptime:105][@"alerts"] count]==0,@"experimental icons cannot keep stale warnings alive");
    [trial updateIdentifier:@"hidden" icon:@"icon_alerter_cam_phone_hidden" type:10 subtype:5 trait:0 distance:50 valid:YES passed:NO atUptime:106];
    Require([[trial outputAtUptime:106][@"alerts"] count]==0,@"hidden variant is not assumed to be an active warning");
    [store updateSpeed:10000 timestamp:1000 now:1001 uptime:200 optionalLimit:((uint64_t)1<<32)|60];
    output=[store outputAtUptime:200];
    Require([output[@"speed"][@"value"] isEqual:@36] && [output[@"speedLimit"][@"value"] isEqual:@60],@"native units and optional limit");
    [store updateSpeed:20000 timestamp:1000 now:1003 uptime:202 optionalLimit:0];
    Require([[store outputAtUptime:202][@"speed"][@"value"] isEqual:@36],@"duplicate GPS does not refresh");
    Camera(store,@"C",100,YES,NO,203);
    output=[store outputAtUptime:204];
    Require(!output[@"speed"] && !output[@"speedLimit"] && [output[@"alerts"] count]==1,@"fields expire independently");
    [store updateSpeed:0 timestamp:1005 now:1005 uptime:204 optionalLimit:0];
    output=[store outputAtUptime:204];
    Require([output[@"speed"][@"value"] isEqual:@0] && !output[@"speedLimit"],@"zero speed and absent limit are distinct");
    [store updateSpeed:999 timestamp:1010 now:1006 uptime:205 optionalLimit:0];
    Require([[store outputAtUptime:205][@"speed"][@"value"] isEqual:@0],@"future GPS rejected");
    GVMWazeOutputStore *held=[GVMWazeOutputStore new];
    [held updateSpeed:10000 timestamp:1000 now:1000 uptime:300 optionalLimit:((uint64_t)1<<32)|50];
    [held updateLimit:((uint64_t)1<<32)|50 uptime:308];
    NSDictionary *heldOutput=[held outputAtUptime:308];
    Require(!heldOutput[@"speed"] && [heldOutput[@"speedLimit"][@"value"] isEqual:@50],@"live native limit holds without GPS; speed still expires");
    [held updateLimit:0 uptime:309];
    Require(![held outputAtUptime:309][@"speedLimit"],@"live native read without a limit clears it");
    [held updateLimit:((uint64_t)1<<32)|50 uptime:NAN];
    Require(![held outputAtUptime:309][@"speedLimit"],@"invalid read time is ignored");
    // A stationary speed is held while GPS is silent; uptime and the wall clock both bound it.
    GVMWazeOutputStore *still=[GVMWazeOutputStore new];
    Require(still.lastSampleUptime==-1,@"no GPS sample yet");
    [still updateSpeed:500 timestamp:2000 now:2001 uptime:400 optionalLimit:((uint64_t)1<<32)|50];
    Require(still.lastSampleUptime==399,@"the sample keeps its own receive time");
    [still holdStationarySpeedAtUptime:430 now:2031];
    Require([[still outputAtUptime:434][@"speed"][@"value"] isEqual:@2] && still.lastSampleUptime==399,
        @"a stationary speed is held while GPS is silent, without counting as a GPS sample");
    [still holdStationarySpeedAtUptime:998 now:2599];
    Require([[still outputAtUptime:1002][@"speed"][@"value"] isEqual:@2],@"the hold lasts until ten minutes after the sample");
    [still holdStationarySpeedAtUptime:999 now:2599.5];
    Require(![still outputAtUptime:1003][@"speed"],@"ten minutes after the sample the speed lapses");
    [still updateSpeed:0 timestamp:2700 now:2700 uptime:1100 optionalLimit:0];
    [still holdStationarySpeedAtUptime:1101 now:3300];
    Require(![still outputAtUptime:1105][@"speed"],@"ten minutes asleep end the hold although uptime barely moved");
    [still updateSpeed:0 timestamp:2710 now:2710 uptime:1110 optionalLimit:0];
    [still holdStationarySpeedAtUptime:NAN now:2711];
    [still holdStationarySpeedAtUptime:1111 now:NAN];
    [still holdStationarySpeedAtUptime:1100 now:2712];
    Require([[still outputAtUptime:1114][@"speed"][@"value"] isEqual:@0],@"an invalid or earlier hold time leaves the sample as it was");
    [still holdStationarySpeedAtUptime:1112 now:2700];
    Require(![still outputAtUptime:1115][@"speed"],@"a wall clock before the sample renews nothing");
    [still updateSpeed:0 timestamp:2720 now:2720 uptime:1120 optionalLimit:0];
    [still endStationaryHold];
    [still holdStationarySpeedAtUptime:1124 now:2724];
    Require(![still outputAtUptime:1125][@"speed"],@"a stopped GPS run ends the hold");
    [still updateSpeed:0 timestamp:2730 now:2730 uptime:1130 optionalLimit:0];
    [still updateSpeed:13889 timestamp:2731 now:2737 uptime:1137 optionalLimit:0];
    [still holdStationarySpeedAtUptime:1138 now:2738];
    Require(![still outputAtUptime:1138][@"speed"] && still.lastSampleUptime==1130,@"a newer sample that came late ends the hold");
    [still updateSpeed:0 timestamp:2740 now:2740 uptime:1140 optionalLimit:0];
    [still updateSpeed:-1 timestamp:2741 now:2741 uptime:1141 optionalLimit:0];
    [still holdStationarySpeedAtUptime:1142 now:2742];
    Require(![still outputAtUptime:1142][@"speed"],@"an invalid speed after a stationary one is neither published nor held");
    [still updateSpeed:16667 timestamp:2750 now:2750 uptime:1150 optionalLimit:0];
    [still holdStationarySpeedAtUptime:1154 now:2754];
    Require(![still outputAtUptime:1155][@"speed"],@"a moving speed is not held");
    [still updateSpeed:700 timestamp:2760 now:2760 uptime:1160 optionalLimit:0];
    [still holdStationarySpeedAtUptime:1164 now:2764];
    Require(![still outputAtUptime:1165][@"speed"],@"a speed shown as 3 km/h is not held");
    GVMWazeOutputStore *early=[GVMWazeOutputStore new];
    [early updateSpeed:16667 timestamp:100 now:100 uptime:10 optionalLimit:0];
    [early holdStationarySpeedAtUptime:12 now:102];
    Require(![early outputAtUptime:15][@"speed"],@"soon after boot a moving speed is not held either");
    GVMOutputWords words;
    Require(GVMEncodeSourceOutput(output,204,&words),@"Waze encodes into shared wire");
    NSDictionary *decoded=GVMDecodeSourceOutput(2,words,204);
    Require([decoded[@"alerts"][0][@"type"] isEqual:@34],@"red light survives wire round trip");
    Require([GVMSourceDisplayName(2) isEqual:@"Waze"],@"source identity");
    puts("waze-output tests passed");
} return 0; }
