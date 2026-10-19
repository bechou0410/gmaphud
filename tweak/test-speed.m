#import <Foundation/Foundation.h>
#import "test-state.h"
#import "placement-state.h"
#import "alert-state.h"
#import "vietmap-alert-assets.h"
#include <notify.h>
#include <errno.h>
#include <stdlib.h>

static BOOL Number(const char *text, NSInteger *value) {
    char *end; errno = 0;
    long parsed = strtol(text, &end, 10);
    if (errno || end == text || *end) return NO;
    *value = parsed; return YES;
}
static NSDictionary *DisplayAlert(const char *text) {
    NSString *input=[NSString stringWithUTF8String:text];
    NSArray<NSString *> *parts=[input componentsSeparatedByString:@":"];
    NSString *name=@"traffic_camera.png", *distanceText=input;
    if (parts.count==2) {
        name=[parts[0] stringByAppendingString:@".png"];
        distanceText=parts[1];
    } else if (parts.count!=1) return nil;
    NSInteger distance;
    NSUInteger kind=GVMVietMapKindForAssetName(name);
    // "-" is a sign in effect, which VietMap shows without a distance.
    if (kind && parts.count==2 && [distanceText isEqual:@"-"])
        return @{@"provider":@(GVMVietMapProviderID),@"kind":@(kind),@"distance":NSNull.null};
    if (!kind || !Number(distanceText.UTF8String,&distance) || distance<0 || distance>10000) return nil;
    return @{@"provider":@(GVMVietMapProviderID),@"kind":@(kind),@"distance":@(distance)};
}
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc==3 && strcmp(argv[1],"overspeed")==0) {
            NSString *scope=[NSString stringWithUTF8String:argv[2]];
            NSUInteger mode=[scope isEqual:@"map"] ? 1 : [scope isEqual:@"screen"] ? 2 : 0;
            if (!mode && ![scope isEqual:@"off"]) return 2;
            int token=-1;
            if (notify_register_check(GVMOverspeedModeName,&token)!=NOTIFY_STATUS_OK) return 3;
            uint32_t result=notify_set_state(token,mode);
            if (result==NOTIFY_STATUS_OK) notify_post(GVMOverspeedModeName);
            notify_cancel(token); return result==NOTIFY_STATUS_OK ? 0 : 3;
        }
        if (argc==4 && strcmp(argv[1],"position")==0) {
            NSString *full=[NSString stringWithUTF8String:argv[2]], *dashboard=[NSString stringWithUTF8String:argv[3]];
            if (![@[@"top-left",@"top-right",@"bottom-left",@"bottom-right"] containsObject:full] ||
                ![@[@"left",@"right"] containsObject:dashboard]) return 2;
            int token=-1;
            if (notify_register_check(GVMPlacementStateName,&token)!=NOTIFY_STATUS_OK) return 3;
            uint32_t result=notify_set_state(token,GVMEncodePlacement(full,dashboard));
            if (result==NOTIFY_STATUS_OK) notify_post(GVMPlacementStateName);
            notify_cancel(token);
            return result==NOTIFY_STATUS_OK ? 0 : 3;
        }
        // Temporary New UI dial, like position: Settings republishes the saved choice.
        if (argc==3 && strcmp(argv[1],"options")==0) {
            NSString *dial=[NSString stringWithUTF8String:argv[2]];
            if (![@[@"speed",@"limit"] containsObject:dial]) return 2;
            int token=-1;
            if (notify_register_check(GVMPresentationOptionsName,&token)!=NOTIFY_STATUS_OK) return 3;
            uint32_t result=notify_set_state(token,GVMEncodePresentationOptions(dial));
            if (result==NOTIFY_STATUS_OK) notify_post(GVMPresentationOptionsName);
            notify_cancel(token);
            return result==NOTIFY_STATUS_OK ? 0 : 3;
        }
        // Optional test lanes, anywhere after the values: lanes=1,1,1,5,4@127, or with a speed limit
        // sign per lane: lanes=1:90,5:70 (0 or -1 a sign without a number, -2 or less a grey one).
        uint64_t laneState=0, laneLimitState=0;
        for (int i=1;i<argc;i++) {
            if (strncmp(argv[i],"lanes=",6)) continue;
            NSDictionary *lanes=GVMParseTestLanes([NSString stringWithUTF8String:argv[i]+6]);
            if (!lanes) {
                fprintf(stderr, "Use lanes=CODES[@METERS]: up to 7 VietMap lane codes such as 1,1,5,4 (x1 marks a lane not to use), each optionally :LIMIT for every lane, such as 1:90,5:70\n"); return 2;
            }
            laneState=GVMEncodeTestLanes(lanes[@"items"],lanes[@"distance"]);
            laneLimitState=GVMEncodeTestLaneLimits(lanes[@"items"]);
            for (int j=i;j<argc-1;j++) argv[j]=argv[j+1];
            argc--; break;
        }
        BOOL photo=argc>1 && strcmp(argv[argc-1],"--photo")==0;
        if (photo) argc--;
        uint64_t state = 0;
        uint64_t firstAlert = 0, secondAlert = 0;
        if (!(argc == 2 && strcmp(argv[1], "off") == 0)) {
            NSInteger speed, limit, duration;
            if ((argc != 4 && argc != 6) || !Number(argv[1], &speed) || !Number(argv[2], &limit) || !Number(argv[3], &duration) ||
                !(state = GVMEncodeTest(speed, limit, NSProcessInfo.processInfo.systemUptime, duration))) {
                fprintf(stderr, "Usage: gvm-test-speed SPEED_KMH LIMIT_KMH SECONDS [SIGN1:METERS SIGN2:METERS] [lanes=CODES[:LIMIT]@METERS], [--photo], or off; position FULL DASHBOARD; options speed|limit; overspeed off|map|screen\n"); return 2;
            }
            if (argc == 6) {
                NSDictionary *first=DisplayAlert(argv[4]), *second=DisplayAlert(argv[5]);
                NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
                if (!first || !second || !(firstAlert=GVMEncodeAlert(first,now)) ||
                    !(secondAlert=GVMEncodeAlert(second,now))) {
                    fprintf(stderr, "Use VietMap sign asset names and distances 0..10000 m (- for a sign in effect); bare numbers mean traffic_camera\n"); return 2;
                }
            }
        }
        int photoToken=-1;
        if (notify_register_check("com.chou.googlemaps.vietmap.test.photo",&photoToken)!=NOTIFY_STATUS_OK) return 3;
        uint32_t photoResult=notify_set_state(photoToken,photo ? state : 0);
        notify_cancel(photoToken);
        if (photoResult!=NOTIFY_STATUS_OK) return 3;
        if (!state) { laneState=0; laneLimitState=0; }
        int laneToken=-1, laneLimitToken=-1;
        if (notify_register_check(GVMTestLaneStateName,&laneToken)!=NOTIFY_STATUS_OK) return 3;
        uint32_t laneResult=notify_set_state(laneToken,laneState);
        notify_cancel(laneToken);
        if (laneResult!=NOTIFY_STATUS_OK) return 3;
        if (notify_register_check(GVMTestLaneLimitStateName,&laneLimitToken)!=NOTIFY_STATUS_OK) return 3;
        laneResult=notify_set_state(laneLimitToken,laneLimitState);
        notify_cancel(laneLimitToken);
        if (laneResult!=NOTIFY_STATUS_OK) return 3;
        int token, firstToken, secondToken;
        if (notify_register_check(GVMTestStateName, &token) != NOTIFY_STATUS_OK) return 3;
        if (notify_register_check(GVMTestFirstAlertStateName, &firstToken) != NOTIFY_STATUS_OK) {
            notify_cancel(token); return 3;
        }
        if (notify_register_check(GVMTestSecondAlertStateName, &secondToken) != NOTIFY_STATUS_OK) {
            notify_cancel(firstToken); notify_cancel(token); return 3;
        }
        uint32_t result = notify_set_state(firstToken,firstAlert);
        if (result == NOTIFY_STATUS_OK) result = notify_set_state(secondToken,secondAlert);
        if (result == NOTIFY_STATUS_OK) result = notify_set_state(token,state);
        if (result == NOTIFY_STATUS_OK) {
            notify_post(GVMTestFirstAlertStateName);
            notify_post(GVMTestSecondAlertStateName);
            notify_post(GVMTestStateName);
        }
        notify_cancel(secondToken); notify_cancel(firstToken); notify_cancel(token);
        if (result != NOTIFY_STATUS_OK) { fprintf(stderr, "Test publication refused\n"); return 3; }
        printf(state ? "TEST active on Google CarPlay; display values expire automatically\n" : "TEST off; live VietMap restored\n");
        return 0;
    }
}
