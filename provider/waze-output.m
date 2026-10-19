#import "waze-output.h"
#include <math.h>
static NSUInteger ExperimentalType(NSString *icon) {
    static NSDictionary *types; static dispatch_once_t once;
    dispatch_once(&once,^{ types=@{
        @"icon_alerter_cam_bus_lane":@(GVMRoadAlertBusLaneCam),
        @"icon_alerter_cam_combo_speed_and_redlight":@(GVMRoadAlertRedLightAndSpeedCamera),
        @"icon_alerter_cam_distance_between_vehicles":@(GVMRoadAlertDistanceBetweenVehiclesCamera),
        @"icon_alerter_cam_dummy":@(GVMRoadAlertDummyCamera),
        @"icon_alerter_cam_hov":@(GVMRoadAlertHovCamera),
        @"icon_alerter_cam_noise":@(GVMRoadAlertNoiseCamera),
        @"icon_alerter_cam_phone":@(GVMRoadAlertPhoneCamera),
        @"icon_alerter_cam_seat_belt":@(GVMRoadAlertSeatbeltCamera),
        @"icon_alerter_cam_speed":@(GVMRoadAlertSpeedCamera),
        @"icon_alerter_cam_stop_sign":@(GVMRoadAlertStopSignCamera),
        @"icon_alerter_cam_stop_signe":@(GVMRoadAlertStopSignCamera),
        @"icon_alerter_railroads":@(GVMRoadAlertRailway),
        @"icon_alerter_toll_booth":@(GVMRoadAlertToll),
        @"icon_permanent_hazard_dangerous_curves":@(GVMRoadAlertDangerousCurves),
        @"icon_permanent_hazard_fork":@(GVMRoadAlertFork),
        @"icon_permanent_hazard_highway_crosswalk":@(GVMRoadAlertHighwayCrosswalk),
        @"icon_permanent_hazard_intersection":@(GVMRoadAlertIntersection),
        @"icon_permanent_hazard_lanes_merging":@(GVMRoadAlertLanesMerging),
        @"icon_permanent_hazard_left_lane_ending":@(GVMRoadAlertLeftLaneEnding),
        @"icon_permanent_hazard_left_shoulder_ending":@(GVMRoadAlertLeftShoulderEnding),
        @"icon_permanent_hazard_narrow_bridge":@(GVMRoadAlertNarrowBridge),
        @"icon_permanent_hazard_raised_crosswalk":@(GVMRoadAlertRaisedCrosswalk),
        @"icon_permanent_hazard_right_lane_ending":@(GVMRoadAlertRightLaneEnding),
        @"icon_permanent_hazard_right_shoulder_ending":@(GVMRoadAlertRightShoulderEnding),
        @"icon_permanent_hazard_school_zone":@(GVMRoadAlertSchoolZone),
        @"icon_permanent_hazard_speed_bumps":@(GVMRoadAlertSpeedBumps),
        @"icon_permanent_hazard_toll_booth":@(GVMRoadAlertToll),
        @"icon_permanent_hazard_topes":@(GVMRoadAlertTopes),
        @"icon_report_accident":@(GVMRoadAlertAccident),
        @"icon_report_accident_minor":@(GVMRoadAlertAccidentMinor),
        @"icon_report_hazard":@(GVMRoadAlertHazard),
        @"icon_report_hazard_animals":@(GVMRoadAlertHazardAnimals),
        @"icon_report_hazard_broken_light":@(GVMRoadAlertHazardBrokenLight),
        @"icon_report_hazard_construction":@(GVMRoadAlertHazardConstruction),
        @"icon_report_hazard_object":@(GVMRoadAlertHazardObjectOnRoad),
        @"icon_report_hazard_on_road":@(GVMRoadAlertHazardonroad),
        @"icon_report_hazard_pothole":@(GVMRoadAlertHazardPothole),
        @"icon_report_hazard_roadkill":@(GVMRoadAlertHazardRoadkill),
        @"icon_report_hazard_stopped":@(GVMRoadAlertHazardStopped),
        @"icon_report_hazard_vehicle_stopped":@(GVMRoadAlertHazardStopped),
        @"icon_report_hazard_weather_flood":@(GVMRoadAlertHazardWeatherFlood),
        @"icon_report_hazard_weather_fog":@(GVMRoadAlertHazardWeatherFog),
        @"icon_report_hazard_weather_hail":@(GVMRoadAlertHazardWeatherHail),
        @"icon_report_hazard_weather_ice":@(GVMRoadAlertHazardWeatherIce),
        @"icon_report_hazard_weather_slippery_road":@(GVMRoadAlertSlipperyRoad),
        @"icon_report_police":@(GVMRoadAlertPolice),
        @"icon_report_police_mobile_camera":@(GVMRoadAlertPoliceMobileCamera)
    }; });
    return [types[icon] unsignedIntegerValue];
}


static NSDictionary *LimitSample(uint64_t limit,double receivedAt) {
    int32_t kmh=(int32_t)limit;
    return ((limit>>32)&255)==1 && kmh>0 && kmh<=400 ? @{@"value":@(kmh),@"receivedAt":@(receivedAt)} : nil;
}

@implementation GVMWazeOutputStore {
    NSMutableDictionary<NSString *, NSDictionary *> *_alerts;
    NSDictionary *_samples;
    double _lastGPS;
    double _stationarySample, _stationaryTime;
}
- (instancetype)init {
    if ((self=[super init])) {
        _alerts=[NSMutableDictionary new]; _samples=@{}; _lastGPS=-1;
        _lastSampleUptime=-1; _stationarySample=-1; _stationaryTime=-1;
    }
    return self;
}
- (void)updateIdentifier:(NSString *)identifier icon:(NSString *)icon type:(NSInteger)type
                subtype:(NSInteger)subtype trait:(NSInteger)trait distance:(NSInteger)distance
                valid:(BOOL)valid passed:(BOOL)passed atUptime:(double)uptime {
    if (![identifier isKindOfClass:NSString.class] || !identifier.length || identifier.length>128 ||
        !isfinite(uptime) || uptime<0) return;
    NSDictionary *previous=_alerts[identifier];
    if (previous && [previous[@"receivedAt"] doubleValue]>uptime) return;
    // Red-light retains its measured tuple. Other exact artwork names are internal trials.
    BOOL redLight=[icon isEqual:@"icon_alerter_cam_red_light"];
    NSUInteger semantic=redLight && type==10 && subtype==1 && trait==0 ? GVMRoadAlertRedLightCamera :
        (!redLight && [icon isKindOfClass:NSString.class] ? ExperimentalType(icon) : 0);
    if (!valid || passed || !semantic || distance<0 || distance>10000) { [_alerts removeObjectForKey:identifier]; return; }
    // Bound native candidate storage independently of the two displayed slots.
    if (!_alerts[identifier] && _alerts.count>=64) {
        NSString *oldest=nil;
        for (NSString *key in _alerts)
            if (!oldest || [_alerts[key][@"receivedAt"] doubleValue]<[_alerts[oldest][@"receivedAt"] doubleValue]) oldest=key;
        [_alerts removeObjectForKey:oldest];
    }
    _alerts[identifier]=@{@"type":@(semantic), @"distance":@(distance),
        @"value":NSNull.null, @"receivedAt":@(uptime)};
}
- (void)updateSpeed:(double)speed timestamp:(double)timestamp now:(double)now
            uptime:(double)uptime optionalLimit:(uint64_t)limit {
    double age=now-timestamp;
    // A newer fix that came too late may show movement the store cannot publish.
    if (isfinite(timestamp) && isfinite(now) && timestamp>_lastGPS && age>=5) _stationarySample=-1;
    if (!isfinite(timestamp) || !isfinite(now) || !isfinite(uptime) ||
        timestamp<=_lastGPS || age<0 || age>=5 || uptime<age) return;
    _lastGPS=timestamp;
    _lastSampleUptime=uptime-age;
    NSMutableDictionary *samples=[NSMutableDictionary new];
    double kmh=speed*0.0036;
    if (isfinite(kmh) && kmh>=0 && kmh<=400)
        samples[@"speed"]=@{@"value":@(lround(kmh)),@"receivedAt":@(uptime-age)};
    BOOL stationary=isfinite(kmh) && kmh>=0 && lround(kmh)<GVMWazeStationaryKmh;
    _stationarySample=stationary ? uptime-age : -1;
    _stationaryTime=stationary ? timestamp : -1;
    samples[@"speedLimit"]=LimitSample(limit,uptime-age);
    _samples=[samples copy];
}
- (void)updateLimit:(uint64_t)limit uptime:(double)uptime {
    if (!isfinite(uptime) || uptime<0) return;
    NSMutableDictionary *samples=[_samples mutableCopy];
    samples[@"speedLimit"]=LimitSample(limit,uptime);
    _samples=[samples copy];
}
- (void)holdStationarySpeedAtUptime:(double)uptime now:(double)now {
    NSDictionary *speed=_samples[@"speed"];
    // Uptime stops while the phone sleeps, so the wall clock bounds the hold as well.
    double held=uptime-_stationarySample, elapsed=now-_stationaryTime;
    if (!speed || _stationarySample<0 || !isfinite(held) || !isfinite(elapsed) || held<0 || elapsed<0 ||
        held>=GVMWazeStationaryHoldSeconds || elapsed>=GVMWazeStationaryHoldSeconds) return;
    NSMutableDictionary *samples=[_samples mutableCopy];
    samples[@"speed"]=@{@"value":speed[@"value"],@"receivedAt":@(uptime)};
    _samples=[samples copy];
}
- (void)endStationaryHold { _stationarySample=-1; }
- (NSDictionary *)outputAtUptime:(double)uptime {
    if (!isfinite(uptime) || uptime<0) return nil;
    for (NSString *key in _alerts.allKeys) {
        double age=uptime-[_alerts[key][@"receivedAt"] doubleValue];
        if (age>=5 || age<0) [_alerts removeObjectForKey:key];
    }
    return GVMSourceOutput(GVMSourceWaze,_samples,_alerts.allValues,uptime);
}
@end
