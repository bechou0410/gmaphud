#import <Foundation/Foundation.h>
// Classic is the 0.2.3 bubble; Halo is New UI (beta). Each draws on its own canvas.
typedef NS_ENUM(NSUInteger, GVMInterfaceStyle) { GVMInterfaceClassic, GVMInterfaceHalo };
typedef NS_ENUM(NSInteger, GVMWarning) { GVMWarningNormal, GVMWarningNear, GVMWarningOver };
GVMWarning GVMWarningFor(NSNumber *speed, NSNumber *limit);
double GVMProgressFor(NSNumber *speed, NSNumber *limit);

// All dimensions use UIKit points; scale stays uniform across the artwork.
typedef struct {
    double width;
    double height;
    BOOL compact;
    BOOL stacked; // New UI only: alerts moved under the dial because the chosen layout did not fit.
} GVMCardSize;
GVMCardSize GVMCardSizeFor(GVMInterfaceStyle style, double availableWidth, double availableHeight,
    double screenWidth, double screenHeight, NSUInteger cameraCount);
typedef NS_ENUM(NSInteger, GVMCardPlacement) {
    GVMCardTopLeft, GVMCardTopRight, GVMCardBottomLeft, GVMCardBottomRight
};
typedef struct { double x; double y; } GVMCardOrigin;
GVMCardOrigin GVMClampCardOrigin(GVMCardOrigin origin,GVMCardSize size,
    double left,double right,double top,double bottom);
GVMCardOrigin GVMCardOriginFor(double left, double right, double top, double bottom,
    GVMCardSize size, GVMCardPlacement placement);

GVMCardSize GVMScaleCardSize(GVMCardSize size, double percent, double width, double height);

GVMCardSize GVMPhoneCardSizeFor(GVMInterfaceStyle style, double width, double height, NSUInteger alerts);

GVMCardSize GVMPhoneCardSizeForLayout(GVMInterfaceStyle style,double width,double height,NSUInteger alerts,NSUInteger layout);

GVMCardOrigin GVMPhoneCardOriginFor(double left,double right,double top,double bottom,
    GVMCardSize size,GVMCardPlacement placement,double offsetX,double offsetY);

GVMCardSize GVMCarPlayCardSizeForView(GVMInterfaceStyle style,double availableWidth,double availableHeight,
    double viewWidth,double screenWidth,double screenHeight,NSUInteger alerts);

GVMCardSize GVMCarPlayCardSizeForLayout(GVMInterfaceStyle style,double width,double height,double screenWidth,double screenHeight,NSUInteger alerts,BOOL dashboard,NSUInteger layout,double percent);

typedef struct { double x, y, width, height; } GVMModuleRect;
GVMCardSize GVMCardCanvasSize(GVMInterfaceStyle style,NSUInteger alerts,BOOL vertical);

// Classic canvas: each visible value or warning occupies one equal cell. Alerts move as a group.
GVMModuleRect GVMModuleFrame(NSArray<NSString *> *order,NSString *module,
    BOOL vertical,NSUInteger alerts,NSUInteger alertIndex);

// Halo canvas, in points at the L size: one dial block (speed with the limit badge and the
// source tag) and up to two alerts beside it (horizontal) or below it (vertical). Each alert is
// a large sign with its distance tag under it, the way the source tag sits under the dial.
// Alerts move as a group before or after the dial.
extern const double GVMHaloPadding, GVMHaloDialBlock, GVMHaloDial, GVMHaloGap;
// The limit badge covers a third of the dial's area (72 x sqrt(1/3)). Its centre sits 3 inside the
// dial's right edge and 8 below its top.
extern const double GVMHaloBadge, GVMHaloBadgeInset, GVMHaloBadgeDrop;
extern const double GVMHaloAlertWidth, GVMHaloAlertHeight, GVMHaloAlertSign, GVMHaloAlertSignTop;
// Row and column follow the chosen layout. Stack puts the alerts in one row under the dial (over it
// when alerts come first); it is used only when the chosen layout does not fit at the chosen size,
// so the dial keeps its size instead of shrinking for arriving alerts. A stack lines up with the
// card's anchored side (trailing for right-hand placements) so the dial also keeps its place.
typedef NS_ENUM(NSUInteger, GVMHaloArrangement) { GVMHaloRow, GVMHaloColumn, GVMHaloStack };
GVMHaloArrangement GVMHaloArrangementFor(GVMCardSize size);
GVMCardSize GVMHaloCanvasSize(GVMHaloArrangement arrangement,NSUInteger alerts);
GVMModuleRect GVMHaloDialFrame(GVMHaloArrangement arrangement,BOOL alertsFirst,BOOL trailing,NSUInteger alerts);
GVMModuleRect GVMHaloAlertFrame(GVMHaloArrangement arrangement,BOOL alertsFirst,BOOL trailing,NSUInteger alerts,NSUInteger index);
// Lane strip, in points at size L: one cell per lane (30 wide up to six lanes, 26 up to eight, 22
// beyond), arrows 4 narrower than the cell and a plate 20 taller than the arrows. Lanes in effect
// have no distance and the strip is the plate. Lanes announced ahead (GVMLaneStripTagged) carry a
// distance tag across the plate's bottom edge, like the sign tags: 10 more points (half the tag and
// its stroke), and at least the tag's width. Per-lane speed limits (GVMLaneStripLimits) add a row of
// round signs 8 narrower than the cell, 3 under the arrows; without arrows (GVMLaneStripLimitsOnly)
// the row stands alone in the middle of a plate 20 taller than the signs. `sign` and `signTop` are 0
// without the row.
typedef NS_OPTIONS(NSUInteger, GVMLaneStripOptions) {
    GVMLaneStripTagged=1, GVMLaneStripLimits=2, GVMLaneStripLimitsOnly=4
};
typedef struct { double cell, arrow, plate, width, height, sign, signTop; } GVMLaneStripMetrics;
GVMLaneStripMetrics GVMLaneStripMetricsFor(NSUInteger lanes, NSUInteger options);
// The options a lanes sample needs: tagged when it has a distance; limits when every lane carries one,
// limits only when, besides, no lane has a known direction.
NSUInteger GVMLaneStripOptionsFor(NSDictionary *lanes);
// The plate's own width (the strip may be wider for a tag).
double GVMLanePlateWidth(GVMLaneStripMetrics strip, NSUInteger lanes);
// Arrows never drop below this many points, whatever the bubble size.
extern const double GVMLaneMinimumArrow;
typedef NS_ENUM(NSUInteger, GVMLaneStripPlace) { GVMLaneStripHidden, GVMLaneStripBelow, GVMLaneStripAbove, GVMLaneStripBeside };
// `options` are the ones the strip was laid out with: those asked for, less the limit row when the
// strip only fits without it.
typedef struct { GVMModuleRect frame; double scale; GVMLaneStripPlace place; NSUInteger options; } GVMLaneStripLayout;
// Places the strip for a New UI bubble already laid out at `card` (host points, `cardScale` points per
// canvas unit, dial block at `dial`) and anchored to the `right`/`bottom` edges of `area`. The bubble
// with its lanes may use `reachWidth` x `reachHeight` of the area from the anchored corner (or the
// card's own size if larger). Rows and stacks put the strip on the inner side, lined up with the
// dial's edge; columns put it beside the dial on the inner side, else on the inner side of the
// column. The strip keeps the bubble's scale, shrinks on its own to fit down to the minimum arrow,
// drops its limit row before giving up its arrows, and is hidden rather than cut. The dial never
// moves.
GVMLaneStripLayout GVMLaneStripLayoutFor(GVMModuleRect card, double cardScale, GVMHaloArrangement arrangement,
    GVMModuleRect dial, BOOL right, BOOL bottom, NSUInteger lanes, NSUInteger options, GVMModuleRect area,
    double reachWidth, double reachHeight);
// Navigation: CarPlay's guidance column has a free slot between its maneuver card and the arrival
// estimates (`slot`, host points). Signs in effect (up to two) and the lane strip are laid out there in
// one row from the slot's leading edge, centred in its height. Signs are at most the bubble's sign size
// (cardScale) and at least 20 points; the strip keeps its 14-point arrows. The strip's limit row gives
// way first; then what does not fit stays in the bubble: a second sign first, then the first, then
// the lanes. `stripOptions` are the options the strip was laid out with.
typedef struct {
    NSUInteger signs; BOOL lanes; double diameter;
    GVMModuleRect signFrames[2]; GVMModuleRect strip; double stripScale; NSUInteger stripOptions;
} GVMEffectDock;
GVMEffectDock GVMEffectDockFor(GVMModuleRect slot, NSUInteger signs, NSUInteger lanes, NSUInteger options, double cardScale);
// Stored orders keep their three names; the limit now lives on the dial, so only whether
// alerts come first matters.
BOOL GVMAlertsFirst(NSArray<NSString *> *order);
