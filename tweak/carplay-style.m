#import "carplay-style.h"
#import "speed-presentation.h"
#import <objc/runtime.h>

@interface GVMSpeedCard : UIView
@property(nonatomic, copy) NSNumber *speed, *limit;
@property(nonatomic) BOOL night, compact;
@end

static UIColor *RGB(unsigned value, CGFloat alpha) {
    return [UIColor colorWithRed:((value >> 16) & 255)/255.0 green:((value >> 8) & 255)/255.0
        blue:(value & 255)/255.0 alpha:alpha];
}
static void Text(NSString *text, CGRect rect, CGFloat size, UIFontWeight weight, UIColor *color) {
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentCenter;
    [text drawInRect:rect withAttributes:@{NSFontAttributeName:[UIFont monospacedDigitSystemFontOfSize:size weight:weight],
        NSForegroundColorAttributeName:color, NSParagraphStyleAttributeName:paragraph}];
}
@implementation GVMSpeedCard
- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    CGContextScaleCTM(context, self.bounds.size.width/(self.compact ? 84 : 232),
        self.bounds.size.height/(self.compact ? 164 : 88));
    GVMWarning warning = GVMWarningFor(self.speed, self.limit);
    BOOL over = warning == GVMWarningOver, near = warning == GVMWarningNear;
    UIColor *normal = self.night ? UIColor.whiteColor : RGB(0x202124, 1);
    UIColor *accent = over ? RGB(self.night ? 0xff555b : 0xc5221f, 1) : near ? RGB(self.night ? 0xffc107 : 0x9c6500, 1) : normal;
    UIColor *muted = self.night ? RGB(0xc3c6ce, 1) : RGB(0x5f6368, 1);
    UIColor *surface = over ? RGB(self.night ? 0x48191d : 0xffe5e5, 0.60) : RGB(self.night ? 0x191e28 : 0xffffff, 0.60);
    if (self.compact) {
        UIBezierPath *stack = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(1,1,82,162) cornerRadius:41];
        [RGB(self.night ? 0x191e28 : 0xffffff,0.60) setFill]; [stack fill];
        [RGB(self.night ? 0xffffff : 0x202124,0.1) setStroke];
        stack.lineWidth=1; [stack stroke];
        UIBezierPath *sign = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(12,13,60,60)];
        sign.lineWidth=self.limit ? 6 : 2.5;
        if (self.limit) { [UIColor.whiteColor setFill]; [sign fill]; [RGB(0xe9222c,1) setStroke]; }
        else { CGFloat dash[]={5,3}; [sign setLineDash:dash count:2 phase:0]; [muted setStroke]; }
        [sign stroke];
        Text(self.limit ? self.limit.stringValue : @"–",CGRectMake(9,24,66,42),32,
            UIFontWeightBold,self.limit ? RGB(0x1c1d20,1) : muted);
        UIBezierPath *speedDisc = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(10.5,92.5,63,63)];
        [RGB(over ? 0xe9222c : (self.night ? 0xffffff : 0x202124),over ? 0.60 : 0.06) setFill];
        [speedDisc fill];
        [(over || near ? accent : RGB(self.night ? 0xffffff : 0x202124,0.3)) setStroke];
        speedDisc.lineWidth=3; [speedDisc stroke];
        Text(self.speed ? self.speed.stringValue : @"--",CGRectMake(10,106,64,37),28,
            UIFontWeightBold,self.speed ? (over ? UIColor.whiteColor : accent) : muted);
        Text(@"km/h",CGRectMake(20,140,44,14),10.5,UIFontWeightSemibold,over ? UIColor.whiteColor : muted);
        CGContextRestoreGState(context);
        return;
    }
    UIBezierPath *pill = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(1,1,230,86) cornerRadius:43];
    [surface setFill]; [pill fill];
    [(over ? RGB(0xff555b, 0.5) : (self.night ? RGB(0xffffff,0.10) : RGB(0x202124,0.10))) setStroke];
    pill.lineWidth=1; [pill stroke];
    UIBezierPath *sign = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(13.5,13.5,61,61)];
    sign.lineWidth = self.limit ? 7 : 2.5;
    if (self.limit) { [UIColor.whiteColor setFill]; [sign fill]; [RGB(0xe9222c,1) setStroke]; }
    else { CGFloat dash[]={5,3}; [sign setLineDash:dash count:2 phase:0]; [muted setStroke]; }
    [sign stroke];
    Text(self.limit ? self.limit.stringValue : @"–", CGRectMake(12,24,64,44), self.limit ? 32 : 29,
        UIFontWeightBold, self.limit ? RGB(0x1c1d20,1) : muted);
    Text(self.speed ? self.speed.stringValue : @"--", CGRectMake(85,8,120,56), 44, UIFontWeightBold,
        self.speed ? accent : muted);
    UIBezierPath *track = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(105,67,56,4) cornerRadius:2];
    [RGB(self.night ? 0xffffff : 0x202124,0.17) setFill]; [track fill];
    CGFloat progress = 56*GVMProgressFor(self.speed,self.limit);
    if (progress > 0) {
        [accent setFill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(105,67,progress,4) cornerRadius:2] fill];
    }
    Text(@"km/h", CGRectMake(166,61,44,20),13,UIFontWeightSemibold,muted);
    CGContextRestoreGState(context);
}
@end

static const void *cardKey = &cardKey;

static BOOL ExternalMap(UIView *map) {
    return NSThread.isMainThread && [map isKindOfClass:NSClassFromString(@"AZCarPlayView")] &&
        map.window && map.window.screen != UIScreen.mainScreen;
}
void GVMStyleNativeSpeedView(UIView *view) {
    UIView *owner = view.superview;
    while (owner && ![owner isKindOfClass:NSClassFromString(@"AZCarPlayView")]) owner=owner.superview;
    if (ExternalMap(owner)) view.alpha=0; // Keep Google's model/layout boundary, replace only its artwork.
}
CGRect GVMLayoutSpeedCard(UIView *map) {
    if (!ExternalMap(map)) return CGRectZero;
    CGFloat margin = 8;
    BOOL compact = map.bounds.size.width < 240;
    CGFloat width = compact ? 30 : 104;
    width = MIN(width, MAX(0,map.bounds.size.width-2*margin));
    // UIKit's safe area follows the actual top toolbar. Google's subview-aware
    // exclusions also include the left guidance tile, even when that bar hides.
    CGFloat top = map.safeAreaInsets.top;
    top += 8;
    CGRect frame = CGRectMake(CGRectGetMaxX(map.bounds)-width-margin,CGRectGetMinY(map.bounds)+top,
        width,compact ? width*164/84 : width*88/232);
    GVMSpeedCard *card = objc_getAssociatedObject(map,cardKey);
    if (card && card.compact!=compact) { card.compact=compact; [card setNeedsDisplay]; }
    if (card && !CGRectEqualToRect(card.frame,frame)) { card.frame=frame; [card setNeedsDisplay]; }
    return frame;
}
void GVMUpdateSpeedCard(UIView *map, NSNumber *speed, NSNumber *limit, BOOL night) {
    if (!ExternalMap(map)) return;
    GVMSpeedCard *card = objc_getAssociatedObject(map,cardKey);
    if (!card) {
        card = [[GVMSpeedCard alloc] initWithFrame:CGRectZero];
        card.backgroundColor=UIColor.clearColor; card.opaque=NO; card.userInteractionEnabled=NO;
        card.isAccessibilityElement=YES;
        card.layer.shadowColor=UIColor.blackColor.CGColor; card.layer.shadowOpacity=0.2;
        card.layer.shadowRadius=3; card.layer.shadowOffset=CGSizeMake(0,2);
        [map addSubview:card]; objc_setAssociatedObject(map,cardKey,card,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGRect frame = GVMLayoutSpeedCard(map);
    BOOL changed = !CGRectEqualToRect(card.frame,frame) || card.night!=night ||
        !((card.speed==speed)||[card.speed isEqual:speed]) || !((card.limit==limit)||[card.limit isEqual:limit]);
    card.frame=frame; card.speed=speed; card.limit=limit; card.night=night;
    if (changed) [card setNeedsDisplay];
    card.accessibilityLabel=[NSString stringWithFormat:@"Speed %@ km/h, limit %@ km/h", speed ?: @"unavailable",limit ?: @"unavailable"];
    [map bringSubviewToFront:card];
}
