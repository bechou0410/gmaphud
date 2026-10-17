#import "halo-card.h"
#import "halo-style.h"
#import "speed-presentation.h"
#import "source-output.h"
#import <rootless.h>

static void DrawCentered(NSAttributedString *text, CGPoint centre) {
    CGSize size=text.size;
    [text drawAtPoint:CGPointMake(centre.x-size.width/2,centre.y-size.height/2)];
}
static NSString *AlertKey(NSDictionary *alert) {
    return [NSString stringWithFormat:@"%@|%@|%@",alert[@"type"],alert[@"value"],alert[@"artworkID"]];
}

@implementation GVMHaloSpeedCard {
    // Distance first seen for each alert, so the approach bar fills as the car gets closer.
    NSMutableDictionary<NSString *,NSNumber *> *_approachStart;
}
@synthesize speed=_speed, limit=_limit, alerts=_alerts, night=_night, compact=_compact, sourceID=_sourceID, moduleOrder=_moduleOrder;
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    _approachStart=[NSMutableDictionary new];
    GVMHaloRegisterFonts();
    return self;
}
- (void)setAlerts:(NSArray<NSDictionary *> *)alerts {
    _alerts=[alerts copy];
    NSMutableSet *seen=[NSMutableSet new];
    for (NSDictionary *alert in _alerts) {
        NSString *key=AlertKey(alert); [seen addObject:key];
        id meters=alert[@"distance"];
        if (![meters isKindOfClass:NSNumber.class]) continue;
        if ([meters doubleValue]>[_approachStart[key] doubleValue]) _approachStart[key]=meters;
    }
    for (NSString *key in _approachStart.allKeys) if (![seen containsObject:key]) [_approachStart removeObjectForKey:key];
}
// Signs in effect carry no distance (NSNull), so the type is checked before reading a number.
- (CGFloat)approachFor:(NSDictionary *)alert {
    id meters=alert[@"distance"];
    double start=[_approachStart[AlertKey(alert)] doubleValue];
    if (![meters isKindOfClass:NSNumber.class] || start<=0) return 0;
    return MAX(0,MIN(1,1-[meters doubleValue]/start));
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context=UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    NSUInteger count=MIN(self.alerts.count,2);
    GVMHaloArrangement arrangement=self.stacked ? GVMHaloStack : self.compact ? GVMHaloColumn : GVMHaloRow;
    GVMCardSize canvas=GVMHaloCanvasSize(arrangement,count);
    BOOL alertsFirst=GVMAlertsFirst(self.moduleOrder);
    CGContextScaleCTM(context,self.bounds.size.width/canvas.width,self.bounds.size.height/canvas.height);
    GVMModuleRect block=GVMHaloDialFrame(arrangement,alertsFirst,self.trailing,count);
    [self drawDialInBlock:CGRectMake(block.x,block.y,block.width,block.height) context:context];
    for (NSUInteger i=0;i<count;i++) {
        GVMModuleRect cell=GVMHaloAlertFrame(arrangement,alertsFirst,self.trailing,count,i);
        [self drawAlert:self.alerts[i] inCell:CGRectMake(cell.x,cell.y,cell.width,cell.height)];
    }
    CGContextRestoreGState(context);
}

- (void)drawDialInBlock:(CGRect)block context:(CGContextRef)context {
    CGRect dial=CGRectMake(CGRectGetMidX(block)-GVMHaloDial/2,CGRectGetMinY(block)+7,GVMHaloDial,GVMHaloDial);
    CGPoint centre=CGPointMake(CGRectGetMidX(dial),CGRectGetMidY(dial));
    BOOL live=self.speed!=nil;
    BOOL hasLimit=self.limit && self.limit.doubleValue>0;
    GVMWarning state=hasLimit ? GVMWarningFor(self.speed,self.limit) : GVMWarningNormal;
    uint32_t tone=state==GVMWarningOver ? GVMHaloSignal : state==GVMWarningNear ? GVMHaloAmber : GVMHaloIce;

    if (state==GVMWarningOver) {
        CGContextSaveGState(context);
        CGContextSetShadowWithColor(context,CGSizeZero,12,GVMHaloColor(GVMHaloSignal,0.55).CGColor);
        UIBezierPath *glow=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(dial,-1,-1)];
        glow.lineWidth=2; [GVMHaloColor(GVMHaloSignal,1) setStroke]; [glow stroke];
        CGContextRestoreGState(context);
    }
    if (self.limitDial) {
        [self drawLimitFace:dial centre:centre limit:hasLimit];
        [self drawSpeedBadgeAt:CGPointMake(CGRectGetMaxX(dial)-GVMHaloBadgeInset,CGRectGetMinY(dial)+GVMHaloBadgeDrop)
            live:live state:state tone:tone];
        [self drawTagBelow:dial live:live];
        return;
    }
    UIBezierPath *face=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(dial,0.5,0.5)];
    [GVMHaloColor(GVMHaloInk900,0.8) setFill]; [face fill];
    face.lineWidth=1; [GVMHaloColor(GVMHaloInk600,1) setStroke]; [face stroke];

    UIBezierPath *track=[UIBezierPath bezierPathWithArcCenter:centre radius:30 startAngle:0 endAngle:2*M_PI clockwise:YES];
    track.lineWidth=5;
    if (!live) { CGFloat dash[]={4,5}; [track setLineDash:dash count:2 phase:0]; }
    [GVMHaloColor(live ? GVMHaloInk700 : GVMHaloInk400,1) setStroke]; [track stroke];
    double fraction=state==GVMWarningOver ? 1 : GVMProgressFor(self.speed,self.limit);
    if (live && hasLimit && fraction>0) {
        UIBezierPath *arc=[UIBezierPath bezierPathWithArcCenter:centre radius:30 startAngle:-M_PI_2
            endAngle:-M_PI_2+2*M_PI*fraction clockwise:YES];
        arc.lineWidth=5; arc.lineCapStyle=kCGLineCapRound;
        [GVMHaloColor(tone,1) setStroke]; [arc stroke];
    }

    UIColor *speedInk=!live ? GVMHaloColor(GVMHaloInk400,1) : state==GVMWarningNormal ? GVMHaloColor(GVMHaloInk050,1) : GVMHaloColor(tone,1);
    DrawCentered(GVMHaloText(live ? self.speed.stringValue : @"--",GVMHaloNumberFont(30),speedInk,0),
        CGPointMake(centre.x,centre.y-4));
    DrawCentered(GVMHaloText(@"KM/H",GVMHaloFont(8,UIFontWeightBold),GVMHaloColor(GVMHaloInk400,1),0.12),
        CGPointMake(centre.x+0.5,centre.y+13));

    [self drawBadgeAt:CGPointMake(CGRectGetMaxX(dial)-GVMHaloBadgeInset,CGRectGetMinY(dial)+GVMHaloBadgeDrop) limit:hasLimit over:state==GVMWarningOver];
    [self drawTagBelow:dial live:live];
}

// The large circle as the limit sign: its P.127 sticker, or a drawn one when the value has no artwork.
// An unknown limit keeps the dark face with a dashed ring and a dash.
- (void)drawLimitFace:(CGRect)dial centre:(CGPoint)centre limit:(BOOL)hasLimit {
    UIImage *sticker=hasLimit ? GVMHaloSignArtwork(GVMRoadAlertSpeedLimit,self.limit) : nil;
    if (sticker) { GVMHaloDrawSticker(sticker,centre,GVMHaloDial); return; }
    if (hasLimit) {
        // P.127 proportions: a red ring a tenth of the diameter on a white face.
        UIBezierPath *face=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(dial,3.6,3.6)];
        [UIColor.whiteColor setFill]; [face fill];
        face.lineWidth=7.2; [GVMHaloColor(GVMHaloSignRed,1) setStroke]; [face stroke];
        DrawCentered(GVMHaloText(self.limit.stringValue,GVMHaloNumberFont(self.limit.doubleValue>=100 ? 28 : 34),
            GVMHaloColor(GVMHaloInk900,1),0),centre);
        return;
    }
    UIBezierPath *face=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(dial,1.5,1.5)];
    [GVMHaloColor(GVMHaloInk900,0.8) setFill]; [face fill];
    CGFloat dash[]={7,6}; [face setLineDash:dash count:2 phase:0];
    face.lineWidth=3; [GVMHaloColor(GVMHaloInk400,1) setStroke]; [face stroke];
    DrawCentered(GVMHaloText(@"—",GVMHaloNumberFont(32),GVMHaloColor(GVMHaloInk400,1),0),centre);
}
// The small circle as the current speed: a dark disc whose ring and digits take the state colour,
// with the over-limit halo of the limit badge; "--" and a dashed ring without a live speed.
- (void)drawSpeedBadgeAt:(CGPoint)centre live:(BOOL)live state:(GVMWarning)state tone:(uint32_t)tone {
    CGFloat d=GVMHaloBadge, unit=d/30;
    CGRect badge=CGRectMake(centre.x-d/2,centre.y-d/2,d,d);
    if (state==GVMWarningOver) {
        UIBezierPath *halo=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(badge,-1.5*unit,-1.5*unit)];
        halo.lineWidth=3*unit; [GVMHaloColor(GVMHaloSignal,0.4) setStroke]; [halo stroke];
    }
    UIBezierPath *disc=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(badge,1.5*unit,1.5*unit)];
    [GVMHaloColor(GVMHaloInk900,1) setFill]; [disc fill];
    if (!live) { CGFloat dash[]={3*unit,2.5*unit}; [disc setLineDash:dash count:2 phase:0]; }
    disc.lineWidth=(live ? 3 : 2)*unit;
    [GVMHaloColor(live ? tone : GVMHaloInk400,1) setStroke]; [disc stroke];
    UIColor *ink=!live ? GVMHaloColor(GVMHaloInk400,1) : state==GVMWarningNormal ? GVMHaloColor(GVMHaloInk050,1) : GVMHaloColor(tone,1);
    DrawCentered(GVMHaloText(live ? self.speed.stringValue : @"--",GVMHaloNumberFont((self.speed.doubleValue>=100 ? 12 : 14)*unit),ink,0),centre);
}

- (void)drawBadgeAt:(CGPoint)centre limit:(BOOL)hasLimit over:(BOOL)over {
    CGFloat d=GVMHaloBadge, unit=d/30;
    CGRect badge=CGRectMake(centre.x-d/2,centre.y-d/2,d,d);
    if (over) {
        UIBezierPath *halo=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(badge,-1.5*unit,-1.5*unit)];
        halo.lineWidth=3*unit; [GVMHaloColor(GVMHaloSignal,0.4) setStroke]; [halo stroke];
    }
    UIImage *sticker=hasLimit ? GVMHaloSignArtwork(GVMRoadAlertSpeedLimit,self.limit) : nil;
    if (sticker) { GVMHaloDrawSticker(sticker,centre,d); return; }
    UIBezierPath *disc=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(badge,1.5*unit,1.5*unit)];
    if (hasLimit) {
        [UIColor.whiteColor setFill]; [disc fill];
        disc.lineWidth=3*unit; [GVMHaloColor(GVMHaloSignRed,1) setStroke]; [disc stroke];
        DrawCentered(GVMHaloText(self.limit.stringValue,GVMHaloNumberFont((self.limit.doubleValue>=100 ? 12 : 14)*unit),
            GVMHaloColor(GVMHaloInk900,1),0),centre);
    } else {
        [GVMHaloColor(GVMHaloInk900,1) setFill]; [disc fill];
        CGFloat dash[]={3*unit,2.5*unit}; [disc setLineDash:dash count:2 phase:0];
        disc.lineWidth=2*unit; [GVMHaloColor(GVMHaloInk400,1) setStroke]; [disc stroke];
        DrawCentered(GVMHaloText(@"—",GVMHaloNumberFont(14*unit),GVMHaloColor(GVMHaloInk400,1),0),centre);
    }
}

- (void)drawTagBelow:(CGRect)dial live:(BOOL)live {
    NSAttributedString *name=GVMHaloText(GVMHaloSourceTag(self.sourceID),GVMHaloFont(9,UIFontWeightBold),
        GVMHaloColor(live ? GVMHaloIce : GVMHaloInk400,1),0.14);
    NSAttributedString *test=self.test ? GVMHaloText(@"TEST",GVMHaloFont(8,UIFontWeightBold),GVMHaloColor(GVMHaloInk900,1),0.08) : nil;
    CGFloat width=8+6+5+name.size.width+(test ? 5+test.size.width+8 : 0)+8;
    CGRect tag=CGRectMake(CGRectGetMidX(dial)-width/2,CGRectGetMaxY(dial)-7,width,18);
    UIBezierPath *pill=[UIBezierPath bezierPathWithRoundedRect:tag cornerRadius:9];
    [GVMHaloColor(GVMHaloInk900,1) setFill]; [pill fill];
    pill.lineWidth=1; [GVMHaloColor(GVMHaloInk600,1) setStroke]; [pill stroke];
    UIColor *accent=GVMHaloColor(GVMHaloSourceColor(self.sourceID),1);
    CGRect dot=CGRectMake(CGRectGetMinX(tag)+8,CGRectGetMidY(tag)-3,6,6);
    if (live) { [accent setFill]; [[UIBezierPath bezierPathWithOvalInRect:dot] fill]; }
    else {
        UIBezierPath *ring=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(dot,0.75,0.75)];
        ring.lineWidth=1.5; [accent setStroke]; [ring stroke];
    }
    CGFloat x=CGRectGetMaxX(dot)+5;
    [name drawAtPoint:CGPointMake(x,CGRectGetMidY(tag)-name.size.height/2)];
    if (test) {
        x+=name.size.width+5;
        CGRect chip=CGRectMake(x,CGRectGetMidY(tag)-6,test.size.width+8,12);
        [GVMHaloColor(GVMHaloInk050,1) setFill]; [[UIBezierPath bezierPathWithRoundedRect:chip cornerRadius:4] fill];
        DrawCentered(test,CGPointMake(CGRectGetMidX(chip),CGRectGetMidY(chip)));
    }
}

- (void)drawAlert:(NSDictionary *)alert inCell:(CGRect)cell {
    // The sign is the alert: a large sticker, readable at a glance, with its distance in a tag
    // under it as the source tag sits under the dial.
    CGPoint centre=CGPointMake(CGRectGetMidX(cell),CGRectGetMinY(cell)+GVMHaloAlertSignTop+GVMHaloAlertSign/2);
    GVMHaloDrawSign([alert[@"type"] unsignedIntegerValue],alert[@"value"],centre,GVMHaloAlertSign);

    GVMHaloDrawDistanceTag(CGRectGetMidX(cell),CGRectGetMaxY(cell)-19,alert[@"distance"],[self approachFor:alert]);
}
@end
