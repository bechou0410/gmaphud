#import <Foundation/Foundation.h>
#import "speed-presentation.h"
#import "guidance-state.h"
#import "placement-state.h"
#include <assert.h>
#include <math.h>
static NSArray *Permutations(void) {
    return @[@[@"speed",@"limit",@"alerts"],@[@"speed",@"alerts",@"limit"],@[@"limit",@"speed",@"alerts"],@[@"limit",@"alerts",@"speed"],@[@"alerts",@"speed",@"limit"],@[@"alerts",@"limit",@"speed"]];
}
static void ClassicFrameTests(void) {
    for (NSArray *order in Permutations()) for (NSUInteger vertical=0;vertical<2;vertical++) for (NSUInteger alerts=0;alerts<3;alerts++) {
        GVMCardSize canvas=GVMCardCanvasSize(GVMInterfaceClassic,alerts,vertical);
        GVMModuleRect cells[4]={GVMModuleFrame(order,@"speed",vertical,alerts,0),
            GVMModuleFrame(order,@"limit",vertical,alerts,0)};
        for (NSUInteger i=0;i<alerts;i++) cells[2+i]=GVMModuleFrame(order,@"alerts",vertical,alerts,i);
        double area=0,minEdge=INFINITY,maxEdge=0;
        for (NSUInteger i=0;i<2+alerts;i++) {
            GVMModuleRect cell=cells[i];
            assert(cell.width==cells[0].width && cell.height==cells[0].height);
            assert(cell.width==88 && cell.height==88);
            assert(cell.x>=0 && cell.y>=0 && cell.x+cell.width<=canvas.width && cell.y+cell.height<=canvas.height);
            assert(vertical ? cell.x+cell.width/2==canvas.width/2 : cell.y+cell.height/2==canvas.height/2);
            area+=cell.width*cell.height;
            double start=vertical ? cell.y : cell.x;
            minEdge=MIN(minEdge,start); maxEdge=MAX(maxEdge,start+88);
            for (NSUInteger j=0;j<i;j++) {
                GVMModuleRect other=cells[j];
                assert(cell.x+cell.width<=other.x || other.x+other.width<=cell.x ||
                    cell.y+cell.height<=other.y || other.y+other.height<=cell.y);
            }
        }
        assert(minEdge==4 && maxEdge-minEdge==(2+alerts)*88);
        assert(area==(2+alerts)*88*88); // Every cell is accounted for; no gaps or reserved empty alert slot.
        if (alerts==2) assert(vertical ? cells[3].y-cells[2].y==88 : cells[3].x-cells[2].x==88);
        assert(GVMModuleFrame(order,@"alerts",vertical,alerts,alerts).width==0);
        assert(GVMModuleFrame(order,@"unknown",vertical,alerts,0).width==0);
    }
    for (NSUInteger vertical=0;vertical<2;vertical++) {
        GVMModuleRect fallback=GVMModuleFrame(@[@"invalid"],@"speed",vertical,0,0);
        GVMModuleRect standard=GVMModuleFrame(nil,@"speed",vertical,0,0);
        assert(fallback.x==standard.x && fallback.y==standard.y);
    }
}
static BOOL Apart(GVMModuleRect a,GVMModuleRect b,double gap) {
    return a.x+a.width+gap<=b.x+1e-9 || b.x+b.width+gap<=a.x+1e-9 || a.y+a.height+gap<=b.y+1e-9 || b.y+b.height+gap<=a.y+1e-9;
}
static void HaloFrameTests(void) {
    for (GVMHaloArrangement arrangement=GVMHaloRow;arrangement<=GVMHaloStack;arrangement++)
    for (NSUInteger trailing=0;trailing<2;trailing++) for (NSUInteger first=0;first<2;first++) for (NSUInteger alerts=0;alerts<3;alerts++) {
        GVMCardSize canvas=GVMHaloCanvasSize(arrangement,alerts);
        assert(canvas.stacked==(arrangement==GVMHaloStack) && canvas.compact==(arrangement==GVMHaloColumn));
        assert(GVMHaloArrangementFor(canvas)==arrangement);
        GVMModuleRect cells[3]={GVMHaloDialFrame(arrangement,first,trailing,alerts)};
        for (NSUInteger i=0;i<alerts;i++) cells[1+i]=GVMHaloAlertFrame(arrangement,first,trailing,alerts,i);
        assert(cells[0].width==GVMHaloDialBlock && cells[0].height==GVMHaloDialBlock);
        for (NSUInteger i=0;i<1+alerts;i++) {
            GVMModuleRect cell=cells[i];
            assert(cell.width>0 && cell.x>=GVMHaloPadding && cell.y>=GVMHaloPadding);
            assert(cell.x+cell.width<=canvas.width-GVMHaloPadding+1e-9 && cell.y+cell.height<=canvas.height-GVMHaloPadding+1e-9);
            for (NSUInteger j=0;j<i;j++) assert(Apart(cell,cells[j],GVMHaloGap)); // Gap, never overlap.
            if (!i) continue;
            // Alert signs share the dial's centre on the cross axis; a stacked row is centred under it.
            if (arrangement==GVMHaloColumn) assert(fabs(cell.x+cell.width/2-(cells[0].x+cells[0].width/2))<1e-9);
            if (arrangement==GVMHaloRow) assert(fabs(cell.y+GVMHaloAlertSignTop+GVMHaloAlertSign/2-(cells[0].y+7+GVMHaloDial/2))<1e-9);
        }
        if (arrangement==GVMHaloStack) {
            // The stack lines up with the anchored side, so the dial does not move when it forms.
            GVMModuleRect lone=GVMHaloDialFrame(GVMHaloRow,first,trailing,0);
            if (!trailing) assert(cells[0].x==lone.x && (first || cells[0].y==lone.y));
            double edge=trailing ? canvas.width-GVMHaloPadding : GVMHaloPadding;
            assert(fabs((trailing ? cells[0].x+cells[0].width : cells[0].x)-edge)<1e-9);
            if (alerts) assert(fabs((trailing ? cells[alerts].x+cells[alerts].width : cells[1].x)-edge)<1e-9);
        } else {
            GVMModuleRect leading=GVMHaloDialFrame(arrangement,first,NO,alerts);
            assert(cells[0].x==leading.x && cells[0].y==leading.y); // Only a stack depends on the side.
        }
        if (alerts) {
            BOOL across=arrangement==GVMHaloRow;
            double dial=across ? cells[0].x : cells[0].y, alert=across ? cells[1].x : cells[1].y;
            assert(first ? alert<dial : alert>dial);
        }
        if (alerts==2) {
            BOOL down=arrangement==GVMHaloColumn;
            assert((down ? cells[2].y-cells[1].y : cells[2].x-cells[1].x)==GVMHaloGap+(down ? GVMHaloAlertHeight : GVMHaloAlertWidth));
        }
        assert(GVMHaloAlertFrame(arrangement,first,trailing,alerts,alerts).width==0);
    }
    // Row and column are the chosen layouts and match the shared canvas size.
    for (NSUInteger alerts=0;alerts<3;alerts++) for (NSUInteger vertical=0;vertical<2;vertical++) {
        GVMCardSize shared=GVMCardCanvasSize(GVMInterfaceHalo,alerts,vertical);
        GVMCardSize own=GVMHaloCanvasSize(vertical ? GVMHaloColumn : GVMHaloRow,alerts);
        assert(shared.width==own.width && shared.height==own.height && !shared.stacked);
    }
    for (NSArray *order in Permutations()) assert(GVMAlertsFirst(order)==[order.firstObject isEqual:@"alerts"]);
    assert(!GVMAlertsFirst(nil) && !GVMAlertsFirst((NSArray *)@"alerts"));
}
// Size and fit rules shared by both bubbles; only the canvas and scale numbers differ.
static void StyleTests(GVMInterfaceStyle style) {
    BOOL halo=style==GVMInterfaceHalo;
    for (NSUInteger vertical=0;vertical<2;vertical++) {
        GVMCardSize capped=GVMCardCanvasSize(style,99,vertical),two=GVMCardCanvasSize(style,2,vertical);
        assert(capped.width==two.width && capped.height==two.height);
    }
    for (NSUInteger dashboard=0;dashboard<2;dashboard++) for (NSUInteger mode=0;mode<3;mode++) for (NSUInteger alerts=0;alerts<3;alerts++) {
        double width=dashboard ? 165 : 355;
        GVMCardSize size=GVMCarPlayCardSizeForLayout(style,width,226,400,240,alerts,dashboard,mode,100);
        assert(size.compact==(mode==2 || (mode==0 && dashboard)));
        assert(size.width>0 && size.height>0 && size.width<=width && size.height<=226);
        GVMCardSize scaled=GVMCarPlayCardSizeForLayout(style,width,226,400,240,alerts,dashboard,mode,GVMSizePercentMax);
        for (NSUInteger corner=0;corner<4;corner++) {
            GVMCardOrigin origin=GVMCardOriginFor(0,width,0,226,scaled,(GVMCardPlacement)corner);
            assert(origin.x>=0 && origin.y>=0 && origin.x+scaled.width<=width+.001 && origin.y+scaled.height<=226+.001);
        }
    }
    // Dashboard: up to 100% the modules keep one scale whatever the arrangement or alert count,
    // even on narrow tiles. Larger sizes are kept while the shown content fits the tile and
    // shrink only as far as the current alerts need.
    const double tiles[][4]={{165,226,400,240},{105,120,240,160},{278,200,640,240},{120,90,400,240},{330,440,800,480}};
    for (NSUInteger t=0;t<sizeof(tiles)/sizeof(tiles[0]);t++) for (NSUInteger alerts=0;alerts<3;alerts++) {
        double width=tiles[t][0],height=tiles[t][1];
        GVMCardSize hc=GVMCardCanvasSize(style,alerts,NO),vc=GVMCardCanvasSize(style,alerts,YES);
        double standard=GVMCarPlayCardSizeForLayout(style,width,height,tiles[t][2],tiles[t][3],2,YES,1,100).width/GVMCardCanvasSize(style,2,NO).width;
        double previous=0;
        for (NSUInteger percent=GVMSizePercentMin;percent<=GVMSizePercentMax;percent+=25) {
            GVMCardSize h=GVMCarPlayCardSizeForLayout(style,width,height,tiles[t][2],tiles[t][3],alerts,YES,1,percent);
            GVMCardSize v=GVMCarPlayCardSizeForLayout(style,width,height,tiles[t][2],tiles[t][3],alerts,YES,2,percent);
            GVMCardSize emptyCanvas=GVMCardCanvasSize(style,0,NO);
            GVMCardSize empty=GVMCarPlayCardSizeForLayout(style,width,height,tiles[t][2],tiles[t][3],0,YES,1,percent);
            double requested=standard*percent/100;
            // New UI stacks the alerts under the dial only when the chosen layout does not fit
            // and stacking keeps the bubble larger; otherwise both styles shrink just enough.
            GVMCardSize sizes[2]={h,v},chosen[2]={hc,vc};
            for (NSUInteger k=0;k<2;k++) {
                GVMCardSize size=sizes[k],own=size.stacked ? GVMHaloCanvasSize(GVMHaloStack,alerts) : chosen[k];
                double fit=MIN(width/chosen[k].width,height/chosen[k].height);
                double scale=size.width/own.width;
                assert(fabs(scale-size.height/own.height)<0.00001);
                if (size.stacked) {
                    double stackFit=MIN(width/own.width,height/own.height);
                    assert(halo && alerts && requested>fit && stackFit>fit);
                    assert(fabs(scale-MIN(requested,stackFit))<0.00001);
                } else {
                    assert(fabs(scale-MIN(requested,fit))<0.00001);
                }
            }
            if (percent<=100) {
                assert(!h.stacked && !v.stacked);
                assert(fabs(h.width/hc.width-empty.width/emptyCanvas.width)<0.00001);
                assert(fabs(h.width/hc.width-v.width/vc.width)<0.00001);
            }
            double drawn=h.width/(h.stacked ? GVMHaloCanvasSize(GVMHaloStack,alerts) : hc).width;
            assert(drawn>=previous-0.00001); // A larger size is never drawn smaller.
            previous=drawn;
            assert(h.width<=width+.00001 && h.height<=height+.00001);
            assert(v.width<=width+.00001 && v.height<=height+.00001);
            GVMCardSize automatic=GVMCarPlayCardSizeForLayout(style,width,height,tiles[t][2],tiles[t][3],alerts,YES,0,percent);
            assert(automatic.compact && automatic.width==v.width && automatic.height==v.height);
            for (NSUInteger corner=0;corner<2;corner++) for (NSUInteger direction=0;direction<2;direction++) {
                GVMCardSize size=direction ? v : h;
                GVMCardOrigin origin=GVMCardOriginFor(0,width,0,height,size,corner);
                assert(origin.x>=0 && origin.y>=0 && origin.x+size.width<=width+.00001 && origin.y+size.height<=height+.00001);
            }
        }
    }
    // On a 400 x 240 Dashboard tile the 200% New UI row cannot hold two alerts beside the dial, so
    // they move under it and the dial stays larger than the row would allow.
    GVMCardSize stackedRow=GVMCarPlayCardSizeForLayout(style,150.6,211.6,400,240,2,YES,1,200);
    GVMCardSize plainRow=GVMCarPlayCardSizeForLayout(style,150.6,211.6,400,240,2,YES,1,100);
    assert(stackedRow.stacked==halo && !plainRow.stacked);
    if (halo) assert(stackedRow.width/GVMHaloCanvasSize(GVMHaloStack,2).width>plainRow.width/GVMCardCanvasSize(style,2,NO).width);
    // No viewport-fraction shrink as alerts arrive while the full group still fits.
    for (NSUInteger alerts=0;alerts<3;alerts++) for (NSUInteger mode=1;mode<=2;mode++) {
        GVMCardSize canvas=GVMCardCanvasSize(style,alerts,mode==2);
        GVMCardSize size=GVMCarPlayCardSizeForLayout(style,400,400,400,240,alerts,YES,mode,100);
        GVMCardSize larger=GVMCarPlayCardSizeForLayout(style,400,400,400,240,alerts,YES,mode,150);
        // Dashboard scale at display scale 1: Halo M dial, or the 0.2.3 30-point column.
        assert(fabs(size.width/canvas.width-(halo ? 64.0/GVMHaloDial/1.4 : 30.0/96))<0.00001);
        assert(fabs(larger.width/size.width-1.5)<0.00001);
    }
    assert(!GVMCarPlayCardSizeForLayout(style,0,226,400,240,0,YES,1,100).width);
    assert(!GVMCarPlayCardSizeForLayout(style,NAN,226,400,240,0,YES,2,100).width);
    GVMCardSize defaultPercent=GVMCarPlayCardSizeForLayout(style,180,226,400,240,2,YES,1,NAN);
    assert(defaultPercent.width==GVMCarPlayCardSizeForLayout(style,180,226,400,240,2,YES,1,100).width);
    const double screens[][2] = {{320,180}, {400,240}, {640,240}, {800,480}, {240,160}};
    for (NSUInteger i = 0; i < sizeof(screens) / sizeof(screens[0]); i++) {
        double screenWidth = screens[i][0], screenHeight = screens[i][1];
        for (int dashboard = 0; dashboard < 2; dashboard++) {
            for (int camera = 0; camera < 3; camera++) {
                double availableWidth = screenWidth * (dashboard ? 0.46 : 0.90) - 16;
                double availableHeight = screenHeight - 40;
                GVMCardSize size = GVMCardSizeFor(style, availableWidth, availableHeight,
                    screenWidth, screenHeight, camera);
                assert(size.compact == dashboard);
                assert(size.width > 0 && size.height > 0);
                assert(size.width < availableWidth && size.height < availableHeight);
                GVMCardSize canvas = GVMCardCanvasSize(style, camera, dashboard);
                assert(fabs(size.width / size.height - canvas.width / canvas.height) < 0.00001);
            }
        }
    }
    // A full-map guidance panel reduces available space, not the presentation mode.
    for (NSUInteger alerts=0;alerts<3;alerts++) {
        GVMCardSize guided=GVMCarPlayCardSizeForView(style,190,189,355,400,240,alerts);
        assert(!guided.compact);
        GVMCardSize canvas=GVMCardCanvasSize(style,alerts,NO);
        assert(fabs(guided.width/guided.height-canvas.width/canvas.height)<0.00001);
        GVMCardSize dash=GVMCarPlayCardSizeForView(style,130,189,165.5,400,240,alerts);
        // The bare Halo dial block is square; the Classic column always runs vertically.
        assert(dash.compact && (alerts || !halo ? dash.height>dash.width : fabs(dash.height-dash.width)<0.00001));
    }
    GVMCardSize wide = GVMCardSizeFor(style,560,200,640,240,YES);
    // Navigation exclusions can exceed the remaining space at a corner.
    // Keep the viewport-sized card intact and move it inside the viewport.
    for (NSUInteger alerts=0;alerts<3;alerts++) {
        for (NSUInteger dashboard=0;dashboard<2;dashboard++) {
            double width=dashboard ? 165.5 : 355;
            GVMCardSize base=GVMCarPlayCardSizeForView(style,width-14,226,width,400,240,alerts);
            for (NSUInteger percent=50;percent<=150;percent+=50) {
                GVMCardSize scaled=GVMScaleCardSize(base,percent,width-14,226);
                assert(fabs(scaled.width-base.width*percent/100.0)<0.00001);
                assert(fabs(scaled.height-base.height*percent/100.0)<0.00001);
                for (NSUInteger corner=0;corner<4;corner++) {
                    GVMCardOrigin requested=GVMCardOriginFor(width-20,width-80,220,180,scaled,corner);
                    GVMCardOrigin clamped=GVMClampCardOrigin(requested,scaled,7,width-7,7,233);
                    assert(clamped.x>=7 && clamped.y>=7);
                    assert(clamped.x+scaled.width<=width-7+0.00001);
                    assert(clamped.y+scaled.height<=233+0.00001);
                    GVMCardOrigin unchanged=GVMClampCardOrigin(clamped,scaled,7,width-7,7,233);
                    assert(unchanged.x==clamped.x && unchanged.y==clamped.y);
                }
            }
        }
    }
    GVMCardSize shortMap = GVMCardSizeFor(style,560,80,640,240,YES);
    assert(shortMap.height < wide.height && shortMap.height <= 80 * (halo ? 0.26 : 0.24));
    assert(!GVMCardSizeFor(style,0,100,400,240,NO).width);
    assert(!GVMCardSizeFor(style,NAN,100,400,240,NO).width);
    assert(!GVMCardSizeFor(style,100,100,0,240,NO).width);
    GVMCardSize portrait=GVMPhoneCardSizeFor(style,390,844,2);
    GVMCardSize landscape=GVMPhoneCardSizeFor(style,844,390,2);
    assert(portrait.compact && portrait.height>portrait.width);
    assert(!landscape.compact && landscape.width>landscape.height);
    assert(GVMPhoneCardSizeFor(style,0,100,0).width==0);
    assert(!GVMPhoneCardSizeForLayout(style,390,844,2,1).compact);
    assert(GVMPhoneCardSizeForLayout(style,844,390,2,2).compact);
    GVMCardSize forced=GVMPhoneCardSizeForLayout(style,320,568,2,1);
    assert(forced.width<=320 && forced.height<=568);
}
static BOOL Close(double a,double b) { return fabs(a-b)<0.01; }
static GVMModuleRect Scaled(GVMModuleRect r,double x,double y,double scale) {
    return (GVMModuleRect){x+r.x*scale,y+r.y*scale,r.width*scale,r.height*scale};
}
static void GuidanceStateTests(void) {
    GVMGuidanceColumn column={53,142,94,188}, read;
    uint64_t state=GVMEncodeGuidance(column,1000.4);
    assert(GVMDecodeGuidance(state,1001,&read) && read.x==53 && read.width==142 && read.cardBottom==94 && read.etaTop==188);
    assert(GVMDecodeGuidance(GVMEncodeGuidance((GVMGuidanceColumn){53.5,142,94.5,188},10),10,&read) && read.x==53.5 && read.cardBottom==94.5);
    assert(GVMDecodeGuidance(state,1003,NULL) && !GVMDecodeGuidance(state,1004,NULL));   // a column left behind is ignored
    assert(GVMDecodeGuidance(GVMEncodeGuidance(column,32767),32768+1,NULL));             // uptime seconds wrap
    assert(!GVMDecodeGuidance(0,1000,NULL) && !GVMDecodeGuidance(state&~(1ULL<<63),1000,NULL));
    assert(!GVMEncodeGuidance((GVMGuidanceColumn){53,0,94,188},10) && !GVMEncodeGuidance((GVMGuidanceColumn){53,142,190,188},10) &&
        !GVMEncodeGuidance((GVMGuidanceColumn){-1,142,94,188},10) && !GVMEncodeGuidance((GVMGuidanceColumn){53,142,94,4000},10));
}
static void DockTests(void) {
    // CarPlay 400 x 240 in navigation (measured 16/10): column x 53, width 142, card ends at 94 and the
    // estimates start at 188; the slot keeps 6 points from each. Bubble at 48%.
    GVMModuleRect slot={53,100,142,82};
    double k=0.479;
    GVMEffectDock one=GVMEffectDockFor(slot,1,5,NO,k);
    assert(one.signs==1 && one.lanes && Close(one.diameter,58*k) && Close(one.stripScale,14.0/26));
    assert(one.signFrames[0].x==53 && Close(one.strip.x,53+58*k+6) && Close(one.strip.y+one.strip.height/2,141) && Close(one.signFrames[0].y+one.diameter/2,141));
    GVMEffectDock two=GVMEffectDockFor(slot,2,5,NO,k);
    assert(two.signs==2 && two.lanes && two.diameter>=20 && two.diameter<58*k && Close(two.strip.x+two.strip.width,53+142));
    GVMEffectDock wide=GVMEffectDockFor(slot,1,8,NO,k);
    assert(wide.signs==0 && wide.lanes && wide.strip.width<=142+1e-9);  // eight lanes take the row; the sign stays in the bubble
    GVMEffectDock signsOnly=GVMEffectDockFor(slot,2,0,NO,k);
    assert(signsOnly.signs==2 && !signsOnly.lanes && Close(signsOnly.diameter,58*k));
    assert(GVMEffectDockFor((GVMModuleRect){53,100,142,15},1,5,NO,k).signs==0 && !GVMEffectDockFor((GVMModuleRect){53,100,142,15},1,5,NO,k).lanes);
    assert(!GVMEffectDockFor(slot,0,0,NO,k).lanes && GVMEffectDockFor(slot,0,0,NO,k).signs==0);
    // Large screens keep the bubble's own sizes.
    GVMEffectDock big=GVMEffectDockFor((GVMModuleRect){106,200,284,170},1,5,NO,1);
    assert(big.signs==1 && Close(big.diameter,58) && Close(big.stripScale,1));
}
static void LaneLayoutTests(void) {
    GVMLaneStripMetrics five=GVMLaneStripMetricsFor(5,NO), eight=GVMLaneStripMetricsFor(8,NO), twelve=GVMLaneStripMetricsFor(12,NO);
    assert(five.cell==30 && five.arrow==26 && five.plate==46 && five.width==160 && five.height==46);
    assert(eight.cell==26 && eight.width==218 && twelve.cell==22 && twelve.arrow==18);
    // Lanes announced ahead carry a distance tag across the plate's bottom edge.
    GVMLaneStripMetrics tagged=GVMLaneStripMetricsFor(5,YES), single=GVMLaneStripMetricsFor(1,YES);
    assert(tagged.height==56 && tagged.width==160 && GVMLanePlateWidth(tagged,5)==160);
    assert(single.width==58 && GVMLanePlateWidth(single,1)==40 && single.height==56);
    GVMLaneStripLayout taggedBelow=GVMLaneStripLayoutFor((GVMModuleRect){90,10,GVMHaloCanvasSize(GVMHaloRow,2).width,GVMHaloCanvasSize(GVMHaloRow,2).height},
        1,GVMHaloRow,Scaled(GVMHaloDialFrame(GVMHaloRow,NO,NO,2),90,10,1),NO,NO,5,YES,(GVMModuleRect){90,10,700,460},0.5,0.5);
    assert(taggedBelow.place==GVMLaneStripBelow && taggedBelow.frame.height==56);
    GVMEffectDock taggedDock=GVMEffectDockFor((GVMModuleRect){53,100,142,40},0,5,YES,0.556);
    assert(taggedDock.lanes && Close(taggedDock.strip.height,56*taggedDock.stripScale) && taggedDock.strip.height<=40+1e-9);
    // Full map 800 x 480, row with two alerts at size L, top-left: the strip hangs under the group,
    // lined up with the dial block, at the bubble's own scale.
    GVMModuleRect area={90,10,700,460};
    GVMCardSize row=GVMHaloCanvasSize(GVMHaloRow,2);
    GVMModuleRect card={90,10,row.width,row.height};
    GVMModuleRect dial=Scaled(GVMHaloDialFrame(GVMHaloRow,NO,NO,2),90,10,1);
    GVMLaneStripLayout below=GVMLaneStripLayoutFor(card,1,GVMHaloRow,dial,NO,NO,5,NO,area,0.5,0.5);
    assert(below.place==GVMLaneStripBelow && below.scale==1 && below.frame.x==dial.x &&
        below.frame.y==card.y+card.height && below.frame.width==160 && below.frame.height==46);
    // Bottom corners put it over the group instead, so nothing moves off screen and the dial stays.
    GVMModuleRect low={90,470-row.height,row.width,row.height};
    GVMLaneStripLayout above=GVMLaneStripLayoutFor(low,1,GVMHaloRow,Scaled(GVMHaloDialFrame(GVMHaloRow,NO,NO,2),90,low.y,1),NO,YES,5,NO,area,0.5,0.5);
    assert(above.place==GVMLaneStripAbove && Close(above.frame.y+above.frame.height,low.y));
    // Alerts first on the right: the dial is the right-hand block and the strip lines up with its right edge.
    GVMModuleRect rightCard={790-row.width,10,row.width,row.height};
    GVMModuleRect rightDial=Scaled(GVMHaloDialFrame(GVMHaloRow,YES,YES,2),rightCard.x,10,1);
    GVMLaneStripLayout rightRow=GVMLaneStripLayoutFor(rightCard,1,GVMHaloRow,rightDial,YES,NO,5,NO,area,0.5,0.5);
    assert(rightRow.place==GVMLaneStripBelow && Close(rightRow.frame.x+rightRow.frame.width,rightDial.x+rightDial.width));
    // Dial alone at the right edge: the strip is wider than the bubble and stays on screen.
    GVMCardSize lone=GVMHaloCanvasSize(GVMHaloRow,0);
    GVMModuleRect loneCard={790-lone.width,10,lone.width,lone.height};
    GVMLaneStripLayout clamped=GVMLaneStripLayoutFor(loneCard,1,GVMHaloRow,Scaled(GVMHaloDialFrame(GVMHaloRow,NO,YES,0),loneCard.x,10,1),YES,NO,5,NO,area,0.5,0.5);
    assert(clamped.place==GVMLaneStripBelow && Close(clamped.frame.x+clamped.frame.width,790));
    // A column puts the strip beside the dial, on the inner side, centred on the dial.
    double k=0.867;
    GVMCardSize column=GVMHaloCanvasSize(GVMHaloColumn,2);
    GVMModuleRect colCard={90,10,column.width*k,column.height*k};
    GVMModuleRect colDial=Scaled(GVMHaloDialFrame(GVMHaloColumn,NO,NO,2),90,10,k);
    GVMLaneStripLayout beside=GVMLaneStripLayoutFor(colCard,k,GVMHaloColumn,colDial,NO,NO,5,NO,area,0.5,0.5);
    double circleRight=colDial.x+(GVMHaloDialBlock+GVMHaloDial)/2*k, middle=colDial.y+(7+GVMHaloDial/2)*k;
    double badgeBottom=colDial.y+(7+GVMHaloBadgeDrop+GVMHaloBadge/2)*k;
    assert(beside.place==GVMLaneStripBeside && Close(beside.scale,k) && Close(beside.frame.x,circleRight+GVMHaloGap*k) &&
        beside.frame.y>=badgeBottom && beside.frame.y+beside.frame.height/2>middle);   // under the limit badge
    assert(beside.frame.y+beside.frame.height<=colCard.y+(GVMHaloPadding+GVMHaloDialBlock)*k);
    GVMModuleRect colRight={790-colCard.width,10,colCard.width,colCard.height};
    GVMModuleRect colRightDial=Scaled(GVMHaloDialFrame(GVMHaloColumn,NO,YES,2),colRight.x,10,k);
    GVMLaneStripLayout besideLeft=GVMLaneStripLayoutFor(colRight,k,GVMHaloColumn,colRightDial,YES,NO,5,NO,area,0.5,0.5);
    assert(besideLeft.place==GVMLaneStripBeside && Close(besideLeft.frame.x+besideLeft.frame.width,colRightDial.x+(GVMHaloDialBlock-GVMHaloDial)/2*k-GVMHaloGap*k));
    // Small bubbles: the strip keeps 14-point arrows even when the bubble is smaller.
    GVMModuleRect small={0,0,305,227};
    double tiny=0.425;
    GVMModuleRect tinyCard={6,6,column.width*tiny,column.height*tiny};
    GVMLaneStripLayout floorStrip=GVMLaneStripLayoutFor(tinyCard,tiny,GVMHaloColumn,Scaled(GVMHaloDialFrame(GVMHaloColumn,NO,NO,2),6,6,tiny),NO,NO,5,NO,small,0.5,0.5);
    assert(floorStrip.place==GVMLaneStripBeside && Close(floorStrip.scale*26,14) && floorStrip.frame.x+floorStrip.frame.width<=152.5+0.01);
    // A column too narrow for the strip beside the dial puts it under the column.
    GVMModuleRect narrow={0,0,120,300};
    GVMModuleRect narrowCard={0,0,column.width*0.6,column.height*0.6};
    GVMLaneStripLayout under=GVMLaneStripLayoutFor(narrowCard,0.6,GVMHaloColumn,Scaled(GVMHaloDialFrame(GVMHaloColumn,NO,NO,2),0,0,0.6),NO,NO,5,NO,narrow,1,1);
    assert(under.place==GVMLaneStripBelow && Close(under.frame.y,narrowCard.height) && under.frame.width<=120+0.01 && under.scale>=14.0/26-1e-9);
    // Not enough room even at the minimum: hidden, never cut.
    GVMLaneStripLayout hidden=GVMLaneStripLayoutFor(narrowCard,0.6,GVMHaloColumn,Scaled(GVMHaloDialFrame(GVMHaloColumn,NO,NO,2),0,0,0.6),NO,NO,5,NO,(GVMModuleRect){0,0,70,170},1,1);
    assert(hidden.place==GVMLaneStripHidden);
    assert(GVMLaneStripLayoutFor(card,1,GVMHaloRow,dial,NO,NO,0,NO,area,0.5,0.5).place==GVMLaneStripHidden);
    assert(GVMLaneStripLayoutFor(card,1,GVMHaloRow,dial,NO,NO,13,NO,area,0.5,0.5).place==GVMLaneStripHidden);
    // Wider roads use narrower cells; their smaller arrows still keep 14 points.
    GVMLaneStripLayout wide=GVMLaneStripLayoutFor(card,0.5,GVMHaloRow,dial,NO,NO,8,NO,area,0.5,0.5);
    assert(wide.place==GVMLaneStripBelow && Close(wide.scale*22,14) && Close(wide.frame.width,218*wide.scale));
    // The strip shrinks to fit the reach before it gives up: a shallow area under a full-size row.
    GVMLaneStripLayout squeezed=GVMLaneStripLayoutFor(card,1,GVMHaloRow,dial,NO,NO,5,NO,(GVMModuleRect){90,10,700,300},0.5,0.5);
    assert(squeezed.place==GVMLaneStripBelow && squeezed.scale<1 && Close(squeezed.frame.y+squeezed.frame.height,10+150));
}
int main(void) {
    LaneLayoutTests();
    DockTests();
    GuidanceStateTests();
    @autoreleasepool {
    NSDictionary *overspeed=@{@"speed":@{@"value":@61,@"receivedAt":@100},@"speedLimit":@{@"value":@60,@"receivedAt":@100}};
    uint64_t lease=GVMEncodeOverspeedLease(overspeed,100);
    assert((lease&3)==1);
    for (NSNumber *excess in @[@4,@5,@9,@10,@30]) {
        NSDictionary *sample=@{@"speed":@{@"value":@(60+excess.integerValue),@"receivedAt":@100},@"speedLimit":overspeed[@"speedLimit"]};
        assert((GVMEncodeOverspeedLease(sample,100)&3)==(excess.integerValue<5 ? 1 : excess.integerValue<10 ? 2 : 3));
    }
    assert(GVMOverspeedLeaseActive(lease,100.9)); assert(!GVMOverspeedLeaseActive(lease,101));
    assert(!GVMOverspeedLeaseActive(lease,99));
    assert(!GVMEncodeOverspeedLease(overspeed,105));
    assert(!GVMEncodeOverspeedLease(@{@"speed":@{@"value":@60,@"receivedAt":@100},@"speedLimit":overspeed[@"speedLimit"]},100));
    assert(!GVMEncodeOverspeedLease(@{@"speed":overspeed[@"speed"],@"speedLimit":@{@"value":@0,@"receivedAt":@100}},100));
    assert(!GVMEncodeOverspeedLease(@{},100));
    assert(!GVMEncodeOverspeedLease(@{@"speed":@{@"value":@YES,@"receivedAt":@100},@"speedLimit":overspeed[@"speedLimit"]},100));
    assert(!GVMEncodeOverspeedLease(overspeed,99));
    assert(!GVMEncodeOverspeedLease(overspeed,NAN));
    uint64_t almostExpired=GVMEncodeOverspeedLease(overspeed,104.8);
    assert(GVMOverspeedLeaseActive(almostExpired,104.9) && !GVMOverspeedLeaseActive(almostExpired,105));
        for (NSUInteger mask=0;mask<16;mask++) {
            BOOL master=(mask&1)!=0;
            uint64_t state=GVMEncodeBubbleVisibility(@(master),@((mask&2)!=0),@((mask&4)!=0),@((mask&8)!=0));
            for (NSUInteger surface=0;surface<3;surface++)
                assert(GVMDecodeBubbleVisibility(state,surface)==(master && (mask&(1UL<<(surface+1)))));
            // Turning the master back on preserves the individual screen choices.
            uint64_t resumed=GVMEncodeBubbleVisibility(@YES,@((mask&2)!=0),@((mask&4)!=0),@((mask&8)!=0));
            for (NSUInteger surface=0;surface<3;surface++)
                assert(GVMDecodeBubbleVisibility(resumed,surface)==((mask&(1UL<<(surface+1)))!=0));
        }
        for (NSUInteger surface=0;surface<3;surface++) {
            assert(GVMDecodeBubbleVisibility(0,surface));
            assert(GVMDecodeBubbleVisibility(UINT64_MAX,surface));
            assert(GVMDecodeBubbleVisibility(GVMEncodeBubbleVisibility(nil,nil,nil,nil),surface));
            assert(GVMDecodeBubbleVisibility(GVMEncodeBubbleVisibility(@"invalid",NSNull.null,@[],@{}),surface));
            assert(GVMDecodeBubbleVisibility((1ULL<<8)|0x10,surface));
        }
        assert(!GVMDecodeBubbleVisibility(GVMEncodeBubbleVisibility(nil,nil,nil,nil),3));
        NSArray *permutations=Permutations();
        ClassicFrameTests();
        HaloFrameTests();
        StyleTests(GVMInterfaceClassic);
        StyleTests(GVMInterfaceHalo);
        // Classic until New UI (beta) is chosen; unpublished or foreign states stay Classic.
        assert(GVMDecodeInterfaceStyle(GVMEncodeInterfaceStyle(@"halo"))==GVMInterfaceHalo);
        for (id value in @[@"classic",@"Halo",@1,NSNull.null,@[]]) assert(GVMDecodeInterfaceStyle(GVMEncodeInterfaceStyle(value))==GVMInterfaceClassic);
        assert(GVMDecodeInterfaceStyle(GVMEncodeInterfaceStyle(nil))==GVMInterfaceClassic);
        assert(GVMDecodeInterfaceStyle(0)==GVMInterfaceClassic && GVMDecodeInterfaceStyle(GVMInterfaceHalo)==GVMInterfaceClassic);
        assert(GVMDecodeInterfaceStyle(UINT64_MAX)==GVMInterfaceClassic);
        for (NSArray *order in permutations) for (NSString *mode in @[@"auto",@"horizontal",@"vertical"]) {
            uint64_t state=GVMEncodeBubbleConfiguration(@[mode,mode,mode],@[order,order,order]);
            for (NSUInteger surface=0;surface<3;surface++) {
                assert([GVMDecodeModuleOrder(state,surface,YES) isEqual:order]);
                assert(GVMDecodeBubbleLayout(state,surface)==([mode isEqual:@"horizontal"] ? 1 : [mode isEqual:@"vertical"] ? 2 : 0));
            }
        }
        uint64_t invalid=GVMEncodeBubbleConfiguration(@[],@[@[@"speed",@"speed",@"alerts"]]);
        assert([GVMDecodeModuleOrder(invalid,0,NO) isEqual:permutations[0]]);
        assert([GVMDecodeModuleOrder(0,1,YES) isEqual:permutations[2]]);
        assert(GVMDecodeBubbleLayout(UINT64_MAX,0)==0);
        assert(GVMWarningFor(@44,@50)==GVMWarningNormal);
        assert(GVMWarningFor(@45,@50)==GVMWarningNear);
        assert(GVMWarningFor(@50,@50)==GVMWarningNear);
        assert(GVMWarningFor(@51,@50)==GVMWarningOver);
        assert(GVMWarningFor(@25,@30)==GVMWarningNear);
        assert(GVMWarningFor(@0,@50)==GVMWarningNormal);
        assert(GVMWarningFor(nil,@50)==GVMWarningNormal);
        assert(GVMWarningFor(@60,nil)==GVMWarningNormal);
        assert(GVMWarningFor(@60,@0)==GVMWarningNormal);
        assert(GVMProgressFor(@0,@50)==0);
        assert(GVMProgressFor(@25,@50)==0.5);
        assert(GVMProgressFor(@60,@50)==1);
        assert(GVMProgressFor(nil,@50)==0);
        assert(GVMProgressFor(@60,nil)==0);
        GVMCardSize card = {40,60,NO,NO};
        GVMCardOrigin tl = GVMCardOriginFor(10,210,20,180,card,GVMCardTopLeft);
        GVMCardOrigin tr = GVMCardOriginFor(10,210,20,180,card,GVMCardTopRight);
        GVMCardOrigin bl = GVMCardOriginFor(10,210,20,180,card,GVMCardBottomLeft);
        GVMCardOrigin br = GVMCardOriginFor(10,210,20,180,card,GVMCardBottomRight);
        assert(tl.x==10 && tl.y==20 && tr.x==170 && tr.y==20);
        assert(bl.x==10 && bl.y==120 && br.x==170 && br.y==120);
        for (NSUInteger corner=0;corner<4;corner++) {
            NSArray *positions=@[@"top-left",@"top-right",@"bottom-left",@"bottom-right"];
            for (NSUInteger side=0;side<2;side++) {
                NSUInteger decoded=99; BOOL isLeft=NO;
                uint64_t state=GVMEncodePlacement(positions[corner],side ? @"left" : @"right");
                assert(GVMDecodePlacement(state,&decoded,&isLeft));
                assert(decoded==corner && isLeft==side);
            }
        }
        assert(!GVMDecodePlacement(0,NULL,NULL));
        assert(!GVMDecodePlacement(9,NULL,NULL));
    for (NSUInteger c=0;c<4;c++) {
        NSUInteger corner=9; NSInteger x=0,y=0;
        NSArray *corners=@[@"top-left",@"top-right",@"bottom-left",@"bottom-right"];
        GVMDecodePhonePlacement(GVMEncodePhonePlacement(corners[c],@(-23),@87,@"auto"),&corner,&x,&y,NULL);
        assert(corner==c && x==-23 && y==87);
    }
    NSUInteger fallbackCorner=9; NSInteger fallbackX=99,fallbackY=99;
    GVMDecodePhonePlacement(0,&fallbackCorner,&fallbackX,&fallbackY,NULL);
    assert(fallbackCorner==1 && fallbackX==0 && fallbackY==0);
    assert(GVMOffsetPercent(@999)==100 && GVMOffsetPercent(@(-999))==-100 && GVMOffsetPercent(@(NAN))==0);
    assert(GVMOffsetPercentFromPoints(@100,400)==25);
    assert(GVMOffsetPercentFromPoints(@(-200),800)==-25);
    assert(GVMOffsetPercentFromPoints(@100,0)==0);
    assert(GVMOffsetPercent(@YES)==0);
    assert(GVMDecodeLimitDial(GVMEncodePresentationOptions(@"limit")));
    assert(!GVMDecodeLimitDial(GVMEncodePresentationOptions(@"speed")) && !GVMDecodeLimitDial(GVMEncodePresentationOptions(nil)));
    assert(!GVMDecodeLimitDial(GVMEncodePresentationOptions(@5)));
    assert(!GVMDecodeLimitDial(0) && !GVMDecodeLimitDial(3));
    assert(GVMSliderPercent(@(-18),YES)==-18 && GVMSliderPercent(@(-27),YES)==-27 && GVMSliderPercent(@140,NO)==140);
    for (NSUInteger mode=0;mode<3;mode++) {
        NSUInteger decoded=99;
        GVMDecodePhonePlacement(GVMEncodePhonePlacement(@"bottom-right",@100,@(-100),@[@"auto",@"horizontal",@"vertical"][mode]),NULL,&fallbackX,&fallbackY,&decoded);
        assert(decoded==mode && fallbackX==100 && fallbackY==-100);
    }
    // Legacy point packets must not be interpreted as percentages.
    GVMDecodePhonePlacement(1ULL<<32,NULL,&fallbackX,&fallbackY,NULL);
    assert(fallbackX==0 && fallbackY==0);
    GVMCardSize phoneCard={80,120,YES,NO};
    GVMCardOrigin home=GVMPhoneCardOriginFor(10,380,50,800,phoneCard,GVMCardTopRight,0,0);
    assert(home.x==300 && home.y==50);
    GVMCardOrigin movedUp=GVMPhoneCardOriginFor(10,380,50,800,phoneCard,GVMCardTopRight,0,-50);
    assert(movedUp.y==50); // Only the supplied screen edge limits movement.
    for (NSUInteger corner=0;corner<4;corner++) {
        GVMCardOrigin minEdge=GVMPhoneCardOriginFor(10,380,50,800,phoneCard,corner,-1000,-1000);
        GVMCardOrigin maxEdge=GVMPhoneCardOriginFor(10,380,50,800,phoneCard,corner,1000,1000);
        assert(minEdge.x==10 && minEdge.y==50);
        assert(maxEdge.x==300 && maxEdge.y==680);
    }
    GVMCardOrigin shortScreen=GVMPhoneCardOriginFor(44,800,10,150,phoneCard,GVMCardTopLeft,0,0);
    assert(shortScreen.x==44 && shortScreen.y==10);
    GVMCardOrigin fullScreen=GVMPhoneCardOriginFor(0,390,0,844,phoneCard,GVMCardTopLeft,0,0);
    assert(fullScreen.x==0 && fullScreen.y==0);
    GVMCardOrigin farEdge=GVMPhoneCardOriginFor(0,390,0,844,phoneCard,GVMCardTopLeft,390,844);
    assert(farEdge.x==310 && farEdge.y==724);
    uint64_t sizes=GVMEncodeSizes(@50,@125,@150);
    assert(GVMDecodeSize(sizes,0)==50 && GVMDecodeSize(sizes,1)==125 && GVMDecodeSize(sizes,2)==150);
    assert(GVMDecodeSize(0,0)==100 && GVMDecodeSize(sizes,3)==100);
    assert(GVMSizePercent(@(NAN))==100 && GVMSizePercent(@YES)==100 && GVMSizePercent(@999)==GVMSizePercentMax && GVMSizePercent(@1)==GVMSizePercentMin);
    uint64_t largest=GVMEncodeSizes(@250,@250,@250);
    assert(GVMDecodeSize(largest,0)==250 && GVMDecodeSize(largest,1)==250 && GVMDecodeSize(largest,2)==250);
    GVMCardSize enlarged=GVMScaleCardSize((GVMCardSize){100,50,NO,NO},250,1000,1000);
    assert(enlarged.width==250 && enlarged.height==125);
    GVMCardSize doubled=GVMScaleCardSize((GVMCardSize){100,50,NO,NO},150,120,100);
    assert(doubled.width==120 && doubled.height==60);
    GVMCardSize reduced=GVMScaleCardSize((GVMCardSize){100,50,YES,NO},50,300,200);
    assert(reduced.width==50 && reduced.height==25 && reduced.compact);
    puts("speed-presentation tests passed");
    }
}
