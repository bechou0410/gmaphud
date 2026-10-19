#import "scale-math.h"
#include <math.h>

const NSInteger CPSPercentChoices[] = {90, 85, 80, 75, 70};
const NSUInteger CPSPercentChoiceCount = sizeof CPSPercentChoices / sizeof CPSPercentChoices[0];
const NSInteger CPSPercentDefault = 80;

static BOOL IsChoice(NSInteger percent) {
    for (NSUInteger i = 0; i < CPSPercentChoiceCount; i++)
        if (CPSPercentChoices[i] == percent) return YES;
    return NO;
}

CGFloat CPSRatioFromPreferences(NSNumber *enabled, NSNumber *percent) {
    if ([enabled isKindOfClass:NSNumber.class] && !enabled.boolValue) return 0;
    NSInteger chosen = [percent isKindOfClass:NSNumber.class] && IsChoice(percent.integerValue) ? percent.integerValue : CPSPercentDefault;
    return chosen / 100.0;
}

CPSScaledMode CPSMakeScaledMode(CGSize pixelSize, CGFloat nativeScale, CGFloat ratio) {
    CPSScaledMode mode = {0};
    if (!isfinite(pixelSize.width) || !isfinite(pixelSize.height) || !isfinite(nativeScale) || !isfinite(ratio)) return mode;
    if (pixelSize.width <= 0 || pixelSize.height <= 0 || nativeScale <= 0 || ratio <= 0 || ratio >= 1) return mode;
    CGFloat ideal = round(pixelSize.width / (nativeScale * ratio));
    if (!isfinite(ideal) || ideal < 1) return mode;
    // FrontBoard stores floor(points x scale) as the pixel size and hands apps pixels / scale as the point size.
    // A whole width (or a close neighbour) for which both round trips are exact keeps every pixel column and gives
    // apps a whole number of points; otherwise the scale is nudged up so no pixel column is lost.
    static const CGFloat offsets[] = {0, 1, -1, 2, -2};
    CGFloat width = ideal, scale = pixelSize.width / ideal;
    BOOL exact = NO;
    for (NSUInteger i = 0; i < sizeof offsets / sizeof offsets[0] && !exact; i++) {
        CGFloat candidate = ideal + offsets[i], candidateScale = pixelSize.width / candidate;
        if (candidate < 1 || candidate * candidateScale < pixelSize.width || pixelSize.width / candidateScale < candidate) continue;
        width = candidate;
        scale = candidateScale;
        exact = YES;
    }
    while (!exact && width * scale < pixelSize.width) scale = nextafter(scale, INFINITY);
    // The height is rarely whole; it only has to keep every pixel row.
    CGFloat height = pixelSize.height / scale;
    while (height * scale < pixelSize.height) height = nextafter(height, INFINITY);
    mode.scale = scale;
    mode.pointSize = CGSizeMake(width, height);
    mode.valid = YES;
    return mode;
}
