#import <Preferences/PSListController.h>
#import <Preferences/PSListItemsController.h>
#import <Preferences/PSSpecifier.h>
#include <notify.h>
#import "scale-math.h"

@interface CPSPreferencesController : PSListController
@end

@interface CPSSizeListController : PSListItemsController
@end

// Present in Preferences.framework; Theos' header omits it.
@interface PSSpecifier (CPSListValues)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
@end

static NSString *const CPSApplyIdentifier = @"apply";
static NSString *const CPSApplyTitle = @"Áp dụng";

// A preference row saved by PSListController's own handling in the CarPlay Scale domain.
static PSSpecifier *CPSPreference(NSString *name, id target, NSString *key, id defaultValue, Class detail, PSCellType cell) {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:name target:target set:@selector(setPreferenceValue:specifier:)
        get:@selector(readPreferenceValue:) detail:detail cell:cell edit:Nil];
    [item setProperty:key forKey:@"key"];
    [item setProperty:defaultValue forKey:@"default"];
    [item setProperty:@CPS_PREFERENCES_DOMAIN forKey:@"defaults"];
    return item;
}

// Clears the crash-loop count, since a deliberate save or Apply re-arms scaling, and makes the change reach cfprefsd.
static void CPSRearmAndSynchronize(void) {
    CFPreferencesSetAppValue(CFSTR(CPS_UNCONFIRMED_LAUNCHES_KEY), NULL, CFSTR(CPS_PREFERENCES_DOMAIN));
    CFPreferencesAppSynchronize(CFSTR(CPS_PREFERENCES_DOMAIN));
}

// The Apply button and the empty group above it, shown at the bottom of both pages.
static NSArray *CPSApplySpecifiers(id target) {
    PSSpecifier *apply = [PSSpecifier preferenceSpecifierNamed:CPSApplyTitle target:target set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
    apply.identifier = CPSApplyIdentifier;
    apply.buttonAction = @selector(applyChoice:);
    return @[[PSSpecifier groupSpecifierWithName:nil], apply];
}

// Asks CarPlay to use the saved choice now (it restarts only on a difference), then reads "Đã áp dụng" for two seconds.
static void CPSApply(PSListController *controller, PSSpecifier *button) {
    CPSRearmAndSynchronize();
    notify_post(CPS_CHANGED_NOTIFICATION);
    button.name = @"Đã áp dụng";
    [controller reloadSpecifier:button animated:NO];
    __weak PSListController *weakController = controller;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        button.name = CPSApplyTitle;
        [weakController reloadSpecifier:button animated:NO];
    });
}

// Taps on the Apply row are handled here, so the size list never treats the button as a size choice.
static BOOL CPSHandleApplyTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath) {
    PSSpecifier *specifier = [controller specifierAtIndexPath:indexPath];
    if (![specifier.identifier isEqual:CPSApplyIdentifier]) return NO;
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CPSApply(controller, specifier);
    return YES;
}

@implementation CPSPreferencesController
// Saves the value itself as well, so CarPlay never depends on how PSListController stores it. Nothing changes
// on the car until Apply (or the next CarPlay connection).
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length) CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, CFSTR(CPS_PREFERENCES_DOMAIN));
    CPSRearmAndSynchronize();
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        PSSpecifier *enabled = CPSPreference(@"Thu nhỏ giao diện", self, @"enabled", @YES, Nil, PSSwitchCell);
        NSMutableArray *values = [NSMutableArray array], *titles = [NSMutableArray array];
        for (NSUInteger i = 0; i < CPSPercentChoiceCount; i++) {
            [values addObject:@(CPSPercentChoices[i])];
            [titles addObject:[NSString stringWithFormat:@"%ld%%", (long)CPSPercentChoices[i]]];
        }
        PSSpecifier *size = CPSPreference(@"Cỡ giao diện", self, @"percent", @(CPSPercentDefault), CPSSizeListController.class, PSLinkListCell);
        [size setValues:values titles:titles];
        NSMutableArray *items = [@[[PSSpecifier groupSpecifierWithName:nil], enabled, size] mutableCopy];
        [items addObjectsFromArray:CPSApplySpecifiers(self)];
        _specifiers = items;
    }
    return _specifiers;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!CPSHandleApplyTap(self, tableView, indexPath)) [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (void)applyChoice:(PSSpecifier *)specifier {
    CPSApply(self, specifier);
}
@end

// The standard size list with the Apply button under it.
@implementation CPSSizeListController
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[super specifiers] mutableCopy];
        [items addObjectsFromArray:CPSApplySpecifiers(self)];
        _specifiers = items;
    }
    return _specifiers;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!CPSHandleApplyTap(self, tableView, indexPath)) [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (void)applyChoice:(PSSpecifier *)specifier {
    CPSApply(self, specifier);
}
@end
