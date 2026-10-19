#import "source-output.h"
#import "vietmap-output.h"
#import "vietmap-alert-assets.h"
#import "nav-source.h"
#import "alert-state.h"
#include <math.h>

static void Require(BOOL condition, NSString *name) {
    if (!condition) { fprintf(stderr,"FAIL: %s\n",name.UTF8String); exit(1); }
}
static NSDictionary *Sample(id value,double time) { return @{@"value":value,@"receivedAt":@(time)}; }
static NSDictionary *Alert(NSUInteger type,id value,id distance,double time) {
    return @{@"type":@(type),@"value":value ?: NSNull.null,@"distance":distance ?: NSNull.null,@"receivedAt":@(time)};
}
int main(int argc,const char **argv) { @autoreleasepool {
    NSDictionary *gofa=GVMSourceOutput(GVMSourceGofa,@{@"speedLimit":Sample(@70,100)},@[Alert(GVMRoadAlertRedLightCamera,nil,@390,100)],100);
    GVMOutputWords gofaWords;
    Require([GVMSourceDisplayName(GVMSourceGofa) isEqual:@"GOFA"],@"GOFA source identity");
    Require(GVMEncodeSourceOutput(gofa,100,&gofaWords),@"GOFA envelope encodes");
    Require([GVMDecodeSourceOutput(GVMSourceGofa,gofaWords,100) isEqual:gofa],@"GOFA canonical fields round trip");
    Require([GVMDecodeSourceOutput(GVMSourceWaze,gofaWords,100)[@"alerts"] count]==0,@"GOFA warnings do not decode under Waze");
    Require([GVMDecodeSourceOutput(GVMSourceGofa,gofaWords,105)[@"alerts"] count]==0,@"GOFA warnings expire at five seconds");
    NSDictionary *samples=@{@"speed":Sample(@0,100),@"speedLimit":Sample(@50,102)};
    NSDictionary *output=GVMSourceOutput(1,samples,@[Alert(GVMRoadAlertSpeedLimit,@80,@200,101),Alert(GVMRoadAlertTrafficCamera,nil,@400,102)],103);
    GVMOutputWords words;
    Require(GVMEncodeSourceOutput(output,103,&words),@"common envelope encodes");
    Require([GVMDecodeSourceOutput(1,words,103) isEqual:output],@"all canonical fields round trip");
    NSDictionary *expired=GVMDecodeSourceOutput(1,words,105);
    Require(!expired[@"speed"] && [expired[@"speedLimit"][@"value"] isEqual:@50] && [expired[@"alerts"] count]==2,@"each field retains its own age");
    Require([GVMDecodeSourceOutput(1,words,106)[@"alerts"] count]==1,@"alerts expire independently");
    Require([GVMDecodeSourceOutput(1,words,107)[@"alerts"] count]==0,@"five second expiry");
    Require(!GVMDecodeSourceOutput(1,words,99)[@"speedLimit"],@"future values unavailable");
    Require(!GVMSourceOutput(0,samples,@[],103) && !GVMSourceOutput(8,samples,@[],103),@"source range enforced");
    Require(!GVMSourceOutput(1,(id)@[],@[],103),@"malformed sample container rejected");
    for (id value in @[@YES,@(-1),@401,@1.5,@(NAN),@(INFINITY),@"50",NSNull.null]) {
        Require(!GVMSourceOutput(1,@{@"speed":Sample(value,100)},@[],101)[@"speed"],@"invalid speed omitted");
    }
    Require(!GVMSourceOutput(1,@{@"speedLimit":Sample(@0,100)},@[],100)[@"speedLimit"],@"zero limit means unavailable");
    Require(GVMSourceOutput(1,@{@"speed":Sample(@400,100)},@[],100)[@"speed"],@"maximum speed accepted");
    Require(!GVMSourceOutput(1,nil,@[],NAN),@"invalid clock rejects envelope");
    NSMutableDictionary *bad=[output mutableCopy];
    for (id version in @[@2,@YES,@"1",NSNull.null]) {
        bad[@"schemaVersion"]=version;
        Require(!GVMNormalizeSourceOutput(bad,103),@"unknown/malformed schema rejected");
    }
    bad=[output mutableCopy]; bad[@"sourceID"]=@YES;
    Require(!GVMNormalizeSourceOutput(bad,103),@"boolean source rejected");
    bad=[output mutableCopy]; bad[@"alerts"]=NSNull.null;
    Require(!GVMNormalizeSourceOutput(bad,103),@"alert container required");
    NSMutableArray *large=[NSMutableArray new];
    for (NSUInteger i=0;i<65;i++) [large addObject:Alert(1,nil,@1,100)];
    Require(!GVMSourceOutput(1,nil,large,100),@"bounded input");
    for (id time in @[@YES,@(NAN),@(-1),@101,@95,@"100"]) {
        Require(!GVMSourceOutput(1,@{@"speed":@{@"value":@42,@"receivedAt":time}},@[],100)[@"speed"],@"invalid or expired sample time omitted");
    }
    for (id distance in @[@YES,@(-1),@10001,@1.5,@"200"]) {
        Require([GVMSourceOutput(1,nil,@[Alert(1,nil,distance,100)],100)[@"alerts"] count]==0,@"invalid distance omitted");
    }
    for (id value in @[@0,@401,@YES,@1.5,NSNull.null]) {
        Require([GVMSourceOutput(1,nil,@[Alert(4,value,@200,100)],100)[@"alerts"] count]==0,@"invalid upcoming limit omitted");
    }
    Require([GVMSourceOutput(1,nil,@[Alert(1,@80,@200,100)],100)[@"alerts"] count]==0,@"value only allowed for speed-limit alert");
    for (NSUInteger value=1;value<=400;value++) {
        NSDictionary *arbitrary=GVMSourceOutput(1,nil,@[Alert(4,@(value),nil,100)],100);
        Require(GVMEncodeSourceOutput(arbitrary,100,&words),@"upcoming limit independent of artwork");
        Require([GVMDecodeSourceOutput(1,words,100)[@"alerts"][0][@"value"] isEqual:@(value)],@"all integer upcoming limits survive transport");
    }
    NSDictionary *ordered=GVMSourceOutput(1,nil,@[Alert(1,nil,nil,100),Alert(4,@80,@400,100),Alert(30,nil,@200,100),Alert(30,nil,@200,101)],102);
    NSArray *alerts=ordered[@"alerts"];
    Require(alerts.count==2 && [alerts[0][@"type"] isEqual:@30] && [alerts[0][@"receivedAt"] isEqual:@101] && [alerts[1][@"value"] isEqual:@80],@"nearest two semantic alerts, duplicates prefer latest");
    NSMutableDictionary *raw=[output mutableCopy]; raw[@"coordinates"]=@[@1,@2];
    raw[@"speed"]=@{@"value":@42,@"receivedAt":@100,@"raw":@"private"};
    NSDictionary *clean=GVMNormalizeSourceOutput(raw,103);
    Require(!clean[@"coordinates"] && !clean[@"speed"][@"raw"],@"adapter extras do not leave boundary");

    for (NSUInteger kind=1;kind<=46;kind++) {
        NSDictionary *legacy=@{@"provider":@1,@"kind":@(kind),@"distance":@200};
        NSDictionary *mapped=GVMVietMapOutputAlert(legacy,100);
        Require(mapped && GVMRoadAlertName([mapped[@"type"] unsignedIntegerValue]),@"every VietMap asset maps to a semantic type");
        NSDictionary *canonical=GVMVietMapOutput(nil,@[@{@"sample":legacy,@"receivedAt":@100}],100);
        Require([canonical[@"alerts"] count]==1 && [canonical[@"alerts"][0][@"artworkID"] isEqual:@0],@"adapter uses common semantic artwork");
    }
    Require([GVMRoadAlertIconName(GVMRoadAlertSpeedLimit,@60) isEqual:@"speed_limit_60.png"],@"current and upcoming limits share an icon");
    Require(!GVMRoadAlertIconName(GVMRoadAlertSpeedLimit,@65),@"unavailable numeric icon uses fallback");
    Require(!GVMRoadAlertIconName(GVMRoadAlertSpeedLimit,@YES),@"boolean limit is not artwork");
    if (argc>1) {
        NSString *directory=[NSString stringWithUTF8String:argv[1]];
        for (NSUInteger type=1;type<=GVMRoadAlertMandatoryLeft;type++) {
            NSString *name=GVMRoadAlertIconName(type,type==GVMRoadAlertSpeedLimit ? @60 : nil);
            Require(name.length && [[NSFileManager defaultManager] fileExistsAtPath:[directory stringByAppendingPathComponent:name]],@"every semantic type has shared artwork");
        }
        for (NSUInteger limit=10;limit<=120;limit+=10)
            Require([[NSFileManager defaultManager] fileExistsAtPath:[directory stringByAppendingPathComponent:GVMRoadAlertIconName(GVMRoadAlertSpeedLimit,@(limit))]],@"all supported speed icon files exist");
    }
    for (NSUInteger type=GVMRoadAlertRedLightCamera;type<=88;type++) {
        NSDictionary *trial=GVMSourceOutput(GVMSourceWaze,nil,@[Alert(type,nil,@250,100)],100);
        Require(GVMEncodeSourceOutput(trial,100,&words),@"trial semantic encoded");
        Require([GVMDecodeSourceOutput(GVMSourceWaze,words,100)[@"alerts"][0][@"type"] unsignedIntegerValue]==type,@"trial semantic survives wire roundtrip");
        Require(GVMRoadAlertName(type).length && GVMRoadAlertIconName(type,nil).length,@"trial semantic has name and artwork");
        if (argc>1) Require([[NSFileManager defaultManager] fileExistsAtPath:[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:GVMRoadAlertIconName(type,nil)]],@"designed Waze artwork exists for every mapped type");
    }
    NSUInteger camera=GVMVietMapKindForAssetName(@"speed_limit_camera.png"), next=GVMVietMapKindForAssetName(@"speed_limit_80.png");
    Require([GVMVietMapOutputAlert(@{@"provider":@1,@"kind":@(camera)},100)[@"type"] isEqual:@(GVMRoadAlertSpeedCamera)],@"speed camera distinct from speed limit");
    Require([GVMVietMapOutputAlert(@{@"provider":@1,@"kind":@(next)},100)[@"value"] isEqual:@80],@"next limit has semantic numeric value");
    Require(!GVMVietMapOutputAlert(@{@"provider":@2,@"kind":@(next)},100),@"adapter rejects foreign source");
    Require(!GVMVietMapOutputAlert(@{@"provider":@1,@"kind":@YES},100),@"adapter rejects boolean kind");
    Require(!GVMVietMapOutputAlert(@{@"provider":@1,@"kind":@(NAN)},100),@"adapter rejects nonfinite kind");
    Require([GVMVietMapOutput(nil,@[@{@"sample":@{@"provider":@1,@"kind":@(next)},@"receivedAt":@YES}],1)[@"alerts"] count]==0,@"adapter does not coerce boolean timestamp");
    Require([GVMVietMapOutput(nil,(id)@[NSNull.null],100)[@"alerts"] count]==0,@"malformed alert entry ignored");
    // VietMap sends signs in effect (sticky) with distance 0; they must not read "0 m".
    NSUInteger noPassing=GVMVietMapKindForAssetName(@"no_passing_in.png"), forty=GVMVietMapKindForAssetName(@"speed_limit_40.png");
    NSDictionary *sticky=@{@"sample":@{@"provider":@1,@"kind":@(noPassing),@"distance":@0},@"receivedAt":@100,@"active":@YES};
    NSArray *inEffect=GVMVietMapOutput(nil,@[sticky],100)[@"alerts"];
    Require(inEffect.count==1 && inEffect[0][@"distance"]==NSNull.null,@"sign in effect carries no distance");
    Require(GVMEncodeSourceOutput(GVMVietMapOutput(nil,@[sticky],100),100,&words) &&
        GVMDecodeSourceOutput(1,words,100)[@"alerts"][0][@"distance"]==NSNull.null,@"sign in effect survives the wire without distance");
    NSArray *ahead=@[@{@"sample":@{@"provider":@1,@"kind":@(next),@"distance":@72},@"receivedAt":@100},
        @{@"sample":@{@"provider":@1,@"kind":@(forty),@"distance":@180},@"receivedAt":@100}];
    NSArray *full=GVMVietMapOutput(nil,[ahead arrayByAddingObject:sticky],100)[@"alerts"];
    Require(full.count==2 && [full[0][@"distance"] isEqual:@72] && [full[1][@"distance"] isEqual:@180],@"upcoming signs take both places first");
    NSArray *mixed=GVMVietMapOutput(nil,@[ahead[0],sticky],100)[@"alerts"];
    Require(mixed.count==2 && [mixed[0][@"distance"] isEqual:@72] && [mixed[1][@"type"] isEqual:@(GVMRoadAlertNoPassingStart)] &&
        mixed[1][@"distance"]==NSNull.null,@"sign in effect fills a free place after upcoming signs");
    NSDictionary *again=@{@"sample":@{@"provider":@1,@"kind":@(noPassing),@"distance":@40},@"receivedAt":@100};
    NSArray *once=GVMVietMapOutput(nil,@[again,sticky],100)[@"alerts"];
    Require(once.count==1 && [once[0][@"distance"] isEqual:@40],@"a sign both upcoming and in effect shows once with its distance");
    Require([GVMVietMapOutput(nil,@[@{@"sample":@{@"provider":@1,@"kind":@(noPassing),@"distance":@0},@"receivedAt":@100}],100)[@"alerts"][0][@"distance"] isEqual:@0],@"an upcoming sign at the car keeps its distance");
    VMNavSource *vm=[VMNavSource new];
    [vm applyArguments:@[@{@"speed":@42},@NO] receivedAt:100];
    [vm applyMainSpeedLimit:@50 receivedAt:101];
    NSDictionary *migrated=GVMVietMapOutput([vm freshSamplesAtUptime:102],@[@{@"sample":@{@"provider":@1,@"kind":@(next),@"distance":@212},@"receivedAt":@101}],102);
    Require(GVMEncodeSourceOutput(migrated,102,&words),@"real VietMap source methods migrate through envelope");
    NSDictionary *decoded=GVMDecodeSourceOutput(1,words,102);
    Require([decoded[@"speed"][@"value"] isEqual:@42] && [decoded[@"speedLimit"][@"value"] isEqual:@50] && [decoded[@"alerts"][0][@"value"] isEqual:@80],@"actual source speeds and alerts delivered together");
    [vm applyMainSpeedLimit:@0 receivedAt:103];
    Require(!GVMVietMapOutput([vm freshSamplesAtUptime:103],@[],103)[@"speedLimit"],@"explicit limit invalidation preserved");
    Require([GVMVietMapOutput(nil,@[],103)[@"alerts"] count]==0,@"empty alert list clears");

    words.words[2]=GVMEncodeAlert(@{@"provider":@2,@"kind":@30,@"distance":@200},100); words.words[3]=0; words.words[4]=0;
    Require([GVMDecodeSourceOutput(1,words,100)[@"alerts"] count]==0,@"foreign source alert rejected by codec");
    words.words[2]=GVMEncodeAlert(@{@"provider":@1,@"kind":@4,@"distance":@200},100); words.words[3]=(1ULL<<17)|512|80;
    Require([GVMDecodeSourceOutput(1,words,100)[@"alerts"] count]==0,@"invalid parameter bits rejected");
    Require(GVMOutputFrameReadable(513,513,9,9,9,1),@"committed selected frame accepted");
    Require(!GVMOutputFrameReadable(257,257,9,9,9,1),@"odd write rejected");
    Require(!GVMOutputFrameReadable(513,1025,9,9,9,1),@"interleaved writer rejected");
    Require(!GVMOutputFrameReadable(513,513,9,17,9,1),@"selection changed during read rejected");
    Require(!GVMOutputFrameReadable(513,513,17,17,9,1),@"pre-switch frame rejected");
    Require(!GVMOutputFrameReadable(514,514,9,9,9,1),@"future wire schema rejected");
    Require(!GVMOutputFrameReadable(513,513,10,10,10,1),@"source mismatch rejected");
    Require(!GVMOutputFrameReadable(1,1,9,9,9,1),@"uncommitted frame rejected");

    // VietMap lanes are the ones VietMap Live shows (its overlay's laneInfo): in effect where they show,
    // with no distance, kept as they stand and published with the publication time.
    NSDictionary *vmLanes=GVMVietMapLaneSample(nil,@[@1,@1,@1,@5,@4],nil,101);
    Require(vmLanes[@"distance"]==NSNull.null && [vmLanes[@"items"][3] isEqual:(@{@"code":@5,@"enabled":@YES})] && [vmLanes[@"receivedAt"] isEqual:@101],@"VietMap lanes are in effect, without a distance");
    Require(!GVMVietMapLaneSample(nil,@[],nil,101) && !GVMVietMapLaneSample(nil,nil,nil,101),@"no lanes shown, no lanes");
    Require([GVMVietMapLaneSample(nil,@[@1,@5],nil,400)[@"receivedAt"] isEqual:@400],@"lanes VietMap still shows stay fresh while it publishes");
    Require(!GVMSourceOutput(1,@{@"lanes":GVMVietMapLaneSample(nil,@[@1,@5],nil,100)},@[],105)[@"lanes"],@"lanes expire when VietMap Live stops publishing");
    // Its advance countdown shows the next junction's lanes early, with their distance, over the panel in effect.
    NSDictionary *countdown=@{@"distance":@166,@"items":@[@{@"code":@1,@"enabled":@YES},@{@"code":@4,@"enabled":@NO}]};
    NSDictionary *early=GVMVietMapLaneSample(countdown,@[@1,@1,@5],@[@90,@70,@60],120);
    Require([early[@"distance"] isEqual:@166] && [early[@"items"] isEqual:countdown[@"items"]] && [early[@"receivedAt"] isEqual:@120],@"advance lanes show with their distance");
    Require(GVMVietMapLaneSample(@{@"distance":@40,@"items":@[]},@[@1,@5],nil,120)[@"distance"]==NSNull.null,@"an empty countdown falls back to the panel in effect");
    Require([GVMSourceOutput(1,@{@"lanes":early},@[],121)[@"lanes"][@"distance"] isEqual:@166],@"advance lanes pass the output contract");
    // Its per-lane speed limits go under the lanes in effect when they count the same lanes, or alone.
    NSDictionary *withLimits=GVMVietMapLaneSample(nil,@[@1,@1],@[@90,@70],101);
    Require([[withLimits[@"items"] valueForKey:@"limit"] isEqual:@[@90,@70]] && [withLimits[@"items"][1][@"code"] isEqual:@1],@"limits go under the arrows");
    Require(!GVMVietMapLaneSample(nil,@[@1,@1,@5],@[@90,@70],101)[@"items"][0][@"limit"],@"limits for another lane count are left out");
    NSDictionary *alone=GVMVietMapLaneSample(nil,@[],@[@90,@70],101);
    Require([alone[@"items"] isEqual:(@[@{@"code":@0,@"enabled":@YES,@"limit":@90},@{@"code":@0,@"enabled":@YES,@"limit":@70}])] &&
        alone[@"distance"]==NSNull.null,@"limits stand alone when there are no arrows");
    Require([GVMVietMapLaneSample(nil,nil,@[@-60],101)[@"items"][0][@"limit"] isEqual:@-60] && !GVMVietMapLaneSample(nil,nil,@[],101),@"dimmed limits pass; no limits and no arrows, no lanes");
    Require(GVMEncodeSourceOutput(GVMVietMapOutput(@{@"lanes":withLimits},@[],101),101,&words) &&
        [[GVMDecodeSourceOutput(1,words,101)[@"lanes"][@"items"] valueForKey:@"limit"] isEqual:@[@90,@70]],@"VietMap lane limits reach the wire");
    NSDictionary *vmOutput=GVMVietMapOutput(@{@"lanes":vmLanes},@[],101);
    Require([vmOutput[@"lanes"][@"items"] count]==5 && GVMEncodeSourceOutput(vmOutput,101,&words) && [GVMDecodeSourceOutput(1,words,101)[@"lanes"] isEqual:vmOutput[@"lanes"]],@"VietMap lanes reach the wire");

    // Lanes: one optional set for the next junction, all lanes or none.
    NSDictionary *(^Lane)(id,id)=^NSDictionary *(id code,id enabled) { return enabled ? @{@"code":code,@"enabled":enabled} : @{@"code":code}; };
    NSDictionary *laneSet=@{@"distance":@127,@"items":@[Lane(@1,@YES),Lane(@1,@YES),Lane(@1,@NO),Lane(@5,nil),Lane(@4,@YES)],@"receivedAt":@100};
    NSDictionary *withLanes=GVMSourceOutput(1,@{@"speed":Sample(@42,100),@"lanes":laneSet},@[],101);
    NSArray *items=withLanes[@"lanes"][@"items"];
    Require(items.count==5 && [withLanes[@"lanes"][@"distance"] isEqual:@127] && [items[3][@"enabled"] isEqual:@YES] && [items[2][@"enabled"] isEqual:@NO],@"lanes keep order, distance and enabled (default true)");
    Require(GVMEncodeSourceOutput(withLanes,101,&words) && [GVMDecodeSourceOutput(1,words,101) isEqual:withLanes],@"lanes round trip with the other fields");
    Require(!GVMDecodeSourceOutput(1,words,105)[@"lanes"] && GVMDecodeSourceOutput(1,words,104)[@"lanes"],@"lanes expire at five seconds on their own receive time");
    NSMutableArray *all=[NSMutableArray new];
    for (NSNumber *code in @[@1,@4,@5,@16,@17,@21,@64,@65,@68,@69,@80,@81]) [all addObject:Lane(code,@YES)];
    NSDictionary *twelve=GVMSourceOutput(1,@{@"lanes":@{@"distance":NSNull.null,@"items":all,@"receivedAt":@100}},@[],100);
    Require(GVMEncodeSourceOutput(twelve,100,&words) && [GVMDecodeSourceOutput(1,words,100) isEqual:twelve] && twelve[@"lanes"][@"distance"]==NSNull.null,@"twelve lanes and an unknown distance round trip");
    NSDictionary *wide=GVMSourceOutput(1,@{@"lanes":@{@"distance":@40,@"items":@[Lane(@85,@YES),Lane(@257,@YES)],@"receivedAt":@100}},@[],100);
    Require(GVMEncodeSourceOutput(wide,100,&words) && [GVMDecodeSourceOutput(1,words,100)[@"lanes"][@"items"][1][@"code"] isEqual:@257],@"every known direction survives the wire");
    Require([GVMSourceOutput(1,@{@"lanes":@{@"items":@[Lane(@3,@YES),Lane(@0,@YES)],@"receivedAt":@100}},@[],100)[@"lanes"][@"items"] isEqual:@[Lane(@1,@YES),Lane(@0,@YES)]],@"unknown direction bits are dropped, the lane keeps its place");
    [all addObject:Lane(@1,@YES)];
    NSArray *badSets=@[@{@"items":all,@"receivedAt":@100},@{@"items":@[],@"receivedAt":@100},
        @{@"items":@[Lane(@1,@YES),Lane(@"1",@YES)],@"receivedAt":@100},@{@"items":@[Lane(@512,@YES)],@"receivedAt":@100},
        @{@"items":@[Lane(@1,@1)],@"receivedAt":@100},@{@"items":@[Lane(@1,@YES)],@"distance":@10001,@"receivedAt":@100},
        @{@"items":@[Lane(@1,@YES)],@"receivedAt":@94},@{@"items":@[Lane(@1,@YES)],@"receivedAt":@101}];
    for (NSDictionary *bad in badSets) Require(!GVMSourceOutput(1,@{@"lanes":bad},@[],100)[@"lanes"],@"malformed, oversized, stale or future lane sets are omitted whole");
    Require(GVMEncodeSourceOutput(withLanes,101,&words),@"re-encode lanes");
    GVMOutputWords tampered=words; tampered.words[7]|=64ULL<<8;
    Require(!GVMDecodeSourceOutput(1,tampered,101)[@"lanes"],@"reserved lane bits reject the set");
    tampered=words; tampered.words[8]=1;
    Require(!GVMDecodeSourceOutput(1,tampered,101)[@"lanes"],@"bytes past the lane count reject the set");
    tampered=words; tampered.words[6]&=~(1023ULL<<14);
    Require(!GVMDecodeSourceOutput(1,tampered,101)[@"lanes"],@"a zero lane count is no lanes");
    Require([GVMDecodeSourceOutput(1,tampered,101)[@"speed"][@"value"] isEqual:@42],@"bad lanes leave the other fields alone");

    // Per-lane speed limits, as VietMap sent them on the HCMC - Long Thanh expressway: 90 and 70.
    NSDictionary *(^Limited)(id,id)=^NSDictionary *(id code,id limit) { return @{@"code":code,@"enabled":@YES,@"limit":limit}; };
    NSDictionary *limited=GVMSourceOutput(1,@{@"lanes":@{@"items":@[Limited(@1,@90),Limited(@1,@70)],@"receivedAt":@100}},@[],100);
    Require([limited[@"lanes"][@"items"] isEqual:@[Limited(@1,@90),Limited(@1,@70)]],@"lane limits are kept");
    Require(GVMEncodeSourceOutput(limited,100,&words) &&
        [GVMDecodeSourceOutput(1,words,100)[@"lanes"][@"items"] isEqual:@[Limited(@1,@90),Limited(@1,@70)]],@"lane limits survive the wire");
    NSArray *kinds=@[Limited(@0,@120),Limited(@0,@0),Limited(@0,@-1),Limited(@0,@-60),Limited(@64,@255),Limited(@4,@-255)];
    Require(GVMEncodeSourceOutput(GVMSourceOutput(1,@{@"lanes":@{@"items":kinds,@"receivedAt":@100}},@[],100),100,&words),@"encode every kind of lane limit");
    NSArray *decodedKinds=[GVMDecodeSourceOutput(1,words,100)[@"lanes"][@"items"] valueForKey:@"limit"];
    Require([decodedKinds isEqual:@[@120,@0,@0,@-60,@255,@-255]],@"limits, dimmed limits and signs without a number survive; -1 reads as 0");
    NSMutableArray *twelveLimited=[NSMutableArray new];
    for (NSInteger i=0;i<12;i++) [twelveLimited addObject:Limited(@1,@(40+10*i))];
    Require(GVMEncodeSourceOutput(GVMSourceOutput(1,@{@"lanes":@{@"items":twelveLimited,@"receivedAt":@100}},@[],100),100,&words) &&
        [GVMDecodeSourceOutput(1,words,100)[@"lanes"][@"items"] isEqual:twelveLimited],@"twelve lanes carry their limits");
    NSArray *partialSets=@[@[Limited(@1,@90),Lane(@1,@YES)],@[Limited(@1,@90),Limited(@1,@256)],@[Limited(@1,@90),Limited(@1,@"70")],
        @[Limited(@1,@90),Limited(@1,@YES)],@[Limited(@1,@90),Limited(@1,@70.5)]];
    for (NSArray *set in partialSets)
        Require([GVMSourceOutput(1,@{@"lanes":@{@"items":set,@"receivedAt":@100}},@[],100)[@"lanes"][@"items"] isEqual:@[Lane(@1,@YES),Lane(@1,@YES)]],
            @"partial or unreadable limits are left out, the lanes stay");
    Require(GVMEncodeSourceOutput(limited,100,&words),@"re-encode lane limits");
    tampered=words; tampered.words[9]|=512ULL<<20;
    Require([GVMDecodeSourceOutput(1,tampered,100)[@"lanes"][@"items"] isEqual:@[Lane(@1,@YES),Lane(@1,@YES)]],@"a limit past the last lane drops the limits, not the lanes");
    tampered=words; tampered.words[9]&=~(1023ULL<<10);
    Require([GVMDecodeSourceOutput(1,tampered,100)[@"lanes"][@"items"] isEqual:@[Lane(@1,@YES),Lane(@1,@YES)]],@"a lane without a limit drops the limits");
    tampered=words; tampered.words[10]=1ULL<<63;
    Require([GVMDecodeSourceOutput(1,tampered,100)[@"lanes"][@"items"] isEqual:@[Lane(@1,@YES),Lane(@1,@YES)]],@"reserved limit bits drop the limits");
    puts("source-output tests passed");
} return 0; }
