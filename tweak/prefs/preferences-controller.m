#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <UIKit/UIKit.h>
#import "placement-state.h"
#import "source-transport.h"
#import "diagnostics-controller.h"
#import "modules-controller.h"
#include <notify.h>
#include <math.h>
#import "background-policy.h"

static CGFloat GVMMenuHeight(void) {
    return MAX(52,ceil([UIFont preferredFontForTextStyle:UIFontTextStyleBody].lineHeight*2+20));
}
static CGFloat GVMChoiceHeight(void) {
    return MAX(100,ceil([UIFont preferredFontForTextStyle:UIFontTextStyleBody].lineHeight*2+68));
}
static CGFloat GVMSliderHeight(void) {
    return MAX(140,ceil([UIFont preferredFontForTextStyle:UIFontTextStyleBody].lineHeight*2+88));
}
static NSString * const GVMPreferencesValueChanged=@"GVMPreferencesValueChanged";
static PSSpecifier *GVMGroup(NSString *title,NSString *footer) {
    PSSpecifier *group=[PSSpecifier groupSpecifierWithName:title];
    if (footer.length) [group setProperty:footer forKey:@"footerText"];
    return group;
}
@interface GVMMenuCell : PSTableCell
@property(nonatomic,strong) UIButton *menuButton;
@property(nonatomic,strong) UILabel *settingLabel;
@property(nonatomic,strong) PSSpecifier *settingSpecifier;
- (void)refreshMenu;
@end
static PSSpecifier *GVMMenu(NSString *title,id target,NSString *key,NSArray *values,NSArray *titles,id defaultValue) {
    PSSpecifier *item=[PSSpecifier preferenceSpecifierNamed:title target:target set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil];
    [item setProperty:key forKey:@"key"];
    [item setProperty:values forKey:@"values"];
    [item setProperty:titles forKey:@"titles"];
    [item setProperty:defaultValue forKey:@"default"];
    [item setProperty:GVMMenuCell.class forKey:@"cellClass"];
    // Static Preferences cells are noninteractive unless enabled explicitly.
    [item setProperty:@YES forKey:@"enabled"];
    [item setProperty:@(GVMMenuHeight()) forKey:@"height"];
    return item;
}
static BOOL GVMStorePlacement(NSString *key,id value) {
    CFStringRef domain=CFSTR("com.chou.gmaphud");
    CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)value,domain);
    if (!CFPreferencesAppSynchronize(domain)) return NO;
    NSString *full=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("fullPosition"),domain));
    NSString *dashboard=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("dashboardPosition"),domain));
    int token=-1;
    if (notify_register_check(GVMPlacementStateName,&token)==NOTIFY_STATUS_OK) {
        notify_set_state(token,GVMEncodePlacement(full,dashboard));
        notify_post(GVMPlacementStateName);
        notify_cancel(token);
    }
    return YES;
}
@interface GVMSegmentedCell : PSTableCell
@property(nonatomic,strong) UISegmentedControl *picker;
@property(nonatomic,strong) PSSpecifier *settingSpecifier;
@end
@implementation GVMSegmentedCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    if (!(self=[super initWithStyle:style reuseIdentifier:identifier specifier:specifier])) return nil;
    self.settingSpecifier=specifier; self.selectionStyle=UITableViewCellSelectionStyleNone;
    UILabel *label=[UILabel new]; label.text=specifier.name; label.numberOfLines=0;
    label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; label.textColor=UIColor.labelColor; label.adjustsFontForContentSizeCategory=YES;
    self.picker=[[UISegmentedControl alloc] initWithItems:[specifier propertyForKey:@"titles"]]; self.picker.accessibilityLabel=specifier.name;
    NSArray *values=[specifier propertyForKey:@"values"];
    CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"));
    id saved=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)[specifier propertyForKey:@"key"],CFSTR("com.chou.gmaphud")));
    NSUInteger index=[values indexOfObject:saved ?: [specifier propertyForKey:@"default"]];
    self.picker.selectedSegmentIndex=index==NSNotFound ? 0 : (NSInteger)index;
    [self.picker addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
    [self.picker.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[label,self.picker]]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=8; stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],[stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],[stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8]]];
    return self;
}
- (void)layoutSubviews { [super layoutSubviews]; self.textLabel.hidden=YES; self.detailTextLabel.hidden=YES; }
- (void)changed:(UISegmentedControl *)picker {
    NSArray *values=[self.settingSpecifier propertyForKey:@"values"];
    if (picker.selectedSegmentIndex<0 || (NSUInteger)picker.selectedSegmentIndex>=values.count) return;
    NSString *key=[self.settingSpecifier propertyForKey:@"key"];
    if (![@[@"interfaceStyle",@"haloDial",@"overspeedScope",@"fullLayout",@"dashboardLayout",@"phoneLayout"] containsObject:key]) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)values[picker.selectedSegmentIndex],CFSTR("com.chou.gmaphud"));
    if (CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"))) { GVMPublishSavedSizes(); notify_post(GVMSizeChangedName); [NSNotificationCenter.defaultCenter postNotificationName:GVMPreferencesValueChanged object:key]; }
}
@end

@interface GVMSizeSliderCell : PSTableCell
@property(nonatomic,copy) NSString *sizeKey;
@property(nonatomic,strong) UISlider *sizeSlider;
@property(nonatomic,strong) UILabel *valueLabel;
@property(nonatomic) BOOL offset;
@end
@implementation GVMSizeSliderCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self=[super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (!self) return nil;
    self.selectionStyle=UITableViewCellSelectionStyleNone;
    self.contentView.userInteractionEnabled=YES;
    self.sizeKey=[specifier propertyForKey:@"key"];
    self.offset=[@[@"phoneXPercent",@"phoneYPercent"] containsObject:self.sizeKey];
    UILabel *label=[UILabel new]; label.text=specifier.name; label.numberOfLines=0;
    label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; label.textColor=UIColor.labelColor; label.adjustsFontForContentSizeCategory=YES;
    self.valueLabel=[UILabel new]; self.valueLabel.textColor=UIColor.secondaryLabelColor;
    self.valueLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.valueLabel.textAlignment=NSTextAlignmentRight; self.valueLabel.adjustsFontForContentSizeCategory=YES;
    [self.valueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIButton *reset=[UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:@"Đặt lại" forState:UIControlStateNormal];
    reset.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
    reset.accessibilityLabel=[@"Đặt lại " stringByAppendingString:specifier.name];
    [reset addTarget:self action:@selector(resetSize) forControlEvents:UIControlEventTouchUpInside];

    [reset.heightAnchor constraintEqualToConstant:44].active=YES;
    UIStackView *header=[[UIStackView alloc] initWithArrangedSubviews:@[label,self.valueLabel]];
    header.axis=UILayoutConstraintAxisHorizontal; header.alignment=UIStackViewAlignmentCenter; header.spacing=8;
    // Float on both branches: with the unsigned size limits, -100 would become a huge minimum.
    self.sizeSlider=[UISlider new]; self.sizeSlider.minimumValue=self.offset ? -100.0f : (float)GVMSizePercentMin; self.sizeSlider.maximumValue=self.offset ? 100.0f : (float)GVMSizePercentMax;
    self.sizeSlider.accessibilityLabel=specifier.name;
    self.sizeSlider.accessibilityHint=self.offset ? @"0 phần trăm giữ nguyên góc đã chọn" : @"100 phần trăm là kích cỡ mặc định";
    CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"));
    id saved=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)self.sizeKey,CFSTR("com.chou.gmaphud")));
    self.sizeSlider.value=GVMSliderPercent(saved,self.offset);
    [self.sizeSlider addTarget:self action:@selector(sizeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.sizeSlider.heightAnchor constraintEqualToConstant:44].active=YES;
    UIView *separator=[UIView new]; separator.backgroundColor=UIColor.separatorColor;
    [separator.heightAnchor constraintEqualToConstant:1.0/UIScreen.mainScreen.scale].active=YES;
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[header,self.sizeSlider,separator,reset]];
    stack.axis=UILayoutConstraintAxisVertical; stack.spacing=0; stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
        [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8]]];
    [self updateValue]; return self;
}
- (void)layoutSubviews { [super layoutSubviews]; self.textLabel.hidden=YES; self.detailTextLabel.hidden=YES; }
- (void)updateValue {
    self.valueLabel.text=[NSString stringWithFormat:@"%ld%%",(long)lroundf(self.sizeSlider.value)];
    self.sizeSlider.accessibilityValue=self.valueLabel.text;
}
- (void)sizeChanged:(UISlider *)slider {
    if (![@[@"fullScale",@"dashboardScale",@"phoneScale",@"phoneXPercent",@"phoneYPercent"] containsObject:self.sizeKey]) return;
    float neutral=self.offset ? 0 : 100;
    if (fabsf(slider.value-neutral)<=2) slider.value=neutral;
    NSNumber *value=self.offset ? @(GVMOffsetPercent(@(slider.value))) : @(GVMSizePercent(@(slider.value)));
    CFPreferencesSetAppValue((__bridge CFStringRef)self.sizeKey,(__bridge CFPropertyListRef)value,CFSTR("com.chou.gmaphud"));
    if (CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"))) { GVMPublishSavedSizes(); notify_post(GVMSizeChangedName); }
    [self updateValue];
}
- (void)resetSize { [self.sizeSlider setValue:self.offset ? 0 : 100 animated:!UIAccessibilityIsReduceMotionEnabled()]; [self sizeChanged:self.sizeSlider]; }
@end

@interface GVMPreferencesController : PSListController
@property(nonatomic,strong) PSSpecifier *sourceSpecifier;
@end
@interface GVMSurfaceController : GVMPreferencesController
@end
@interface GVMPhonePositionController : GVMPreferencesController
@end
@interface GVMPositionController : GVMPreferencesController

@end
@interface GVMOverspeedController : GVMPreferencesController
@end

@implementation GVMPreferencesController
- (void)refreshControlHeights {
    for (PSSpecifier *item in _specifiers) {
        Class cell=[item propertyForKey:@"cellClass"];
        if (cell==GVMMenuCell.class) [item setProperty:@(GVMMenuHeight()) forKey:@"height"];
        else if (cell==GVMSegmentedCell.class) [item setProperty:@(GVMChoiceHeight()) forKey:@"height"];
        else if (cell==GVMSizeSliderCell.class) [item setProperty:@(GVMSliderHeight()) forKey:@"height"];
    }
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (previous && ![previous.preferredContentSizeCategory isEqual:self.traitCollection.preferredContentSizeCategory]) {
        [self refreshControlHeights]; [self reloadSpecifiers];
    }
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    CGSize screen=UIScreen.mainScreen.bounds.size;
    GVMMigratePhoneOffsets(screen.width,screen.height);
    GVMPublishSavedSizes();
    [self refreshControlHeights];
    if (self.sourceSpecifier) [self reloadSpecifier:self.sourceSpecifier];
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title=@"GMapHUD";
    NSMutableArray *items=[NSMutableArray new];
    [items addObject:GVMGroup(@"Hiển thị",nil)];
    PSSpecifier *master=[PSSpecifier preferenceSpecifierNamed:@"Hiển thị bong bóng" target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:Nil cell:PSSwitchCell edit:Nil];
    [master setProperty:@"bubbleEnabled" forKey:@"key"]; [master setProperty:@YES forKey:@"default"]; [items addObject:master];
    [items addObject:GVMGroup(@"Giao diện",@"Classic là bong bóng quen thuộc. New UI (beta) là bong bóng mới đang thử nghiệm; vòng lớn của nó là tốc độ hiện tại hoặc biển giới hạn tốc độ. Cả hai kiểu dùng chung bộ biển báo, kích thước và vị trí.")];
    PSSpecifier *style=GVMMenu(@"Kiểu bong bóng",self,@"interfaceStyle",@[@"classic",@"halo"],@[@"Classic",@"New UI (beta)"],@"classic");
    [style setProperty:GVMSegmentedCell.class forKey:@"cellClass"]; [style setProperty:@(GVMChoiceHeight()) forKey:@"height"]; [items addObject:style];
    PSSpecifier *dial=GVMMenu(@"Vòng lớn (New UI)",self,@"haloDial",@[@"speed",@"limit"],@[@"Tốc độ",@"Giới hạn"],@"speed");
    [dial setProperty:GVMSegmentedCell.class forKey:@"cellClass"]; [dial setProperty:@(GVMChoiceHeight()) forKey:@"height"]; [items addObject:dial];
    [items addObject:GVMGroup(@"Nguồn cảnh báo",@"Chỉ nhận dữ liệu từ một nguồn.")];
    self.sourceSpecifier=GVMMenu(@"Nguồn",self,@"sourceID",@[@1,@3,@2],@[@"VietMap Live",@"GOFA",@"Waze"],@1);
    [items addObject:self.sourceSpecifier];
    [items addObject:GVMGroup(@"Tự động hóa",@"Đánh thức nguồn đã chọn khi Google Maps hiển thị; nguồn crash liên tục hoặc chưa cài sau 5 lần thử (mỗi 3 giây) được tạm thay bằng nguồn khác đến phiên Google Maps sau. GMapHUD chỉ đóng nguồn do nó tự mở và chưa từng hiện trên iPhone hay CarPlay: khi đổi nguồn và 10 giây sau khi đóng Google Maps. Tự thoát sau 20 giây ngắt CarPlay; kết nối lại hoặc mở Google Maps trên iPhone sẽ hủy đếm giờ.")];
    for (NSArray *option in @[@[@"Đánh thức nguồn đã chọn",@"autoWake"],@[@"Thoát nguồn khi ngắt CarPlay",@"autoExit"]]) {
        PSSpecifier *toggle=[PSSpecifier preferenceSpecifierNamed:option[0] target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:Nil cell:PSSwitchCell edit:Nil];
        [toggle setProperty:option[1] forKey:@"key"]; [toggle setProperty:@NO forKey:@"default"]; [items addObject:toggle];
    }
    [items addObject:GVMGroup(@"Cảnh báo",nil)];
    PSSpecifier *overspeed=GVMMenu(@"Cảnh báo vượt tốc",self,@"overspeedScope",@[@"off",@"map",@"screen"],@[@"Tắt",@"Bản đồ",@"Toàn màn hình"],@"off");
    [overspeed setProperty:GVMSegmentedCell.class forKey:@"cellClass"]; [overspeed setProperty:@(GVMChoiceHeight()) forKey:@"height"]; [items addObject:overspeed];
    [items addObject:GVMGroup(@"Bố cục bong bóng",@"Điều chỉnh riêng cho từng màn hình.")];
    NSArray *titles=@[@"CarPlay · Toàn màn hình",@"CarPlay · Dashboard",@"iPhone"];
    NSArray *surfaces=@[@"full",@"dashboard",@"phone"];
    for (NSUInteger i=0;i<surfaces.count;i++) {
        PSSpecifier *surface=[PSSpecifier preferenceSpecifierNamed:titles[i] target:self set:NULL get:NULL detail:GVMSurfaceController.class cell:PSLinkCell edit:Nil];
        [surface setProperty:surfaces[i] forKey:@"surface"]; [surface setProperty:surfaces[i] forKey:@"id"]; [items addObject:surface];
    }
    [items addObject:GVMGroup(@"Hỗ trợ",nil)];
    [items addObject:[PSSpecifier preferenceSpecifierNamed:@"Chẩn đoán" target:self set:NULL get:NULL detail:GVMDiagnosticsController.class cell:PSLinkCell edit:Nil]];
    _specifiers=items;
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    if (![key isKindOfClass:NSString.class]) return nil;
    CFStringRef domain=CFSTR("com.chou.gmaphud");
    CFPreferencesAppSynchronize(domain);
    id value=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,domain));
    return value ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    if ([key isEqual:@"overspeedScope"]) {
        if (![@[@"off",@"map",@"screen"] containsObject:value]) return;
        CFPreferencesSetAppValue(CFSTR("overspeedScope"),(__bridge CFStringRef)value,CFSTR("com.chou.gmaphud"));
        if (CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"))) { GVMPublishSavedSizes(); notify_post(GVMSizeChangedName); }
        return;
    }
    if ([@[@"autoWake",@"autoExit",@"bubbleEnabled",@"fullEnabled",@"dashboardEnabled",@"phoneEnabled"] containsObject:key]) {
        if (![value isKindOfClass:NSNumber.class]) return;
        CFPreferencesSetAppValue((__bridge CFStringRef)key,[value boolValue] ? kCFBooleanTrue : kCFBooleanFalse,CFSTR("com.chou.gmaphud"));
        if (CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"))) {
            GVMPublishSavedSizes(); notify_post(GVMSizeChangedName);
        }
        return;
    }
    BOOL offsetPreference=[@[@"phoneXPercent",@"phoneYPercent"] containsObject:key];
    BOOL sizePreference=offsetPreference || [@[@"fullScale",@"dashboardScale",@"phoneScale"] containsObject:key];
    if (sizePreference) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFNumberRef)(offsetPreference ? @(GVMOffsetPercent(value)) : @(GVMSizePercent(value))),CFSTR("com.chou.gmaphud"));
        if (CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"))) {
            GVMPublishSavedSizes(); notify_post(GVMSizeChangedName);
        }
        return;
    }
    if (![key isEqualToString:@"fullPosition"] && ![key isEqualToString:@"dashboardPosition"]) return;
    GVMStorePlacement(key,value);
}
@end

@interface GVMPositionPreviewCell : PSTableCell
@property(nonatomic,strong) UIImageView *preview;
@property(nonatomic,copy) NSString *positionKey;
@end
@implementation GVMPositionPreviewCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self=[super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (!self) return nil;
    self.positionKey=[specifier propertyForKey:@"key"];
    self.preview=[UIImageView new]; self.preview.contentMode=UIViewContentModeScaleAspectFit;
    self.preview.translatesAutoresizingMaskIntoConstraints=NO; self.preview.isAccessibilityElement=YES;
    [self.contentView addSubview:self.preview];
    [NSLayoutConstraint activateConstraints:@[
        [self.preview.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.preview.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.preview.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
        [self.preview.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8]]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshPreview) name:GVMPreferencesValueChanged object:nil];
    [self refreshPreview]; return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)layoutSubviews { [super layoutSubviews]; self.textLabel.hidden=YES; self.detailTextLabel.hidden=YES; }
- (void)refreshPreview {
    CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"));
    BOOL dashboard=[self.positionKey isEqual:@"dashboardPosition"];
    NSString *value=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)self.positionKey,CFSTR("com.chou.gmaphud")));
    NSArray *valid=dashboard ? @[@"left",@"right"] : @[@"top-left",@"top-right",@"bottom-left",@"bottom-right"];
    if (![valid containsObject:value]) value=dashboard ? @"right" : @"top-right";
    NSString *name=[NSString stringWithFormat:@"%@-%@",dashboard ? @"dashboard" : @"full-map",value];
    self.preview.image=[UIImage imageNamed:name inBundle:[NSBundle bundleForClass:self.class] compatibleWithTraitCollection:nil];
    self.preview.accessibilityLabel=@"Minh họa vị trí bong bóng trên CarPlay";
    self.preview.accessibilityValue=value;
}
@end
@implementation GVMPositionController
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title=@"Vị trí";
    BOOL dashboard=[[self.specifier propertyForKey:@"key"] isEqual:@"dashboardPosition"];
    NSString *key=dashboard ? @"dashboardPosition" : @"fullPosition";
    PSSpecifier *preview=[PSSpecifier preferenceSpecifierNamed:@"Minh họa" target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil];
    [preview setProperty:key forKey:@"key"]; [preview setProperty:GVMPositionPreviewCell.class forKey:@"cellClass"]; [preview setProperty:@200 forKey:@"height"];
    _specifiers=[@[GVMGroup(@"Vị trí trên CarPlay",dashboard ? @"Chọn cạnh của ô bản đồ Dashboard." : @"Chọn góc của bản đồ toàn màn hình."),
        GVMMenu(@"Vị trí",self,key,dashboard ? @[@"left",@"right"] : @[@"top-left",@"top-right",@"bottom-left",@"bottom-right"],
            dashboard ? @[@"Bên trái",@"Bên phải"] : @[@"Trên trái",@"Trên phải",@"Dưới trái",@"Dưới phải"],dashboard ? @"right" : @"top-right"),preview] mutableCopy];
    return _specifiers;
}
@end
@implementation GVMMenuCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self=[super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (!self) return nil;
    self.settingSpecifier=specifier; self.selectionStyle=UITableViewCellSelectionStyleNone;
    self.userInteractionEnabled=YES; self.contentView.userInteractionEnabled=YES;
    self.settingLabel=[UILabel new]; self.settingLabel.text=specifier.name; self.settingLabel.numberOfLines=0;
    self.settingLabel.textColor=UIColor.labelColor;
    self.settingLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; self.settingLabel.adjustsFontForContentSizeCategory=YES;
    self.settingLabel.isAccessibilityElement=NO;
    self.settingLabel.translatesAutoresizingMaskIntoConstraints=NO; self.settingLabel.userInteractionEnabled=NO;
    [self.contentView addSubview:self.settingLabel];
    self.menuButton=[UIButton buttonWithType:UIButtonTypeSystem];
    self.menuButton.translatesAutoresizingMaskIntoConstraints=NO; self.menuButton.showsMenuAsPrimaryAction=YES;
    self.menuButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight;
    self.menuButton.accessibilityLabel=specifier.name;
    self.menuButton.accessibilityHint=@"Chạm để chọn trong menu";
    [self.contentView addSubview:self.menuButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.settingLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.settingLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.settingLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.45],
        [self.menuButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.menuButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.menuButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.menuButton.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor]]];
    [self refreshMenu]; return self;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (previous && previous.userInterfaceStyle!=self.traitCollection.userInterfaceStyle && self.settingSpecifier) [self refreshMenu];
}
- (void)layoutSubviews {
    [super layoutSubviews]; self.textLabel.hidden=YES; self.detailTextLabel.hidden=YES;
    CGFloat valueLeadingInset=ceil(self.contentView.bounds.size.width*0.45)+16;
    if (@available(iOS 15.0,*)) {
        UIButtonConfiguration *configuration=self.menuButton.configuration;
        if (fabs(configuration.contentInsets.leading-valueLeadingInset)>0.5) {
            NSDirectionalEdgeInsets insets=configuration.contentInsets; insets.leading=valueLeadingInset;
            configuration.contentInsets=insets; self.menuButton.configuration=configuration;
        }
    } else {
        UIEdgeInsets insets=self.menuButton.contentEdgeInsets; insets.left=valueLeadingInset;
        self.menuButton.contentEdgeInsets=insets;
    }
}
- (void)refreshMenu {
    NSString *key=[self.settingSpecifier propertyForKey:@"key"];
    BOOL source=[key isEqual:@"sourceID"];
    NSArray *values=[self.settingSpecifier propertyForKey:@"values"], *titles=[self.settingSpecifier propertyForKey:@"titles"];
    CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"));
    id saved=source ? @(GVMSelectedSourceID()) : CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,CFSTR("com.chou.gmaphud")));
    NSUInteger selected=[values indexOfObject:saved ?: [self.settingSpecifier propertyForKey:@"default"]];
    if (selected==NSNotFound) selected=[values indexOfObject:[self.settingSpecifier propertyForKey:@"default"]];
    NSMutableArray *actions=[NSMutableArray new]; __weak GVMMenuCell *weakSelf=self;
    void (^selectValue)(id)=^(id value) {
        if (source) {
            if (!GVMSelectOutputSource([value unsignedIntegerValue])) {
                UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"Không thể đổi nguồn. Hãy thử lại."); return;
            }
            GVMRequestSelectedSource();
        } else if ([key isEqual:@"fullPosition"] || [key isEqual:@"dashboardPosition"]) {
            if (!GVMStorePlacement(key,value)) return;
        } else {
            CFPreferencesSetAppValue((__bridge CFStringRef)key,([key hasSuffix:@"Modules"] && [value isEqual:@"auto"]) ? NULL : (__bridge CFPropertyListRef)value,CFSTR("com.chou.gmaphud"));
            if (!CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"))) return;
            GVMPublishSavedSizes(); notify_post(GVMSizeChangedName);
        }
        [NSNotificationCenter.defaultCenter postNotificationName:GVMPreferencesValueChanged object:key];
        [weakSelf refreshMenu];
    };
    for (NSUInteger i=0;i<values.count;i++) {
        id value=values[i]; BOOL enabled=!source || GVMSourceEnabled([value unsignedIntegerValue]);
        NSString *title=enabled ? titles[i] : [titles[i] stringByAppendingString:@" · Sắp hỗ trợ"];
        UIAction *action=[UIAction actionWithTitle:title image:nil identifier:nil handler:^(__unused UIAction *action) {
            selectValue(value);
        }];
        action.state=i==selected ? UIMenuElementStateOn : UIMenuElementStateOff;
        if (!enabled) { action.attributes=UIMenuElementAttributesDisabled;  }
        [actions addObject:action];
    }
    if (!source) {
        id defaultValue=[self.settingSpecifier propertyForKey:@"default"];
        UIAction *reset=[UIAction actionWithTitle:@"Đặt lại" image:nil identifier:nil
            handler:^(__unused UIAction *action) { selectValue(defaultValue); }];
        [actions addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[reset]]];
    }
    self.menuButton.menu=[UIMenu menuWithTitle:@"" children:actions];
    NSString *title=selected==NSNotFound ? @"Chọn" : titles[selected];
    self.menuButton.accessibilityValue=title;
    if (@available(iOS 15.0,*)) {
        UIButtonConfiguration *config=[UIButtonConfiguration plainButtonConfiguration];
        config.title=title; config.image=[UIImage systemImageNamed:@"chevron.up.chevron.down"];
        config.imagePlacement=NSDirectionalRectEdgeTrailing; config.imagePadding=6;
        config.contentInsets=NSDirectionalEdgeInsetsMake(8,16,8,16); config.baseForegroundColor=UIColor.secondaryLabelColor;
        config.titleTextAttributesTransformer=^NSDictionary *(NSDictionary *attributes) {
            NSMutableDictionary *result=[attributes mutableCopy]; result[NSFontAttributeName]=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; return result;
        };
        self.menuButton.configuration=config;
    } else { [self.menuButton setTitle:[title stringByAppendingString:@" ▾"] forState:UIControlStateNormal]; self.menuButton.contentEdgeInsets=UIEdgeInsetsMake(8,16,8,16); }
    self.menuButton.titleLabel.adjustsFontForContentSizeCategory=YES;
    self.menuButton.titleLabel.lineBreakMode=NSLineBreakByTruncatingHead;
}
@end

@implementation GVMSurfaceController
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title=self.specifier.name;
    NSString *surface=[self.specifier propertyForKey:@"surface"];
    if (![@[@"full",@"dashboard",@"phone"] containsObject:surface]) surface=@"full";
    BOOL phone=[surface isEqual:@"phone"], dashboard=[surface isEqual:@"dashboard"];
    NSMutableArray *items=[NSMutableArray new];
    PSSpecifier *group=[PSSpecifier groupSpecifierWithName:@""];
    [group setProperty:@"Bong bóng chỉ hiện khi công tắc tổng cũng đang bật." forKey:@"footerText"];
    [items addObject:group];
    PSSpecifier *enabled=[PSSpecifier preferenceSpecifierNamed:@"Hiển thị bong bóng" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:Nil cell:PSSwitchCell edit:Nil];
    [enabled setProperty:[surface stringByAppendingString:@"Enabled"] forKey:@"key"];
    [enabled setProperty:@YES forKey:@"default"];
    [items addObject:enabled];
    [items addObject:[PSSpecifier groupSpecifierWithName:@""]];
    NSString *positionKey=[surface stringByAppendingString:@"Position"];
    [items addObject:GVMMenu(@"Vị trí",self,positionKey,dashboard ? @[@"left",@"right"] : @[@"top-left",@"top-right",@"bottom-left",@"bottom-right"],dashboard ? @[@"Bên trái",@"Bên phải"] : @[@"Trên trái",@"Trên phải",@"Dưới trái",@"Dưới phải"],dashboard ? @"right" : @"top-right")];
    if (!phone) {
        PSSpecifier *preview=[PSSpecifier preferenceSpecifierNamed:@"Minh họa" target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil];
        [preview setProperty:positionKey forKey:@"key"]; [preview setProperty:GVMPositionPreviewCell.class forKey:@"cellClass"]; [preview setProperty:@200 forKey:@"height"]; [items addObject:preview];
    }
    PSSpecifier *layout=GVMMenu(@"Bố cục",self,[surface stringByAppendingString:@"Layout"],@[@"auto",@"horizontal",@"vertical"],@[@"Tự động",@"Ngang",@"Dọc"],@"auto");
    [layout setProperty:GVMSegmentedCell.class forKey:@"cellClass"]; [layout setProperty:@(GVMChoiceHeight()) forKey:@"height"]; [items addObject:layout];
    PSSpecifier *order=[PSSpecifier preferenceSpecifierNamed:@"Thứ tự các phần" target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil];
    [order setProperty:[surface stringByAppendingString:@"Modules"] forKey:@"key"]; [order setProperty:GVMModuleOrderCell.class forKey:@"cellClass"]; [order setProperty:@YES forKey:@"enabled"]; [order setProperty:@400 forKey:@"height"]; [items addObject:order];
    if (phone) for (NSString *key in @[@"phoneXPercent",@"phoneYPercent"]) {
        PSSpecifier *axis=[PSSpecifier preferenceSpecifierNamed:[key isEqual:@"phoneXPercent"] ? @"Trái / phải" : @"Lên / xuống" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:Nil cell:PSStaticTextCell edit:Nil];
        [axis setProperty:key forKey:@"key"]; [axis setProperty:@0 forKey:@"default"]; [axis setProperty:GVMSizeSliderCell.class forKey:@"cellClass"]; [axis setProperty:@YES forKey:@"enabled"]; [axis setProperty:@(GVMSliderHeight()) forKey:@"height"]; [items addObject:axis];
    }
    PSSpecifier *sizeGroup=[PSSpecifier groupSpecifierWithName:@""];
    [sizeGroup setProperty:@"100% là kích cỡ mặc định." forKey:@"footerText"];
    [items addObject:sizeGroup];
    PSSpecifier *size=[PSSpecifier preferenceSpecifierNamed:@"Kích cỡ" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:Nil cell:PSStaticTextCell edit:Nil];
    [size setProperty:[surface stringByAppendingString:@"Scale"] forKey:@"key"];
    [size setProperty:@100 forKey:@"default"];
    [size setProperty:GVMSizeSliderCell.class forKey:@"cellClass"];
    [size setProperty:@YES forKey:@"enabled"];
    [size setProperty:@(GVMSliderHeight()) forKey:@"height"];
    [items addObject:size];
    _specifiers=items; return _specifiers;
}
@end

@implementation GVMPhonePositionController
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title=@"Vị trí trên iPhone";
    NSMutableArray *items=[NSMutableArray new];
    PSSpecifier *group=[PSSpecifier groupSpecifierWithName:@""];
    [group setProperty:@"Chọn góc rồi tinh chỉnh trái/phải, lên/xuống. 0% giữ nguyên góc đã chọn." forKey:@"footerText"];
    [items addObject:group];
    [items addObject:GVMMenu(@"Góc",self,@"phonePosition",@[@"top-left",@"top-right",@"bottom-left",@"bottom-right"],@[@"Trên trái",@"Trên phải",@"Dưới trái",@"Dưới phải"],@"top-right")];
    for (NSString *key in @[@"phoneXPercent",@"phoneYPercent"]) {
        PSSpecifier *item=[PSSpecifier preferenceSpecifierNamed:[key isEqual:@"phoneXPercent"] ? @"Trái / phải" : @"Lên / xuống" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:Nil cell:PSStaticTextCell edit:Nil];
        [item setProperty:@YES forKey:@"enabled"];
        [item setProperty:@0 forKey:@"default"];
        [item setProperty:key forKey:@"key"];
        [item setProperty:GVMSizeSliderCell.class forKey:@"cellClass"];
        [item setProperty:@(GVMSliderHeight()) forKey:@"height"];
        [items addObject:item];
    }
    _specifiers=items; return _specifiers;
}
@end

@implementation GVMOverspeedController
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title=@"Vượt tốc độ";
    PSSpecifier *group=[PSSpecifier groupSpecifierWithName:@""];
    [group setProperty:@"Viền đỏ cảnh báo khi vượt giới hạn. Toàn màn hình gồm cả thanh bên CarPlay." forKey:@"footerText"];
    PSSpecifier *scope=GVMMenu(@"Phạm vi",self,@"overspeedScope",@[@"off",@"map",@"screen"],@[@"Tắt",@"Bản đồ",@"Toàn màn hình"],@"off");
    _specifiers=[@[group,scope] mutableCopy]; return _specifiers;
}
@end
