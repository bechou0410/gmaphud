#import <Foundation/Foundation.h>
#import "diagnostics.h"
#include <assert.h>
#include <math.h>
int main(int argc, char **argv) { @autoreleasepool {
    assert(argc==2);
    NSString *version=@(argv[1]);
    NSString *loaded=[NSString stringWithFormat:@"Module %@ đã nạp",version];
    NSString *header=[NSString stringWithFormat:@"GMapHUD %@ — Chẩn đoán\n",version];
    assert(!GVMEncodeDiagnostic(0,1,100));
    assert(!GVMEncodeDiagnostic(11,1,100));
    assert(!GVMEncodeDiagnostic(1,0x1000000,100));
    assert(!GVMEncodeDiagnostic(1,0,NAN));
    assert(!GVMEncodeDiagnostic(1,0,-1));
    assert(!GVMEncodeDiagnostic(1,0,UINT32_MAX));
    uint64_t sample=GVMEncodeDiagnostic(GVMDiagnosticSamples,7,100);
    assert([GVMDescribeDiagnostic(sample,110) containsString:@"10 giây"]);
    assert([GVMDescribeDiagnostic(sample,110) containsString:@"foreground"]);
    assert([GVMDescribeDiagnostic(sample,99) containsString:@"Chưa có dữ liệu"]);
    assert([GVMDescribeDiagnostic(GVMEncodeDiagnostic(GVMDiagnosticSamples,0,100),110) containsString:@"thiếu/hết hạn"]);
    assert([GVMDescribeDiagnostic(GVMEncodeDiagnostic(GVMDiagnosticLoaded,(26<<16)|(40<<8)|3,100),110) containsString:@"26.40.3"]);
    assert([GVMDescribeDiagnostic(GVMEncodeDiagnostic(GVMDiagnosticLoaded,0,100),110) containsString:loaded]);
    assert([GVMDescribeDiagnostic(GVMEncodeDiagnostic(GVMDiagnosticCarPlay,4,100),110) containsString:@"mẫu thử"]);
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSFileManager *manager=NSFileManager.defaultManager;
    assert([manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]);
    NSDictionary *samples=@{@"GoogleMaps-new.ips":@"Google crash",@"Runner-new.ips":@"vn.vietmap.live",@"Preferences-new.ips":@"GMapHUDPrefs",@"Runner-unrelated.ips":@"com.other.app",@"GoogleMaps-old.ips":@"old",@"OtherApp.ips":@"unrelated"};
    for (NSString *name in samples) assert([samples[name] writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    NSDate *old=[NSDate dateWithTimeIntervalSinceNow:-8*24*3600];
    [manager setAttributes:@{NSFileModificationDate:old} ofItemAtPath:[directory stringByAppendingPathComponent:@"GoogleMaps-old.ips"] error:nil];
    NSString *status=nil;
    NSArray *crashes=GVMDiagnosticsFindCrashes(@[directory,directory],NSDate.date,&status);
    assert(crashes.count==3 && [status containsString:@"3 crash"]);
    for (NSURL *file in crashes) assert(![file.lastPathComponent containsString:@"unrelated"] && ![file.lastPathComponent containsString:@"old"]);
    assert(GVMDiagnosticsFindCrashes(@[[directory stringByAppendingPathComponent:@"missing"]],NSDate.date,&status).count==0);
    assert([status containsString:@"Không đọc được"]);
    [manager removeItemAtPath:directory error:nil];
    NSString *report=GVMDiagnosticsReport();
    assert([report hasPrefix:header]);
    assert([report containsString:@"com.google.Maps"] && [report containsString:@"vn.vietmap.live"] &&
        [report containsString:@"com.waze.iphone"] && [report containsString:@"com.lumi.GOFA"]);

    assert([report containsString:@"vietmap"] && [report containsString:@"googlemaps"]);
    puts("diagnostics encoding and report tests passed");
} return 0; }
