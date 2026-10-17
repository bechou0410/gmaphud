#import "speed-presentation.h"
#import "placement-state.h"
#import "source-output.h"
#include <math.h>
#include <string.h>
static const double GVMModuleExtent=88, GVMCardPadding=4;
const double GVMHaloPadding=8, GVMHaloDialBlock=92, GVMHaloDial=72, GVMHaloGap=8;
const double GVMHaloBadge=41.57, GVMHaloBadgeInset=3, GVMHaloBadgeDrop=8;
const double GVMHaloAlertWidth=72, GVMHaloAlertHeight=76, GVMHaloAlertSign=58, GVMHaloAlertSignTop=2;
// The dial sits 7 below the block top so the limit badge can rise above it; beside it, alert
// signs share its centre.
static const double GVMHaloDialTop=7;

static double AlertStep(BOOL vertical) { return GVMHaloGap+(vertical ? GVMHaloAlertHeight : GVMHaloAlertWidth); }
// Width of the stacked alert row and of the stack content (the wider of the dial and that row).
static double StackRow(NSUInteger alerts) { return alerts ? alerts*GVMHaloAlertWidth+(alerts-1)*GVMHaloGap : 0; }
static double StackWidth(NSUInteger alerts) { return MAX(GVMHaloDialBlock,StackRow(alerts)); }
GVMHaloArrangement GVMHaloArrangementFor(GVMCardSize size) {
    return size.stacked ? GVMHaloStack : size.compact ? GVMHaloColumn : GVMHaloRow;
}
GVMCardSize GVMHaloCanvasSize(GVMHaloArrangement arrangement,NSUInteger alerts) {
    alerts=MIN(alerts,2);
    if (arrangement==GVMHaloStack)
        return (GVMCardSize){StackWidth(alerts)+2*GVMHaloPadding,
            GVMHaloDialBlock+(alerts ? GVMHaloGap+GVMHaloAlertHeight : 0)+2*GVMHaloPadding,NO,YES};
    BOOL vertical=arrangement==GVMHaloColumn;
    double length=GVMHaloDialBlock+alerts*AlertStep(vertical)+2*GVMHaloPadding;
    double breadth=GVMHaloDialBlock+2*GVMHaloPadding;
    return (GVMCardSize){vertical ? breadth : length,vertical ? length : breadth,vertical,NO};
}
GVMCardSize GVMCardCanvasSize(GVMInterfaceStyle style,NSUInteger alerts,BOOL vertical) {
    if (style==GVMInterfaceHalo) return GVMHaloCanvasSize(vertical ? GVMHaloColumn : GVMHaloRow,alerts);
    double length=(2+MIN(alerts,2))*GVMModuleExtent+2*GVMCardPadding;
    double breadth=GVMModuleExtent+2*GVMCardPadding;
    return (GVMCardSize){vertical ? breadth : length,vertical ? length : breadth,vertical,NO};
}
GVMModuleRect GVMModuleFrame(NSArray<NSString *> *order,NSString *module,BOOL vertical,
    NSUInteger alerts,NSUInteger alertIndex) {
    alerts=MIN(alerts,2);
    if ([module isEqual:@"alerts"] && alertIndex>=alerts) return (GVMModuleRect){0,0,0,0};
    double cursor=GVMCardPadding;
    for (NSString *item in GVMNormalizeModuleOrder(order,vertical)) {
        if ([item isEqual:module]) {
            if ([item isEqual:@"alerts"]) cursor+=alertIndex*GVMModuleExtent;
            return (GVMModuleRect){vertical ? GVMCardPadding : cursor,
                vertical ? cursor : GVMCardPadding,GVMModuleExtent,GVMModuleExtent};
        }
        cursor+=GVMModuleExtent*([item isEqual:@"alerts"] ? alerts : 1);
    }
    return (GVMModuleRect){0,0,0,0};
}
GVMModuleRect GVMHaloDialFrame(GVMHaloArrangement arrangement,BOOL alertsFirst,BOOL trailing,NSUInteger alerts) {
    alerts=MIN(alerts,2);
    if (arrangement==GVMHaloStack) {
        double top=GVMHaloPadding+(alertsFirst && alerts ? GVMHaloAlertHeight+GVMHaloGap : 0);
        double left=GVMHaloPadding+(trailing ? StackWidth(alerts)-GVMHaloDialBlock : 0);
        return (GVMModuleRect){left,top,GVMHaloDialBlock,GVMHaloDialBlock};
    }
    BOOL vertical=arrangement==GVMHaloColumn;
    double lead=GVMHaloPadding+(alertsFirst ? alerts*AlertStep(vertical) : 0);
    return (GVMModuleRect){vertical ? GVMHaloPadding : lead,vertical ? lead : GVMHaloPadding,
        GVMHaloDialBlock,GVMHaloDialBlock};
}
GVMModuleRect GVMHaloAlertFrame(GVMHaloArrangement arrangement,BOOL alertsFirst,BOOL trailing,NSUInteger alerts,NSUInteger index) {
    alerts=MIN(alerts,2);
    if (index>=alerts) return (GVMModuleRect){0,0,0,0};
    if (arrangement==GVMHaloStack) {
        double left=GVMHaloPadding+(trailing ? StackWidth(alerts)-StackRow(alerts) : 0)+index*(GVMHaloAlertWidth+GVMHaloGap);
        double top=GVMHaloPadding+(alertsFirst ? 0 : GVMHaloDialBlock+GVMHaloGap);
        return (GVMModuleRect){left,top,GVMHaloAlertWidth,GVMHaloAlertHeight};
    }
    BOOL vertical=arrangement==GVMHaloColumn;
    double lead=GVMHaloPadding+(alertsFirst ? 0 : GVMHaloDialBlock+GVMHaloGap)+index*AlertStep(vertical);
    if (vertical) return (GVMModuleRect){GVMHaloPadding+(GVMHaloDialBlock-GVMHaloAlertWidth)/2,lead,GVMHaloAlertWidth,GVMHaloAlertHeight};
    double centre=GVMHaloPadding+GVMHaloDialTop+GVMHaloDial/2;
    return (GVMModuleRect){lead,centre-GVMHaloAlertSignTop-GVMHaloAlertSign/2,GVMHaloAlertWidth,GVMHaloAlertHeight};
}
const double GVMLaneMinimumArrow=14;
GVMLaneStripMetrics GVMLaneStripMetricsFor(NSUInteger lanes,BOOL tagged) {
    double cell=lanes<=6 ? 30 : lanes<=8 ? 26 : 22, arrow=cell-4, plate=arrow+20;
    // The tag is 18 high, centred on the plate's bottom edge, and at least 56 wide; its 1-point stroke
    // reaches half a point beyond, so the strip keeps a point more on each side it touches.
    double width=10+lanes*cell;
    return (GVMLaneStripMetrics){cell,arrow,plate,tagged ? MAX(width,58) : width,tagged ? plate+10 : plate};
}
double GVMLanePlateWidth(GVMLaneStripMetrics strip,NSUInteger lanes) { return 10+lanes*strip.cell; }
GVMLaneStripLayout GVMLaneStripLayoutFor(GVMModuleRect card,double cardScale,GVMHaloArrangement arrangement,
    GVMModuleRect dial,BOOL right,BOOL bottom,NSUInteger lanes,BOOL tagged,GVMModuleRect area,double reachWidth,double reachHeight) {
    GVMLaneStripLayout none={{0,0,0,0},0,GVMLaneStripHidden};
    if (!lanes || lanes>GVMMaximumLanes || !isfinite(cardScale) || cardScale<=0 || area.width<=0 || area.height<=0 ||
        !isfinite(reachWidth) || !isfinite(reachHeight)) return none;
    GVMLaneStripMetrics strip=GVMLaneStripMetricsFor(lanes,tagged);
    double floorScale=GVMLaneMinimumArrow/strip.arrow, start=MAX(cardScale,floorScale);
    // The corner region the bubble and its lanes may use.
    double regionWidth=MIN(area.width,MAX(area.width*reachWidth,card.width));
    double regionHeight=MIN(area.height,MAX(area.height*reachHeight,card.height));
    double regionLeft=right ? area.x+area.width-regionWidth : area.x, regionRight=regionLeft+regionWidth;
    double regionTop=bottom ? area.y+area.height-regionHeight : area.y, regionBottom=regionTop+regionHeight;
    // The dial circle inside its block, and which side of the card the dial is on.
    double circleLeft=dial.x+(GVMHaloDialBlock-GVMHaloDial)/2*cardScale, circleRight=circleLeft+GVMHaloDial*cardScale;
    double circleMiddle=dial.y+(GVMHaloDialTop+GVMHaloDial/2)*cardScale;
    BOOL dialRight=dial.x+dial.width/2>card.x+card.width/2;
    GVMLaneStripPlace order[2]={bottom ? GVMLaneStripAbove : GVMLaneStripBelow,GVMLaneStripHidden};
    if (arrangement==GVMHaloColumn) { order[1]=order[0]; order[0]=GVMLaneStripBeside; }
    for (NSUInteger i=0;i<2 && order[i]!=GVMLaneStripHidden;i++) {
        GVMLaneStripPlace place=order[i];
        double scale=start, gap=GVMHaloGap*cardScale;
        if (place==GVMLaneStripBeside) {
            double edge=right ? circleLeft-gap : circleRight+gap;
            // On the dial's right the strip starts under the limit badge; on its left it is centred.
            double badgeBottom=dial.y+(GVMHaloDialTop+GVMHaloBadgeDrop+GVMHaloBadge/2+2)*cardScale;
            scale=MIN(scale,(right ? edge-regionLeft : regionRight-edge)/strip.width);
            scale=MIN(scale,right ? 2*MIN(circleMiddle-regionTop,regionBottom-circleMiddle)/strip.height :
                MIN(2*(circleMiddle-regionTop),regionBottom-badgeBottom)/strip.height);
            if (scale<floorScale-1e-9) continue;
            double width=strip.width*scale, height=strip.height*scale;
            double y=right ? circleMiddle-height/2 : MAX(circleMiddle-height/2,badgeBottom);
            return (GVMLaneStripLayout){{right ? edge-width : edge,y,width,height},scale,place};
        }
        scale=MIN(scale,regionWidth/strip.width);
        scale=MIN(scale,(place==GVMLaneStripBelow ? regionBottom-(card.y+card.height) : card.y-regionTop)/strip.height);
        if (scale<floorScale-1e-9) continue;
        double width=strip.width*scale, height=strip.height*scale;
        // Lined up with the dial's outer edge, kept inside the region.
        double x=dialRight ? dial.x+dial.width-width : dial.x;
        x=MAX(regionLeft,MIN(regionRight-width,x));
        double y=place==GVMLaneStripBelow ? card.y+card.height : card.y-height;
        return (GVMLaneStripLayout){{x,y,width,height},scale,place};
    }
    return none;
}
GVMEffectDock GVMEffectDockFor(GVMModuleRect slot,NSUInteger signs,NSUInteger lanes,BOOL tagged,double cardScale) {
    GVMEffectDock none;
    memset(&none,0,sizeof none);
    if (!(slot.width>0) || !(slot.height>0) || !isfinite(cardScale) || cardScale<=0 || lanes>GVMMaximumLanes) return none;
    const double gap=6, minimumSign=20;
    GVMLaneStripMetrics strip=GVMLaneStripMetricsFor(lanes,tagged);
    double floorScale=lanes ? GVMLaneMinimumArrow/strip.arrow : 0;
    for (int withLanes=lanes ? 1 : 0;withLanes>=0;withLanes--) {
        for (NSInteger n=MIN(signs,2);n>=0;n--) {
            if (!n && !withLanes) continue;
            double d=MIN(slot.height,GVMHaloAlertSign*cardScale);
            double s=withLanes ? MIN(slot.height/strip.height,MAX(cardScale,floorScale)) : 0;
            if ((n && d<minimumSign) || (withLanes && s<floorScale-1e-9)) continue;
            double joint=n && withLanes ? gap : 0;
            double signsWidth=n ? n*d+(n-1)*gap : 0, laneWidth=strip.width*s;
            if (signsWidth+joint+laneWidth>slot.width+1e-9) {
                // The strip gives way first, down to its minimum arrows, then the signs.
                if (withLanes) { s=MAX(floorScale,MIN(s,(slot.width-signsWidth-joint)/strip.width)); laneWidth=strip.width*s; }
                if (n && signsWidth+joint+laneWidth>slot.width+1e-9) {
                    d=(slot.width-joint-laneWidth-(n-1)*gap)/n;
                    if (d<minimumSign) continue;
                    signsWidth=n*d+(n-1)*gap;
                }
                if (signsWidth+joint+laneWidth>slot.width+1e-9) continue;
            }
            GVMEffectDock dock;
            memset(&dock,0,sizeof dock);
            dock.signs=(NSUInteger)n; dock.lanes=withLanes; dock.diameter=n ? d : 0;
            double x=slot.x, middle=slot.y+slot.height/2;
            for (NSInteger i=0;i<n;i++) { dock.signFrames[i]=(GVMModuleRect){x,middle-d/2,d,d}; x+=d+gap; }
            if (withLanes) { dock.strip=(GVMModuleRect){x,middle-strip.height*s/2,laneWidth,strip.height*s}; dock.stripScale=s; }
            return dock;
        }
    }
    return none;
}
BOOL GVMAlertsFirst(NSArray<NSString *> *order) {
    return [order isKindOfClass:NSArray.class] && [order.firstObject isEqual:@"alerts"];
}
GVMWarning GVMWarningFor(NSNumber *speed, NSNumber *limit) {
    if (!speed || !limit || limit.doubleValue <= 0) return GVMWarningNormal;
    if (speed.doubleValue > limit.doubleValue) return GVMWarningOver;
    return speed.doubleValue >= MAX(0, limit.doubleValue - 5) ? GVMWarningNear : GVMWarningNormal;
}
double GVMProgressFor(NSNumber *speed, NSNumber *limit) {
    if (!speed || !limit || limit.doubleValue <= 0) return 0;
    return MIN(1, MAX(0, speed.doubleValue / limit.doubleValue));
}

GVMCardSize GVMCardSizeFor(GVMInterfaceStyle style, double availableWidth, double availableHeight,
    double screenWidth, double screenHeight, NSUInteger cameraCount) {
    return GVMCarPlayCardSizeForView(style,availableWidth,availableHeight,availableWidth,screenWidth,screenHeight,cameraCount);
}
static GVMCardSize GVMCarPlayCardSize(GVMInterfaceStyle style,double availableWidth,double availableHeight,
    double screenWidth,double screenHeight,NSUInteger alertCount,BOOL vertical) {
    GVMCardSize canvas=GVMCardCanvasSize(style,alertCount,vertical);
    double canvasWidth=canvas.width,canvasHeight=canvas.height;
    double displayScale=MIN(1.4,MAX(0.75,MIN(screenWidth/400,screenHeight/240)));
    if (style!=GVMInterfaceHalo) {
        GVMCardSize baseCanvas=GVMCardCanvasSize(style,0,vertical);
        double scale=(vertical ? 30.0/baseCanvas.width : 96.0/baseCanvas.width)*displayScale;
        double widthFraction=vertical ? 0.20 : 0.38;
        double heightFraction=vertical ? (alertCount>=2 ? 0.52 : 0.38) : 0.24;
        scale=MIN(scale,MIN(availableWidth*widthFraction/canvasWidth,availableHeight*heightFraction/canvasHeight));
        return (GVMCardSize){canvasWidth*scale,canvasHeight*scale,vertical,NO};
    }
    // Halo L: a 72-point dial on an 800 x 480 CarPlay screen (display scale 1.4).
    double scale=displayScale/1.4;
    // Fit the two-alert group so arriving alerts never shrink the dial.
    GVMCardSize full=GVMCardCanvasSize(style,2,vertical);
    double widthFraction=vertical ? 0.20 : 0.42;
    double heightFraction=vertical ? 0.52 : 0.26;
    scale=MIN(scale,MIN(availableWidth*widthFraction/full.width,availableHeight*heightFraction/full.height));
    return (GVMCardSize){canvasWidth*scale,canvasHeight*scale,vertical,NO};
}
// New UI at a chosen scale: keep the chosen layout while it fits; otherwise stack the alerts under
// the dial when that keeps the bubble larger; shrink only as far as the better of the two needs.
static GVMCardSize HaloFit(double requested,BOOL vertical,NSUInteger alerts,double width,double height) {
    GVMCardSize chosen=GVMHaloCanvasSize(vertical ? GVMHaloColumn : GVMHaloRow,alerts);
    double fit=MIN(width/chosen.width,height/chosen.height);
    if (requested>fit && MIN(alerts,2)) {
        GVMCardSize stack=GVMHaloCanvasSize(GVMHaloStack,alerts);
        double stackFit=MIN(width/stack.width,height/stack.height);
        if (stackFit>fit) {
            double scale=MIN(requested,stackFit);
            return (GVMCardSize){stack.width*scale,stack.height*scale,vertical,YES};
        }
    }
    double scale=MIN(requested,fit);
    return (GVMCardSize){chosen.width*scale,chosen.height*scale,vertical,NO};
}
GVMCardSize GVMCarPlayCardSizeForView(GVMInterfaceStyle style,double availableWidth,double availableHeight,
    double viewWidth,double screenWidth,double screenHeight,NSUInteger cameraCount) {
    if (!isfinite(availableWidth) || !isfinite(availableHeight) ||
        !isfinite(screenWidth) || !isfinite(screenHeight) || !isfinite(viewWidth) || viewWidth<=0 ||
        availableWidth <= 0 || availableHeight <= 0 ||
        screenWidth <= 0 || screenHeight <= 0) return (GVMCardSize){0,0,NO,NO};
    // Classify the actual map viewport, before navigation controls reserve space.
    // Guidance panels must not turn a full-map card into a Dashboard card.
    BOOL compact=viewWidth/screenWidth<0.72;
    // Reserve the majority of the viewport for navigation, including short screens.
    return GVMCarPlayCardSize(style,availableWidth,availableHeight,screenWidth,screenHeight,cameraCount,compact);
}
GVMCardOrigin GVMCardOriginFor(double left, double right, double top, double bottom,
    GVMCardSize size, GVMCardPlacement placement) {
    BOOL atLeft = placement == GVMCardTopLeft || placement == GVMCardBottomLeft;
    BOOL atBottom = placement == GVMCardBottomLeft || placement == GVMCardBottomRight;
    GVMCardOrigin origin = {atLeft ? left : MAX(left,right-size.width),
        atBottom ? MAX(top,bottom-size.height) : top};
    return origin;
}
GVMCardOrigin GVMClampCardOrigin(GVMCardOrigin origin,GVMCardSize size,
    double left,double right,double top,double bottom) {
    origin.x=MAX(left,MIN(MAX(left,right-size.width),origin.x));
    origin.y=MAX(top,MIN(MAX(top,bottom-size.height),origin.y));
    return origin;
}

GVMCardSize GVMScaleCardSize(GVMCardSize size,double percent,double width,double height) {
    if (!isfinite(percent)) percent=100;
    if (!isfinite(width) || !isfinite(height) || width<=0 || height<=0 || size.width<=0 || size.height<=0)
        return (GVMCardSize){0,0,size.compact,NO};
    double scale=MAX(GVMSizePercentMin,MIN(GVMSizePercentMax,percent))/100.0;
    scale=MIN(scale,MIN(width/size.width,height/size.height));
    return (GVMCardSize){size.width*scale,size.height*scale,size.compact,size.stacked};
}

GVMCardSize GVMPhoneCardSizeFor(GVMInterfaceStyle style,double width,double height,NSUInteger alerts) {
    return GVMPhoneCardSizeForLayout(style,width,height,alerts,0);
}
GVMCardSize GVMPhoneCardSizeForLayout(GVMInterfaceStyle style,double width,double height,NSUInteger alerts,NSUInteger layout) {
    if (!isfinite(width) || !isfinite(height) || width<=0 || height<=0) return (GVMCardSize){0,0,NO,NO};
    BOOL compact=layout==2 || (layout!=1 && height>width);
    GVMCardSize canvas=GVMCardCanvasSize(style,alerts,compact);
    double canvasWidth=canvas.width,canvasHeight=canvas.height;
    if (style!=GVMInterfaceHalo) {
        double scale=compact ? 0.55 : 0.70;
        scale=MIN(scale,MIN(width*0.6/canvasWidth,height*0.65/canvasHeight));
        return (GVMCardSize){canvasWidth*scale,canvasHeight*scale,compact,NO};
    }
    // Halo S: a 58-point dial on iPhone.
    GVMCardSize full=GVMCardCanvasSize(style,2,compact);
    double scale=58.0/GVMHaloDial;
    scale=MIN(scale,MIN(width*0.6/full.width,height*0.65/full.height));
    return (GVMCardSize){canvasWidth*scale,canvasHeight*scale,compact,NO};
}

GVMCardOrigin GVMPhoneCardOriginFor(double left,double right,double top,double bottom,
    GVMCardSize size,GVMCardPlacement placement,double offsetX,double offsetY) {
    GVMCardOrigin origin=GVMCardOriginFor(left,right,top,bottom,size,placement);
    origin.x+=offsetX;
    origin.y+=offsetY;
    return GVMClampCardOrigin(origin,size,left,right,top,bottom);
}

GVMCardSize GVMCarPlayCardSizeForLayout(GVMInterfaceStyle style,double width,double height,double screenWidth,double screenHeight,NSUInteger alerts,BOOL dashboard,NSUInteger layout,double percent) {
    if (!isfinite(width) || !isfinite(height) || !isfinite(screenWidth) || !isfinite(screenHeight) ||
        width<=0 || height<=0 || screenWidth<=0 || screenHeight<=0) return (GVMCardSize){0,0,NO,NO};
    BOOL vertical=layout==2 || (layout!=1 && dashboard);
    if (!isfinite(percent)) percent=100;
    double chosen=MAX(GVMSizePercentMin,MIN(GVMSizePercentMax,percent))/100.0;
    if (!dashboard) {
        GVMCardSize base=GVMCarPlayCardSize(style,width,height,screenWidth,screenHeight,alerts,vertical);
        if (style!=GVMInterfaceHalo) return GVMScaleCardSize(base,percent,width,height);
        return HaloFit(base.width/GVMCardCanvasSize(style,alerts,vertical).width*chosen,vertical,alerts,width,height);
    }
    GVMCardSize canvas=GVMCardCanvasSize(style,alerts,vertical);
    GVMCardSize horizontal=GVMCardCanvasSize(style,2,NO),upright=GVMCardCanvasSize(style,2,YES);
    double displayScale=MIN(1.4,MAX(0.75,MIN(screenWidth/400,screenHeight/240)));
    // Halo M is a 64-point dial in the Dashboard map tile; Classic keeps its 0.2.3 scale.
    double scale=style==GVMInterfaceHalo ? displayScale/1.4*64.0/GVMHaloDial :
        30.0/GVMCardCanvasSize(style,0,YES).width*displayScale;
    // 100% is the largest size at which the two-alert group fits in either arrangement, so up to
    // 100% arriving alerts and layout changes only change the group length, never the module scale.
    scale=MIN(scale,MIN(width/MAX(horizontal.width,upright.width),height/MAX(horizontal.height,upright.height)));
    scale*=chosen;
    if (style==GVMInterfaceHalo) return HaloFit(scale,vertical,alerts,width,height);
    // Larger sizes are kept as chosen while what is on screen fits the tile, and shrink only as
    // far as the alerts currently shown need.
    scale=MIN(scale,MIN(width/canvas.width,height/canvas.height));
    return (GVMCardSize){canvas.width*scale,canvas.height*scale,vertical,NO};
}
