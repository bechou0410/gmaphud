#import "halo-lanes.h"
#import "halo-style.h"
#import "speed-presentation.h"
#import "source-output.h"

// One lane arrow in a 28 x 28 box: a single stem with one branch per direction. Straight ends at the
// top, left and right turns leave in the middle, U-turn hooks sit low, so heads never overlap.
// Returns the horizontal shift that centres the arrow in its box.
static CGFloat LanePaths(NSUInteger code, UIBezierPath *lines, UIBezierPath *heads) {
    BOOL straight=code&GVMLaneStraight, right=code&GVMLaneRight, left=code&GVMLaneLeft;
    BOOL uLeft=code&GVMLaneUTurnLeft, uRight=code&GVMLaneUTurnRight;
    const CGFloat foot=26.5, headWidth=4.2, headLength=6, stroke=2.6;
    CGFloat x=14+(left || uLeft ? 3.5 : 0)-(right || uRight ? 3.5 : 0);
    CGFloat minX=x-stroke/2, maxX=x+stroke/2;
    void (^head)(CGPoint,CGPoint,CGPoint)=^(CGPoint a,CGPoint b,CGPoint c) {
        [heads moveToPoint:a]; [heads addLineToPoint:b]; [heads addLineToPoint:c]; [heads closePath];
    };
    if (!(code&GVMLaneKnownDirections)) {
        // A lane VietMap gave no known direction keeps its place with a short mark.
        [lines moveToPoint:CGPointMake(14,foot)]; [lines addLineToPoint:CGPointMake(14,19)];
        return 0;
    }
    if (straight) {
        [lines moveToPoint:CGPointMake(x,foot)]; [lines addLineToPoint:CGPointMake(x,8)];
        head(CGPointMake(x,1.5),CGPointMake(x-headWidth,7.5),CGPointMake(x+headWidth,7.5));
        minX=MIN(minX,x-headWidth); maxX=MAX(maxX,x+headWidth);
    }
    CGFloat side=straight ? (uLeft || uRight ? 11.5 : 14) : (uLeft || uRight ? 8 : 9);
    for (int sign=1;sign>=-1;sign-=2) {
        if (!(sign>0 ? right : left)) continue;
        CGFloat tip=sign>0 ? 26.5 : 1.5, base=tip-sign*headLength;
        [lines moveToPoint:CGPointMake(x,foot)]; [lines addLineToPoint:CGPointMake(x,side+4)];
        [lines addQuadCurveToPoint:CGPointMake(x+sign*4,side) controlPoint:CGPointMake(x,side)];
        [lines addLineToPoint:CGPointMake(base,side)];
        head(CGPointMake(tip,side),CGPointMake(base,side-headWidth),CGPointMake(base,side+headWidth));
        minX=MIN(minX,MIN(tip,base)); maxX=MAX(maxX,MAX(tip,base));
    }
    for (int sign=-1;sign<=1;sign+=2) {
        if (!(sign<0 ? uLeft : uRight)) continue;
        CGFloat radius, top, width, length;
        if (!(straight || left || right)) { radius=5; top=5; width=headWidth; length=headLength; }
        else if (left || right) { radius=3.5; top=straight ? 17.5 : 15; width=3.8; length=5; }
        else { radius=4; top=12.5; width=headWidth; length=headLength; }
        CGFloat hook=x+sign*2*radius, spring=top+radius;
        CGFloat base=left || right ? MIN(spring+1.5,foot-length) : straight ? spring+2 : spring+5;
        [lines moveToPoint:CGPointMake(x,foot)]; [lines addLineToPoint:CGPointMake(x,spring)];
        // Over the top of the hook: anticlockwise to the left, clockwise to the right.
        [lines addArcWithCenter:CGPointMake(x+sign*radius,spring) radius:radius startAngle:sign<0 ? 0 : M_PI
            endAngle:sign<0 ? -M_PI : 2*M_PI clockwise:sign>0];
        [lines addLineToPoint:CGPointMake(hook,base+0.5)];
        head(CGPointMake(hook,base+length),CGPointMake(hook-width,base),CGPointMake(hook+width,base));
        minX=MIN(minX,hook-width); maxX=MAX(maxX,hook+width);
    }
    return (28-(minX+maxX))/2;
}
static void DrawLane(NSUInteger code, CGRect box, UIColor *color) {
    UIBezierPath *lines=[UIBezierPath bezierPath], *heads=[UIBezierPath bezierPath];
    CGFloat shift=LanePaths(code,lines,heads), unit=box.size.width/28;
    CGContextRef context=UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    CGContextTranslateCTM(context,box.origin.x+shift*unit,box.origin.y);
    CGContextScaleCTM(context,unit,unit);
    lines.lineWidth=2.6; lines.lineCapStyle=kCGLineCapRound; lines.lineJoinStyle=kCGLineJoinRound;
    heads.lineWidth=0.6; heads.lineJoinStyle=kCGLineJoinRound;
    [color setStroke]; [color setFill];
    [lines stroke]; [heads fill]; [heads stroke];
    CGContextRestoreGState(context);
}

// A lane's speed limit sign, as VietMap draws them: a white disc with the red ring and the limit,
// "--" when the sign has no number (0 or -1), and grey with the number for -2 or less.
static void DrawLaneLimit(NSInteger limit, CGPoint centre, CGFloat diameter) {
    BOOL dimmed=limit<=-2;
    NSInteger number=limit>=1 ? limit : dimmed ? -limit : 0;
    CGFloat ring=diameter*0.14;
    UIBezierPath *disc=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(centre.x-diameter/2+ring/2,
        centre.y-diameter/2+ring/2,diameter-ring,diameter-ring)];
    [(dimmed ? GVMHaloColor(0x9D9DA8,1) : UIColor.whiteColor) setFill]; [disc fill];
    disc.lineWidth=ring; [GVMHaloColor(dimmed ? 0x434656 : GVMHaloSignRed,1) setStroke]; [disc stroke];
    NSString *text=number ? [NSString stringWithFormat:@"%ld",(long)number] : @"--";
    NSAttributedString *label=GVMHaloText(text,GVMHaloNumberFont(diameter*(text.length>2 ? 0.42 : 0.54)),
        GVMHaloColor(dimmed ? 0x29292E : GVMHaloInk900,1),0);
    CGSize size=label.size;
    [label drawAtPoint:CGPointMake(centre.x-size.width/2,centre.y-size.height/2)];
}

// Drawn like the rectangular QCVN signs of the icon set (design/icons-halo): a blue panel (#005BAA)
// with an inset white rim and white arrows and lane lines, the same shade on its lower right and the
// same crisp drop shadow. Proportions follow the set's 164-unit panel: corner 16, rim 8 inset by 6,
// shade 14, shadow 12 at 45%.
static const uint32_t GVMLaneSignBlue=0x005BAA;
@implementation GVMHaloLaneStrip {
    // Distance of the first countdown message for these lanes, so the tag fills on the approach.
    double _approachStart;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    GVMHaloRegisterFonts();
    self.backgroundColor=UIColor.clearColor; self.opaque=NO; self.userInteractionEnabled=NO;
    self.layer.shadowColor=GVMHaloColor(GVMHaloInk900,1).CGColor; self.layer.shadowOpacity=0.45;
    self.layer.shadowRadius=0;
    return self;
}
- (void)setLanes:(NSDictionary *)lanes {
    if ((_lanes==lanes) || [_lanes isEqual:lanes]) return;
    id meters=lanes[@"distance"];
    BOOL sameLanes=[_lanes[@"items"] isEqual:lanes[@"items"]];
    if (![meters isKindOfClass:NSNumber.class]) _approachStart=0;
    else if (!sameLanes || [meters doubleValue]>_approachStart) _approachStart=[meters doubleValue];
    _lanes=[lanes copy];
    [self setNeedsDisplay];
}
- (void)setWithoutLimits:(BOOL)withoutLimits {
    if (_withoutLimits==withoutLimits) return;
    _withoutLimits=withoutLimits;
    [self setNeedsDisplay];
}
- (void)setScale:(double)scale {
    if (_scale==scale) return;
    _scale=scale;
    GVMLaneStripMetrics strip=GVMLaneStripMetricsFor(1,NO);
    self.layer.shadowOffset=CGSizeMake(0,12*strip.plate/164*scale);
    [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
    (void)rect;
    NSArray<NSDictionary *> *items=self.lanes[@"items"];
    if (![items isKindOfClass:NSArray.class] || !items.count || self.scale<=0) return;
    id meters=self.lanes[@"distance"];
    NSUInteger options=GVMLaneStripOptionsFor(self.lanes);
    if (self.withoutLimits) options&=~(NSUInteger)GVMLaneStripLimits;
    BOOL tagged=(options&GVMLaneStripTagged)!=0, arrows=!(options&GVMLaneStripLimitsOnly);
    GVMLaneStripMetrics strip=GVMLaneStripMetricsFor(items.count,options);
    // The panel keeps the arrow sign's proportions (corners, rim, shade) whatever its height.
    CGFloat unit=(strip.arrow+20)/164, radius=16*unit, rim=8*unit, inset=6*unit, shade=14*unit;
    CGFloat plateWidth=GVMLanePlateWidth(strip,items.count);
    CGContextRef context=UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    CGContextScaleCTM(context,self.scale,self.scale);
    // A single lane is narrower than the tag; its panel then sits in the middle of the strip.
    CGContextTranslateCTM(context,(strip.width-plateWidth)/2,0);
    CGRect plateRect=CGRectMake(0,0,plateWidth,strip.plate);
    UIBezierPath *plate=[UIBezierPath bezierPathWithRoundedRect:plateRect cornerRadius:radius];
    [GVMHaloColor(GVMLaneSignBlue,1) setFill]; [plate fill];
    // A lane to use stands out only when the route rules some lanes out.
    BOOL choosing=NO;
    for (NSDictionary *item in items) if (![item[@"enabled"] boolValue]) choosing=YES;
    UIColor *white=UIColor.whiteColor;
    CGContextSaveGState(context);
    [plate addClip];
    for (NSUInteger i=0;i<items.count;i++) {
        CGFloat x=5+i*strip.cell;
        BOOL enabled=[items[i][@"enabled"] boolValue];
        if (choosing && enabled) {
            [[white colorWithAlphaComponent:0.16] setFill];
            UIRectFill(CGRectMake(x,0,strip.cell,strip.plate));
        }
    }
    UIBezierPath *rimPath=[UIBezierPath bezierPathWithRoundedRect:CGRectInset(plateRect,inset+rim/2,inset+rim/2)
        cornerRadius:MAX(0,radius-inset-rim/2)];
    rimPath.lineWidth=rim; [white setStroke]; [rimPath stroke];
    for (NSUInteger i=0;i<items.count;i++) {
        CGFloat x=5+i*strip.cell;
        BOOL enabled=[items[i][@"enabled"] boolValue];
        if (i) {
            UIBezierPath *line=[UIBezierPath bezierPath];
            [line moveToPoint:CGPointMake(x,inset+rim+2)]; [line addLineToPoint:CGPointMake(x,strip.plate-inset-rim-2)];
            CGFloat dash[]={3.5,3}; [line setLineDash:dash count:2 phase:0]; line.lineWidth=1.5;
            [[white colorWithAlphaComponent:0.75] setStroke]; [line stroke];
        }
        if (arrows) DrawLane([items[i][@"code"] unsignedIntegerValue],CGRectMake(x+2,7,strip.arrow,strip.arrow),
            enabled ? white : [white colorWithAlphaComponent:0.45]);
        if (strip.sign>0)
            DrawLaneLimit([items[i][@"limit"] integerValue],CGPointMake(x+strip.cell/2,strip.signTop+strip.sign/2),strip.sign);
    }
    // The sign stickers' shade: the panel less itself moved up and left.
    UIBezierPath *band=[UIBezierPath bezierPathWithRect:plateRect];
    [band appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectOffset(plateRect,-shade,-shade) cornerRadius:radius]];
    band.usesEvenOddFillRule=YES;
    [GVMHaloColor(GVMHaloInk900,0.2) setFill]; [band fill];
    CGContextRestoreGState(context);
    if (tagged) {
        CGFloat progress=_approachStart>0 ? MAX(0,MIN(1,1-[meters doubleValue]/_approachStart)) : 0;
        GVMHaloDrawDistanceTag(plateWidth/2,strip.plate-9,meters,progress);
    }
    CGContextRestoreGState(context);
}
@end
