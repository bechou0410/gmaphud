#import <Foundation/Foundation.h>
#include <stdint.h>

// IDs and enum values are wire contracts; append new values rather than reorder.
enum { GVMOutputSchemaVersion=1, GVMSourceVietMap=1, GVMSourceWaze=2, GVMSourceGofa=3, GVMMaximumSourceID=7 };
// Lane directions use VietMap's bitmask; only these five bits are known (odd bits never seen).
typedef NS_OPTIONS(NSUInteger, GVMLaneDirection) {
    GVMLaneStraight=1, GVMLaneRight=4, GVMLaneUTurnLeft=16, GVMLaneLeft=64, GVMLaneUTurnRight=256
};
enum { GVMLaneKnownDirections=0x155, GVMMaximumLanes=12 };
typedef NS_ENUM(NSUInteger, GVMRoadAlertType) {
    GVMRoadAlertCameraAI=1, GVMRoadAlertRestArea=2,
    GVMRoadAlertResidentialStart=3, GVMRoadAlertSpeedLimit=4,
    GVMRoadAlertNoEntry=5, GVMRoadAlertNoEntryLeft=6,
    GVMRoadAlertNoEntryRight=7, GVMRoadAlertNoLeft=8,
    GVMRoadAlertNoLeftRight=9, GVMRoadAlertNoLeftUTurn=10,
    GVMRoadAlertNoRight=11, GVMRoadAlertNoRightUTurn=12,
    GVMRoadAlertNoUTurnLeft=13, GVMRoadAlertNoUTurnRight=14,
    GVMRoadAlertNoPassingStart=15, GVMRoadAlertNoPassingEnd=16,
    GVMRoadAlertPenaltyCamera=17, GVMRoadAlertRailway=18,
    GVMRoadAlertResidentialEnd=19, GVMRoadAlertRestriction=20,
    GVMRoadAlertMandatoryRight=21, GVMRoadAlertSlowDown=22,
    GVMRoadAlertSpeedCamera=23, GVMRoadAlertStopLane=24,
    GVMRoadAlertMandatoryStraight=25, GVMRoadAlertMandatoryStraightLeft=26,
    GVMRoadAlertMandatoryStraightRight=27, GVMRoadAlertToll=28,
    GVMRoadAlertTollETC=29, GVMRoadAlertTrafficCamera=30,
    GVMRoadAlertTunnel=31, GVMRoadAlertMandatoryLeftRight=32,
    GVMRoadAlertMandatoryLeft=33, GVMRoadAlertRedLightCamera=34,
    GVMRoadAlertAccident=35,
    GVMRoadAlertAccidentMinor=36,
    GVMRoadAlertAnimal=37,
    GVMRoadAlertAssistance=38,
    GVMRoadAlertBadWeather=39,
    GVMRoadAlertBlockedLane=40,
    GVMRoadAlertBothShouldersEnding=41,
    GVMRoadAlertBusLaneCam=42,
    GVMRoadAlertClosedLaneConstruction=43,
    GVMRoadAlertClosedLaneCrash=44,
    GVMRoadAlertClosure=45,
    GVMRoadAlertCyclist=46,
    GVMRoadAlertDangerousCurves=47,
    GVMRoadAlertDangerousIntersection=48,
    GVMRoadAlertDistanceBetweenVehiclesCamera=49,
    GVMRoadAlertDummyCamera=50,
    GVMRoadAlertEmergencyVehicle=51,
    GVMRoadAlertFork=52,
    GVMRoadAlertHazard=53,
    GVMRoadAlertHazardAnimals=54,
    GVMRoadAlertHazardBrokenLight=55,
    GVMRoadAlertHazardConstruction=56,
    GVMRoadAlertHazardObjectOnRoad=57,
    GVMRoadAlertHazardPothole=58,
    GVMRoadAlertHazardRoadkill=59,
    GVMRoadAlertHazardStopped=60,
    GVMRoadAlertHazardWeatherFlood=61,
    GVMRoadAlertHazardWeatherFog=62,
    GVMRoadAlertHazardWeatherHail=63,
    GVMRoadAlertHazardWeatherIce=64,
    GVMRoadAlertHazardWeatherSnow=65,
    GVMRoadAlertHazardonroad=66,
    GVMRoadAlertHighwayCrosswalk=67,
    GVMRoadAlertHovCamera=68,
    GVMRoadAlertIntersection=69,
    GVMRoadAlertLanesMerging=70,
    GVMRoadAlertLeftLaneEnding=71,
    GVMRoadAlertLeftShoulderEnding=72,
    GVMRoadAlertMerge=73,
    GVMRoadAlertNarrowBridge=74,
    GVMRoadAlertNoiseCamera=75,
    GVMRoadAlertPhoneCamera=76,
    GVMRoadAlertPolice=77,
    GVMRoadAlertPoliceMobileCamera=78,
    GVMRoadAlertRaisedCrosswalk=79,
    GVMRoadAlertRedLightAndSpeedCamera=80,
    GVMRoadAlertRightLaneEnding=81,
    GVMRoadAlertRightShoulderEnding=82,
    GVMRoadAlertSchoolZone=83,
    GVMRoadAlertSeatbeltCamera=84,
    GVMRoadAlertSlipperyRoad=85,
    GVMRoadAlertSpeedBumps=86,
    GVMRoadAlertStopSignCamera=87,
    GVMRoadAlertTopes=88
};

// Only these documented fields leave an adapter. No coordinates or raw payloads.
// speed/speedLimit: {value: integer km/h, receivedAt: monotonic seconds}.
// alerts: {type, value: limit or null, distance: metres or null,
//          artworkID: legacy optional decoration (renderers use type/value), receivedAt}.
// lanes (optional): {distance: metres to the junction or null,
//          items: 1-12 lanes left to right, each {code: GVMLaneDirection bits, enabled: BOOL,
//          limit (optional): the lane's speed limit sign as VietMap gives it, an integer from -255 to
//          255: a limit in km/h when positive, a sign without a number when 0 or -1, a sign VietMap
//          draws grey (its meaning is not documented) when -2 or less}, receivedAt}. Unknown direction bits are
//          dropped; a lane may keep no known direction. Every lane has a limit or none does.
NSDictionary *GVMNormalizeSourceOutput(id output, NSTimeInterval now);
NSDictionary *GVMSourceOutput(NSUInteger sourceID, NSDictionary *samples,
    NSArray<NSDictionary *> *alerts, NSTimeInterval now);
BOOL GVMSourceIDValid(NSUInteger sourceID);
NSString *GVMSourceDisplayName(NSUInteger sourceID);
NSString *GVMRoadAlertName(NSUInteger type);
NSString *GVMRoadAlertIconName(NSUInteger type, NSNumber *value);

// Speed, limit, two alerts with their values, the lane header, two words of lanes, then two words of
// per-lane speed limits.
enum { GVMOutputWordCount=11 };
typedef struct { uint64_t words[GVMOutputWordCount]; } GVMOutputWords;
BOOL GVMEncodeSourceOutput(NSDictionary *output, NSTimeInterval now, GVMOutputWords *words);
NSDictionary *GVMDecodeSourceOutput(NSUInteger sourceID, GVMOutputWords words, NSTimeInterval now);
NSUInteger GVMSourceIDForSelection(uint64_t selection);
BOOL GVMOutputFrameReadable(uint64_t before, uint64_t after,
    uint64_t selectionBefore, uint64_t selectionAfter, uint64_t frameSelection,
    NSUInteger sourceID);
