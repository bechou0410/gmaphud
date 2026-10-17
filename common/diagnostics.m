#import "diagnostics.h"
#include <notify.h>
#include <sys/sysctl.h>
#include <math.h>

// The build passes the package version from tweak/control so reports name the installed release.
#ifndef GVM_PACKAGE_VERSION
#define GVM_PACKAGE_VERSION "chưa rõ"
#endif
static NSString *const PackageVersion=@GVM_PACKAGE_VERSION;

static NSString *component;
static NSMutableDictionary<NSString *, NSNumber *> *tokens;
static uint64_t previous[11];
static NSUInteger cursor;
static NSString *Key(NSString *source, NSString *slot) {
    return [NSString stringWithFormat:@"com.chou.gmaphud.debug.v1.%@.%@",source,slot];
}
static BOOL Write(NSString *key,uint64_t state) {
    if (!tokens) tokens=[NSMutableDictionary new];
    NSNumber *saved=tokens[key]; int token=-1;
    if (saved) token=saved.intValue;
    else {
        if (notify_register_check(key.UTF8String,&token)!=NOTIFY_STATUS_OK) return NO;
        tokens[key]=@(token);
    }
    return notify_set_state(token,state)==NOTIFY_STATUS_OK;
}
static uint64_t Read(NSString *key) {
    int token=-1; uint64_t state=0;
    if (notify_register_check(key.UTF8String,&token)!=NOTIFY_STATUS_OK) return 0;
    notify_get_state(token,&state); notify_cancel(token); return state;
}
uint64_t GVMEncodeDiagnostic(NSUInteger event,NSUInteger detail,NSTimeInterval uptime) {
    if (event<1 || event>10 || detail>0xffffff || !isfinite(uptime) || uptime<1 || uptime>=UINT32_MAX) return 0;
    return ((uint64_t)floor(uptime)<<32) | ((uint64_t)detail<<8) | event;
}
NSString *GVMDescribeDiagnostic(uint64_t state,NSTimeInterval now) {
    NSUInteger event=state&255, detail=(state>>8)&0xffffff;
    NSTimeInterval age=now-(state>>32);
    if (!state || event<1 || event>10 || !isfinite(now) || age<0) return @"Chưa có dữ liệu trong phiên này";
    NSString *message;
    switch (event) {
        case GVMDiagnosticLoaded: message=[NSString stringWithFormat:@"Module %@ đã nạp; app %lu.%lu.%lu",PackageVersion,(unsigned long)(detail>>16),(unsigned long)((detail>>8)&255),(unsigned long)(detail&255)]; break;
        case GVMDiagnosticHook: message=detail==1 ? @"Hook sẵn sàng" : detail==2 ? @"Chưa tìm thấy lớp/hàm cần thiết" : detail==3 ? @"Cấu trúc hàm không tương thích" : @"Không đăng ký được kênh dữ liệu"; break;
        case GVMDiagnosticChannel: message=@"Đã bắt gặp kênh overlay VietMap"; break;
        case GVMDiagnosticPayload: message=detail==1 ? @"Nhận gói tốc độ đúng cấu trúc" : @"Gói tốc độ khác cấu trúc hỗ trợ"; break;
        case GVMDiagnosticSamples: message=[NSString stringWithFormat:@"Nguồn: tốc độ %@, giới hạn %@; app %@",detail&1 ? @"còn mới" : @"thiếu/hết hạn",detail&2 ? @"còn mới" : @"thiếu/hết hạn",detail&4 ? @"foreground" : @"background/inactive"]; break;
        case GVMDiagnosticCarPlay: message=[NSString stringWithFormat:@"Đã cập nhật view CarPlay: tốc độ %@, giới hạn %@, chế độ %@",detail&1 ? @"có" : @"thiếu",detail&2 ? @"có" : @"thiếu",detail&4 ? @"mẫu thử" : @"thật"]; break;
        case GVMDiagnosticRequest: message=@"Google Maps yêu cầu nguồn gửi dữ liệu"; break;
        case GVMDiagnosticResponse: message=[NSString stringWithFormat:@"Nguồn trả lời: tốc độ %@, giới hạn %@",detail&1 ? @"còn mới" : @"thiếu/hết hạn",detail&2 ? @"còn mới" : @"thiếu/hết hạn"]; break;
        case GVMDiagnosticShape: message=[NSString stringWithFormat:@"Overlay: speed %@, speedLimit %@, thay toàn bộ %@",detail&1 ? @"có" : @"không",detail&2 ? @"có" : @"không",detail&4 ? @"có" : @"không"]; break;
        default: message=@"Lỗi cập nhật hoặc truyền dữ liệu"; break;
    }
    return [NSString stringWithFormat:@"%.0f giây trước: %@",age,message];
}
void GVMDiagnosticsRecord(GVMDiagnosticEvent event,NSUInteger detail) {
    @synchronized(NSProcessInfo.processInfo) {
        if (!component || event<1 || event>10) return;
        NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
        uint64_t state=GVMEncodeDiagnostic(event,detail,now);
        if (!state) return;
        // Repeat snapshots at most once per ten seconds; state changes are immediate.
        if ((previous[event]&UINT32_MAX)==(state&UINT32_MAX) && now-(previous[event]>>32)<10) return;
        previous[event]=state;
        Write(Key(component,[NSString stringWithFormat:@"event%lu",(unsigned long)event]),state);
        Write(Key(component,[NSString stringWithFormat:@"recent%lu",(unsigned long)(cursor++%16)]),state);
    }
}
void GVMDiagnosticsStart(NSString *source) {
    @synchronized(NSProcessInfo.processInfo) {
        if (component) return;
        component=[source copy];
        for (NSUInteger i=1;i<=10;i++) Write(Key(component,[NSString stringWithFormat:@"event%lu",(unsigned long)i]),0);
        for (NSUInteger i=0;i<16;i++) Write(Key(component,[NSString stringWithFormat:@"recent%lu",(unsigned long)i]),0);
        NSArray *parts=[[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] componentsSeparatedByString:@"."];
        NSUInteger version=0;
        for (NSUInteger i=0;i<3;i++) version=(version<<8) | (i<parts.count ? MIN(255,MAX(0,[parts[i] integerValue])) : 0);
        GVMDiagnosticsRecord(GVMDiagnosticLoaded,version);
    }
}
NSString *GVMDiagnosticsReport(void) {
    char model[128]={0}; size_t size=sizeof(model);
    sysctlbyname("hw.machine",model,&size,NULL,0);
    NSMutableString *report=[NSMutableString stringWithFormat:@"GMapHUD %@ — Chẩn đoán\nNgày xuất: %@\nThiết bị: %s\nOS: %@\nRootless /var/jb: %@\n\nKhông chứa tọa độ, tuyến đường, tài khoản hoặc số sê-ri.\nĐây là các mốc chẩn đoán gần nhất, không phải toàn bộ log ứng dụng.\nKhông có dữ liệu không đồng nghĩa tweak bị tắt. Mở lại cả hai app sau khi cài.\n",PackageVersion,NSDate.date,model,NSProcessInfo.processInfo.operatingSystemVersionString,[[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? @"có" : @"không"];
    [report appendFormat:@"\nPhiên bản đang cài:\nGoogle Maps [com.google.Maps]: %@\nNguồn cảnh báo VietMap Live [vn.vietmap.live]: %@\nNguồn cảnh báo Waze [com.waze.iphone]: %@\nNguồn cảnh báo GOFA [com.lumi.GOFA]: %@\n",
        GVMDiagnosticsAppVersion(@"com.google.Maps"),GVMDiagnosticsAppVersion(@"vn.vietmap.live"),
        GVMDiagnosticsAppVersion(@"com.waze.iphone"),GVMDiagnosticsAppVersion(@"com.lumi.GOFA")];
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    for (NSString *source in @[@"vietmap",@"googlemaps"]) {
        [report appendFormat:@"\n=== %@ ===\n",source];
        NSArray *labels=@[@"Module",@"Hook",@"Kênh overlay",@"Gói tốc độ",@"Dữ liệu nguồn",@"View CarPlay",@"Lỗi",@"Yêu cầu nguồn",@"Phản hồi nguồn",@"Trường overlay"];
        for (NSUInteger i=1;i<=10;i++) {
            if (([source isEqual:@"googlemaps"] && i>=3 && i<=5) || ([source isEqual:@"vietmap"] && i==6)) continue;
            [report appendFormat:@"%@: %@\n",labels[i-1],GVMDescribeDiagnostic(Read(Key(source,[NSString stringWithFormat:@"event%lu",(unsigned long)i])),now)];
        }
        NSMutableArray *recent=[NSMutableArray new];
        for (NSUInteger i=0;i<16;i++) {
            uint64_t value=Read(Key(source,[NSString stringWithFormat:@"recent%lu",(unsigned long)i]));
            if (value && (value>>32)<=now) [recent addObject:@(value)];
        }
        [recent sortUsingSelector:@selector(compare:)];
        [report appendString:@"Các mốc gần nhất:\n"];
        for (NSNumber *value in recent) [report appendFormat:@"- %@\n",GVMDescribeDiagnostic(value.unsignedLongLongValue,now)];
    }
    [report appendString:@"\nThông tin bổ sung: phiên bản jailbreak, tweak chia màn hình và các bước gây lỗi (người gửi tự bổ sung).\n"];
    return report;
}

@interface NSObject (GVMApplicationMetadata)
+ (id)applicationProxyForIdentifier:(NSString *)identifier;
- (NSURL *)bundleURL;
- (id)shortVersionString;
- (id)bundleVersion;
@end
NSString *GVMDiagnosticsAppVersion(NSString *bundleID) {
    Class proxyClass=NSClassFromString(@"LSApplicationProxy");
    if (![proxyClass respondsToSelector:@selector(applicationProxyForIdentifier:)]) return @"Không đọc được thông tin app đang cài";
    @try {
        id proxy=[proxyClass applicationProxyForIdentifier:bundleID];
        if (!proxy) return @"Không tìm thấy app";
        NSDictionary *info=nil;
        if ([proxy respondsToSelector:@selector(bundleURL)]) {
            NSURL *url=[proxy bundleURL];
            if ([url isKindOfClass:NSURL.class]) info=[NSDictionary dictionaryWithContentsOfURL:[url URLByAppendingPathComponent:@"Info.plist"]];
        }
        id version=info[@"CFBundleShortVersionString"];
        id build=info[@"CFBundleVersion"];
        if (!version && [proxy respondsToSelector:@selector(shortVersionString)]) version=[proxy shortVersionString];
        if (!build && [proxy respondsToSelector:@selector(bundleVersion)]) build=[proxy bundleVersion];
        if (![version isKindOfClass:NSString.class]) return @"Không đọc được phiên bản";
        return [build isKindOfClass:NSString.class] ? [NSString stringWithFormat:@"%@ (build %@)",version,build] : version;
    } @catch (__unused NSException *exception) { return @"Không đọc được thông tin app"; }
}

NSArray<NSURL *> *GVMDiagnosticsFindCrashes(NSArray<NSString *> *directories,NSDate *now,NSString **status) {
    NSFileManager *manager=NSFileManager.defaultManager;
    NSMutableArray<NSDictionary *> *candidates=[NSMutableArray new];
    BOOL readable=NO;
    for (NSString *directory in directories) {
        NSError *error=nil;
        NSArray *names=[manager contentsOfDirectoryAtPath:directory error:&error];
        if (!names || error) continue;
        readable=YES;
        for (NSString *name in names) {
            NSString *lower=name.lowercaseString;
            if (![@[@"ips",@"crash"] containsObject:lower.pathExtension]) continue;
            BOOL direct=[lower hasPrefix:@"googlemaps-"] || [lower hasPrefix:@"googlemaps_"] ||
                [lower hasPrefix:@"vietmap"];
            BOOL conditional=[lower hasPrefix:@"runner-"] || [lower hasPrefix:@"runner_"] ||
                [lower hasPrefix:@"springboard-"] || [lower hasPrefix:@"springboard_"] ||
                [lower hasPrefix:@"preferences-"] || [lower hasPrefix:@"preferences_"];
            if (!direct && !conditional) continue;
            NSString *path=[directory stringByAppendingPathComponent:name];
            NSDictionary *attributes=[manager attributesOfItemAtPath:path error:nil];
            NSDate *date=attributes[NSFileModificationDate];
            if (![attributes[NSFileType] isEqual:NSFileTypeRegular] || [attributes[NSFileSize] unsignedLongLongValue]>2*1024*1024 || !date || [now timeIntervalSinceDate:date]>7*24*3600 || [now timeIntervalSinceDate:date]<0) continue;
            [candidates addObject:@{@"url":[NSURL fileURLWithPath:path],@"date":date,@"direct":@(direct)}];
        }
    }
    [candidates sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) { return [b[@"date"] compare:a[@"date"]]; }];
    NSMutableArray *files=[NSMutableArray new];
    NSMutableSet *seen=[NSMutableSet new];
    NSUInteger scanned=0;
    for (NSDictionary *candidate in candidates) {
        if (++scanned>30 || files.count>=3) break;
        NSURL *url=candidate[@"url"];
        NSData *data=[NSData dataWithContentsOfURL:url options:0 error:nil];
        if (!data || data.length>2*1024*1024) continue;
        if (![candidate[@"direct"] boolValue]) {
            NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (![text containsString:@"vn.vietmap.live"] && ![text containsString:@"com.google.Maps"] &&
                ![text containsString:@"GoogleMapsVietMap"] && ![text containsString:@"GMapHUDPrefs"] &&
                ![text containsString:@"VietMapGoogleMapsSource"] && ![text containsString:@"GMapHUDPlacementRelay"]) continue;
        }
        if ([seen containsObject:url.lastPathComponent]) continue;
        [seen addObject:url.lastPathComponent]; [files addObject:url];
    }
    if (status) *status=!readable ? @"Không đọc được thư mục crash trên thiết bị này; có thể xuất thủ công trong Dữ liệu phân tích của iOS." : files.count ? [NSString stringWithFormat:@"Có %lu crash liên quan trong 7 ngày gần nhất (tối đa 3 file, 2 MB/file).",(unsigned long)files.count] : @"Không tìm thấy crash liên quan có thể đọc trong 7 ngày gần nhất.";
    return files;
}
NSArray<NSURL *> *GVMDiagnosticsCrashFiles(NSString **status) {
    return GVMDiagnosticsFindCrashes(@[@"/var/mobile/Library/Logs/CrashReporter",@"/Library/Logs/CrashReporter"],NSDate.date,status);
}
