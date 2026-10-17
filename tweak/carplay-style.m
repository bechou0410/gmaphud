#import <rootless.h>
#import "carplay-style.h"
#import "classic-card.h"
#import "halo-card.h"
#import "halo-lanes.h"
#import "halo-dock.h"
#import "guidance-state.h"
#import "overspeed-frame.h"
#import "speed-presentation.h"
#import "source-output.h"
#import "placement-state.h"
#import "source-transport.h"
#import <objc/runtime.h>
#include <notify.h>

static const void *cardKey = &cardKey, *phoneKey=&phoneKey, *testLabelKey=&testLabelKey, *laneKey=&laneKey,
    *alertsKey=&alertsKey, *dockKey=&dockKey;
// Navigation on the full map: the free slot in CarPlay's guidance column, between the maneuver card
// and the arrival estimates (6 points clear of each), in the map's coordinates. CarPlayTemplateUIHost
// draws that column; GMapHUDGuidanceRelay reports it twice a second.
static BOOL GuidanceSlot(UIView *map, CGRect *slot) {
    static int token=-1;
    uint64_t state=0;
    GVMGuidanceColumn column;
    if (token<0) notify_register_check(GVMGuidanceStateName,&token);
    if (token<0 || notify_get_state(token,&state)!=NOTIFY_STATUS_OK || !map.window.screen ||
        !GVMDecodeGuidance(state,NSProcessInfo.processInfo.systemUptime,&column)) return NO;
    CGRect free=CGRectMake(column.x,column.cardBottom+6,column.width,column.etaTop-column.cardBottom-12);
    if (free.size.height<=0) return NO;
    *slot=[map convertRect:free fromCoordinateSpace:map.window.screen.coordinateSpace];
    return CGRectContainsRect(map.bounds,*slot);
}
static GVMInterfaceStyle CardStyle(UIView *card) {
    return [card isKindOfClass:GVMHaloSpeedCard.class] ? GVMInterfaceHalo : GVMInterfaceClassic;
}
static NSUInteger SizePercent(NSUInteger surface) {
    static int token=-1; uint64_t state=0;
    if (token<0) notify_register_check(GVMSizeStateName,&token);
    if (token>=0) notify_get_state(token,&state);
    return GVMDecodeSize(state,surface);
}
static GVMCardPlacement fullPlacement = GVMCardTopRight;
static BOOL dashboardLeft;

void GVMSetPlacementState(uint64_t state) {
    NSUInteger corner=0;
    BOOL left=NO;
    if (!GVMDecodePlacement(state,&corner,&left)) return;
    fullPlacement=(GVMCardPlacement)corner;
    dashboardLeft=left;
}

static UIWindow *HostWindow(UIView *host) {
    return [host isKindOfClass:UIWindow.class] ? (UIWindow *)host : host.window;
}
static BOOL ExternalMap(UIView *map) {
    return NSThread.isMainThread && [map isKindOfClass:NSClassFromString(@"AZCarPlayView")] &&
        map.window && map.window.screen != UIScreen.mainScreen;
}
BOOL GVMBubbleEnabledForHost(UIView *host) {
    BOOL phone=[objc_getAssociatedObject(host,phoneKey) boolValue];
    CGFloat screenWidth=HostWindow(host).screen.bounds.size.width;
    BOOL dashboard=!phone && screenWidth>0 && host.bounds.size.width/screenWidth<0.72;
    return GVMBubbleEnabled(phone ? 2 : dashboard ? 1 : 0);
}
void GVMStyleNativeSpeedView(UIView *view) {
    UIView *owner = view.superview;
    while (owner && ![owner isKindOfClass:NSClassFromString(@"AZCarPlayView")]) owner=owner.superview;
    if (ExternalMap(owner)) view.alpha=0; // Keep Google's model/layout boundary, replace only its artwork.
}
CGRect GVMLayoutSpeedCard(UIView *map) {
    BOOL phone=[objc_getAssociatedObject(map,phoneKey) boolValue];
    if (!ExternalMap(map) && !(phone && NSThread.isMainThread && HostWindow(map).screen==UIScreen.mainScreen)) return CGRectZero;
    UIView<GVMSpeedCardView> *card = objc_getAssociatedObject(map,cardKey);
    GVMHaloLaneStrip *strip=objc_getAssociatedObject(map,laneKey);
    GVMHaloSignDock *dockView=objc_getAssociatedObject(map,dockKey);
    GVMInterfaceStyle style=card ? CardStyle(card) : GVMCurrentInterfaceStyle();
    card.hidden=!GVMBubbleEnabledForHost(map);
    if (card.hidden) { strip.hidden=YES; dockView.hidden=YES; return card.frame; }
    NSArray<NSDictionary *> *allAlerts=objc_getAssociatedObject(map,alertsKey) ?: card.alerts ?: @[];
    // The iPhone overlay never docks, so its bubble shows every alert before its size is chosen.
    if (phone && card && !((card.alerts==allAlerts) || [card.alerts isEqual:allAlerts])) { card.alerts=allAlerts; [card setNeedsDisplay]; }
    CGRect screen=HostWindow(map).screen.bounds;
    UIEdgeInsets insets=map.safeAreaInsets;
    CGFloat margin=MIN(10,MAX(5,MIN(screen.size.width,screen.size.height)*0.03));
    // Google propagates horizontal control exclusions into map/window safe
    // areas. Anchor to the map bounds so disappearing alerts cannot shift it.
    CGFloat left=CGRectGetMinX(map.bounds)+margin;
    CGFloat right=CGRectGetMaxX(map.bounds)-margin;
    CGFloat top=CGRectGetMinY(map.bounds)+margin;
    CGFloat bottom=CGRectGetMaxY(map.bounds)-margin;
    if (phone) {
        // Phone placement spans the whole app window, including system safe areas.
        left=CGRectGetMinX(map.bounds); right=CGRectGetMaxX(map.bounds);
        top=CGRectGetMinY(map.bounds); bottom=CGRectGetMaxY(map.bounds);
    }
    NSUInteger phoneLayout=0;
    NSUInteger phoneCorner=1; NSInteger offsetX=0,offsetY=0;
    GVMCardSize size={0,0,NO,NO};
    if (phone) {
        static int token=-1; uint64_t state=0;
        if (token<0) notify_register_check(GVMPhonePlacementStateName,&token);
        if (token>=0) notify_get_state(token,&state);
        GVMDecodePhonePlacement(state,&phoneCorner,&offsetX,&offsetY,&phoneLayout);
        size=GVMPhoneCardSizeForLayout(style,map.bounds.size.width,map.bounds.size.height,card.alerts.count,phoneLayout);
    }
    BOOL dashboard=!phone && map.bounds.size.width/screen.size.width<0.72;
    NSUInteger surface=phone ? 2 : dashboard ? 1 : 0;
    static int configurationToken=-1; uint64_t configuration=0;
    if (configurationToken<0) notify_register_check(GVMBubbleConfigurationStateName,&configurationToken);
    if (configurationToken>=0) notify_get_state(configurationToken,&configuration);
    // Navigation on the full map, New UI: signs in effect and lanes move under CarPlay's maneuver
    // card, and the bubble keeps the dial and the signs ahead. What does not fit stays in the bubble.
    NSUInteger laneCount=[strip.lanes[@"items"] count];
    BOOL laneTag=[strip.lanes[@"distance"] isKindOfClass:NSNumber.class];
    GVMEffectDock dock;
    memset(&dock,0,sizeof dock);
    NSMutableArray<NSDictionary *> *inEffect=[NSMutableArray new], *ahead=[NSMutableArray new];
    for (NSDictionary *alert in allAlerts) [(alert[@"distance"]==NSNull.null ? inEffect : ahead) addObject:alert];
    CGRect slot=CGRectZero;
    if ([card isKindOfClass:GVMHaloSpeedCard.class] && !phone && !dashboard && (inEffect.count || laneCount) && GuidanceSlot(map,&slot)) {
        NSUInteger layout=GVMDecodeBubbleLayout(configuration,surface);
        GVMCardSize probe=GVMCarPlayCardSizeForLayout(style,MAX(0,right-left),MAX(0,bottom-top),screen.size.width,
            screen.size.height,ahead.count,NO,layout,SizePercent(surface));
        GVMCardSize probeCanvas=GVMHaloCanvasSize(GVMHaloArrangementFor(probe),MIN(ahead.count,2));
        double scale=probeCanvas.width>0 ? probe.width/probeCanvas.width : 0;
        dock=GVMEffectDockFor((GVMModuleRect){slot.origin.x,slot.origin.y,slot.size.width,slot.size.height},
            inEffect.count,laneCount,laneTag,scale);
    }
    NSArray<NSDictionary *> *docked=[inEffect subarrayWithRange:NSMakeRange(0,dock.signs)];
    NSMutableArray<NSDictionary *> *remaining=[NSMutableArray new];
    for (NSDictionary *alert in allAlerts) if (![docked containsObject:alert]) [remaining addObject:alert];
    if (card && !((card.alerts==remaining) || [card.alerts isEqual:remaining])) { card.alerts=remaining; [card setNeedsDisplay]; }
    if (!phone) {
        NSUInteger layout=GVMDecodeBubbleLayout(configuration,surface);
        size=GVMCarPlayCardSizeForLayout(style,MAX(0,right-left),MAX(0,bottom-top),screen.size.width,
            screen.size.height,card.alerts.count,dashboard,layout,SizePercent(surface));
    }
    NSArray *moduleOrder=GVMDecodeModuleOrder(configuration,surface,size.compact);
    if (![card.moduleOrder isEqual:moduleOrder]) { card.moduleOrder=moduleOrder; [card setNeedsDisplay]; }
    BOOL compact=size.compact;
    GVMCardPlacement placement=phone ? (GVMCardPlacement)phoneCorner : dashboard ? (dashboardLeft ? GVMCardTopLeft : GVMCardTopRight) : fullPlacement;
    // Size belongs to the viewport and user preference, never to the chosen
    // corner or the space left by Google's navigation controls.
    if (phone) size=GVMScaleCardSize(size,SizePercent(surface),MAX(0,right-left),MAX(0,bottom-top));
    CGFloat viewportLeft=left, viewportRight=right, viewportTop=top, viewportBottom=bottom;
    if (!phone) {
        top+=insets.top;
        bottom-=insets.bottom;
        if (placement==GVMCardTopLeft || placement==GVMCardBottomLeft) left+=insets.left;
        if (placement==GVMCardBottomRight) right-=insets.right;
        if (placement==GVMCardBottomLeft || placement==GVMCardBottomRight)
            bottom-=MAX(0,25-insets.bottom); // Leave Google's map attribution clear.
    }
    GVMCardOrigin origin=GVMCardOriginFor(left,right,top,bottom,size,placement);
    if (phone) {
        origin=GVMPhoneCardOriginFor(left,right,top,bottom,size,placement,
            offsetX*map.bounds.size.width/100.0,offsetY*map.bounds.size.height/100.0);
    } else {
        origin=GVMClampCardOrigin(origin,size,viewportLeft,viewportRight,viewportTop,viewportBottom);
    }
    CGRect frame=CGRectMake(origin.x,origin.y,size.width,size.height);
    if (card && card.compact!=compact) { card.compact=compact; [card setNeedsDisplay]; }
    if ([card isKindOfClass:GVMHaloSpeedCard.class]) {
        GVMHaloSpeedCard *halo=(GVMHaloSpeedCard *)card;
        BOOL trailing=placement==GVMCardTopRight || placement==GVMCardBottomRight;
        if (halo.stacked!=size.stacked || halo.trailing!=trailing) {
            halo.stacked=size.stacked; halo.trailing=trailing; [halo setNeedsDisplay];
        }
    }
    if (card && !CGRectEqualToRect(card.frame,frame)) { card.frame=frame; [card setNeedsDisplay]; }
    // Signs docked under the maneuver card.
    if (dock.signs && !dockView) {
        dockView=[[GVMHaloSignDock alloc] initWithFrame:CGRectZero];
        dockView.layer.shadowColor=UIColor.blackColor.CGColor; dockView.layer.shadowOpacity=0.35;
        dockView.layer.shadowRadius=6; dockView.layer.shadowOffset=CGSizeMake(0,3);
        [map addSubview:dockView]; objc_setAssociatedObject(map,dockKey,dockView,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    dockView.hidden=!dock.signs;
    if (dock.signs) {
        CGFloat bleed=dock.diameter*GVMHaloSignDockBleed;
        CGRect signsFrame=CGRectMake(dock.signFrames[0].x-bleed,dock.signFrames[0].y-bleed,
            dock.signs*dock.diameter+(dock.signs-1)*6+2*bleed,dock.diameter+2*bleed);
        if (!CGRectEqualToRect(dockView.frame,signsFrame)) dockView.frame=signsFrame;
        dockView.diameter=dock.diameter; dockView.signs=docked;
        [map bringSubviewToFront:dockView];
    }
    // New UI lanes go on the free side of the bubble without moving it. On the full map the bubble
    // with its lanes may reach half the map; Dashboard has the whole tile; iPhone keeps its room.
    // During navigation they sit under the maneuver card instead, when they fit there.
    GVMLaneStripLayout lanes={{0,0,0,0},0,GVMLaneStripHidden};
    if (dock.lanes) lanes=(GVMLaneStripLayout){dock.strip,dock.stripScale,GVMLaneStripBelow};
    else if (strip && laneCount && [card isKindOfClass:GVMHaloSpeedCard.class]) {
        NSUInteger shown=MIN(card.alerts.count,2);
        GVMHaloArrangement arrangement=GVMHaloArrangementFor(size);
        GVMCardSize canvas=GVMHaloCanvasSize(arrangement,shown);
        double scale=canvas.width>0 ? frame.size.width/canvas.width : 0;
        BOOL atRight=placement==GVMCardTopRight || placement==GVMCardBottomRight;
        BOOL atBottom=placement==GVMCardBottomLeft || placement==GVMCardBottomRight;
        GVMModuleRect block=GVMHaloDialFrame(arrangement,GVMAlertsFirst(moduleOrder),atRight,shown);
        GVMModuleRect dial={frame.origin.x+block.x*scale,frame.origin.y+block.y*scale,block.width*scale,block.height*scale};
        GVMModuleRect cardRect={frame.origin.x,frame.origin.y,frame.size.width,frame.size.height};
        GVMModuleRect area={left,top,MAX(0,right-left),MAX(0,bottom-top)};
        double reachWidth=phone ? 0.6 : dashboard ? 1 : 0.5, reachHeight=phone ? 0.65 : dashboard ? 1 : 0.5;
        lanes=GVMLaneStripLayoutFor(cardRect,scale,arrangement,dial,atRight,atBottom,laneCount,laneTag,area,reachWidth,reachHeight);
    }
    strip.hidden=lanes.place==GVMLaneStripHidden;
    if (!strip.hidden) {
        CGRect laneFrame=CGRectMake(lanes.frame.x,lanes.frame.y,lanes.frame.width,lanes.frame.height);
        if (!CGRectEqualToRect(strip.frame,laneFrame)) strip.frame=laneFrame;
        strip.scale=lanes.scale;
    }
    return frame;
}
static void UpdateOverspeedBorder(UIView *map,NSDictionary *output) {
    static const void *key=&key;
    NSUInteger mode=GVMOverspeedMode();
    BOOL visible=ExternalMap(map) && GVMBubbleEnabledForHost(map);
    for (UIView *view=map;view;view=view.superview) if (view.hidden || view.alpha<=0.01) visible=NO;
    if (map.window.windowScene.activationState!=UISceneActivationStateForegroundActive) visible=NO;
    uint64_t lease=visible ? GVMEncodeOverspeedLease(output,NSProcessInfo.processInfo.systemUptime) : 0;
    // Hidden retained maps must not clear the visible map's shared warning.
    // With no visible publisher the bounded lease expires on its own.
    if (visible || mode!=2) GVMPublishOverspeedLease(mode==2 ? lease : 0);
    GVMOverspeedFrame *frame=objc_getAssociatedObject(map,key);
    if (mode==1 && lease && !frame) {
        frame=[[GVMOverspeedFrame alloc] initWithFrame:map.bounds]; [map.layer addSublayer:frame.layer];
        objc_setAssociatedObject(map,key,frame,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Draw inside the visible viewport so clipping/sidebar cannot remove an edge.
    CGRect viewport=map.bounds;
    UIWindow *window=map.window;
    if (window) {
        // Safe-area insets also reserve Google's buttons, not just the sidebar.
        // Intersect actual host geometry; coordinate conversion handles any screen ratio.
        CGRect visibleWindow=window.bounds;
        // Full map can extend under the CarPlay rail. Keep only the dominant
        // edge reservation; other safe-area edges belong to Google controls.
        CGSize screenSize=window.screen.bounds.size;
        BOOL dashboard=screenSize.width>0 && map.bounds.size.width/screenSize.width<0.72;
        if (!dashboard) {
            UIEdgeInsets rail=window.safeAreaInsets;
            CGFloat edge=MAX(MAX(rail.left,rail.right),MAX(rail.top,rail.bottom));
            UIEdgeInsets exclusion=UIEdgeInsetsZero;
            if (edge>0) {
                if (rail.left==edge) exclusion.left=edge;
                else if (rail.right==edge) exclusion.right=edge;
                else if (rail.top==edge) exclusion.top=edge;
                else exclusion.bottom=edge;
            }
            visibleWindow=UIEdgeInsetsInsetRect(visibleWindow,exclusion);
        }
        viewport=CGRectIntersection(viewport,[map convertRect:visibleWindow fromView:window]);
        for (UIView *parent=map.superview;parent;parent=parent.superview)
            if (parent.clipsToBounds) viewport=CGRectIntersection(viewport,[map convertRect:parent.bounds fromView:parent]);
    }
    BOOL valid=!CGRectIsNull(viewport) && !CGRectIsEmpty(viewport);
    frame.autoresizingMask=UIViewAutoresizingNone;
    frame.frame=valid ? viewport : CGRectZero;
    [frame setWarningLevel:mode==1 && valid ? (NSUInteger)(lease&3) : 0];
    if (frame && !frame.hidden) { [frame setNeedsLayout]; [frame layoutIfNeeded]; frame.layer.zPosition=10000; }
}
void GVMUpdateSpeedCard(UIView *map, NSDictionary *output, BOOL night) {
    NSNumber *speed=output[@"speed"][@"value"], *limit=output[@"speedLimit"][@"value"];
    // Freshness is validated upstream; a new receive time alone must not repaint.
    NSMutableArray *visibleAlerts=[NSMutableArray new];
    for (NSDictionary *alert in output[@"alerts"])
        [visibleAlerts addObject:@{@"type":alert[@"type"],@"value":alert[@"value"],
            @"distance":alert[@"distance"],@"artworkID":alert[@"artworkID"]}];
    NSArray *alerts=[visibleAlerts copy];
    NSUInteger sourceID=output ? [output[@"sourceID"] unsignedIntegerValue] : GVMSelectedSourceID();
    if (!ExternalMap(map) && !([objc_getAssociatedObject(map,phoneKey) boolValue] && NSThread.isMainThread && HostWindow(map).screen==UIScreen.mainScreen)) return;
    if (ExternalMap(map)) UpdateOverspeedBorder(map,output);
    UIView<GVMSpeedCardView> *card = objc_getAssociatedObject(map,cardKey);
    GVMHaloLaneStrip *strip=objc_getAssociatedObject(map,laneKey);
    if (!GVMBubbleEnabledForHost(map)) {
        card.hidden=YES; strip.hidden=YES; ((UIView *)objc_getAssociatedObject(map,dockKey)).hidden=YES; return;
    }
    // Switching between Classic and New UI (beta) replaces the bubble in place.
    GVMInterfaceStyle style=GVMCurrentInterfaceStyle();
    if (card && CardStyle(card)!=style) {
        [card removeFromSuperview]; card=nil;
        objc_setAssociatedObject(map,cardKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!card) {
        BOOL halo=style==GVMInterfaceHalo;
        card = halo ? [[GVMHaloSpeedCard alloc] initWithFrame:CGRectZero] : [[GVMClassicSpeedCard alloc] initWithFrame:CGRectZero];
        card.backgroundColor=UIColor.clearColor; card.opaque=NO; card.userInteractionEnabled=NO;
        card.isAccessibilityElement=YES;
        card.layer.shadowColor=UIColor.blackColor.CGColor; card.layer.shadowOpacity=halo ? 0.35 : 0.2;
        card.layer.shadowRadius=halo ? 6 : 3; card.layer.shadowOffset=CGSizeMake(0,halo ? 3 : 2);
        [map addSubview:card]; objc_setAssociatedObject(map,cardKey,card,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Lanes belong to New UI; Classic stays the 0.2.3 bubble. Receive times are left out so only a
    // change on the road repaints the strip.
    NSDictionary *laneSample=output[@"lanes"];
    NSDictionary *lanes=style==GVMInterfaceHalo && [laneSample[@"items"] count] ?
        @{@"distance":laneSample[@"distance"] ?: NSNull.null,@"items":laneSample[@"items"]} : nil;
    if (lanes && !strip) {
        strip=[[GVMHaloLaneStrip alloc] initWithFrame:CGRectZero]; strip.hidden=YES;
        [map addSubview:strip]; objc_setAssociatedObject(map,laneKey,strip,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    strip.lanes=lanes;
    // The layout decides which of these the bubble shows; during navigation signs in effect may sit
    // under CarPlay's maneuver card instead.
    NSArray *previousAlerts=objc_getAssociatedObject(map,alertsKey);
    BOOL alertsChanged=!((previousAlerts==alerts)||[previousAlerts isEqual:alerts]);
    objc_setAssociatedObject(map,alertsKey,alerts,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGRect frame = GVMLayoutSpeedCard(map);
    BOOL changed = card.sourceID!=sourceID || alertsChanged || !CGRectEqualToRect(card.frame,frame) || card.night!=night ||
        !((card.speed==speed)||[card.speed isEqual:speed]) || !((card.limit==limit)||[card.limit isEqual:limit]);
    if ([card isKindOfClass:GVMHaloSpeedCard.class]) {
        BOOL limitDial=GVMDecodeLimitDial(GVMCurrentPresentationOptions());
        if (((GVMHaloSpeedCard *)card).limitDial!=limitDial) { ((GVMHaloSpeedCard *)card).limitDial=limitDial; changed=YES; }
    }
    card.sourceID=sourceID; card.frame=frame; card.speed=speed; card.limit=limit; card.night=night;
    if (changed) [card setNeedsDisplay];
    card.accessibilityLabel=[NSString stringWithFormat:@"Speed %@ km/h, limit %@ km/h", speed ?: @"unavailable",limit ?: @"unavailable"];
    for (NSDictionary *alert in alerts) {
        NSString *name=GVMRoadAlertName([alert[@"type"] unsignedIntegerValue]) ?: @"road warning";
        id meters=alert[@"distance"];
        card.accessibilityLabel=[card.accessibilityLabel stringByAppendingFormat:@", %@ %@%@%@",GVMSourceDisplayName(sourceID),name,
            alert[@"value"]==NSNull.null ? @"" : [NSString stringWithFormat:@" %@ km/h",alert[@"value"]],
            meters==NSNull.null ? @"" : [NSString stringWithFormat:@" %@ meters",meters]];
    }
    if (lanes && !strip.hidden) {
        id meters=lanes[@"distance"];
        card.accessibilityLabel=[card.accessibilityLabel stringByAppendingFormat:@", %lu lanes%@",(unsigned long)[lanes[@"items"] count],
            meters==NSNull.null ? @"" : [NSString stringWithFormat:@" in %@ meters",meters]];
    }
    [map bringSubviewToFront:card];
    if (strip) [map bringSubviewToFront:strip];
    UIView *dockView=objc_getAssociatedObject(map,dockKey);
    if (dockView) [map bringSubviewToFront:dockView];
}

void GVMSetSpeedCardTest(UIView *map, BOOL test) {
    UIView *card=objc_getAssociatedObject(map,cardKey);
    BOOL halo=card ? CardStyle(card)==GVMInterfaceHalo : GVMCurrentInterfaceStyle()==GVMInterfaceHalo;
    if ([card isKindOfClass:GVMHaloSpeedCard.class] && ((GVMHaloSpeedCard *)card).test!=test) {
        ((GVMHaloSpeedCard *)card).test=test; [card setNeedsDisplay];
    }
    // Classic marks a test sample with a yellow label under the bubble; Halo uses its chip.
    UILabel *label=objc_getAssociatedObject(map,testLabelKey);
    if (test && !halo && !label) {
        label=[[UILabel alloc] initWithFrame:CGRectZero];
        label.text=@"TEST"; label.font=[UIFont boldSystemFontOfSize:9];
        label.textColor=UIColor.blackColor; label.backgroundColor=UIColor.systemYellowColor;
        label.textAlignment=NSTextAlignmentCenter; label.layer.cornerRadius=4; label.clipsToBounds=YES;
        label.userInteractionEnabled=NO;
        [map addSubview:label]; objc_setAssociatedObject(map,testLabelKey,label,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    label.hidden=!test || halo || !GVMBubbleEnabledForHost(map);
    if (label.hidden) return;
    CGRect cardFrame=GVMLayoutSpeedCard(map);
    label.frame=CGRectMake(CGRectGetMaxX(cardFrame)-36,CGRectGetMaxY(cardFrame)+3,36,13);
    [map bringSubviewToFront:label];
}

void GVMUpdatePhoneSpeedCard(UIView *host,NSDictionary *output,BOOL night) {
    if (!host || !NSThread.isMainThread) return;
    objc_setAssociatedObject(host,phoneKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    GVMUpdateSpeedCard(host,output,night);
}
void GVMRemovePhoneSpeedCard(UIView *host) {
    UIView *card=objc_getAssociatedObject(host,cardKey);
    [card removeFromSuperview];
    [(UIView *)objc_getAssociatedObject(host,laneKey) removeFromSuperview];
    objc_setAssociatedObject(host,laneKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host,cardKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host,phoneKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
