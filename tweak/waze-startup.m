#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#include <dlfcn.h>
#import <CoreLocation/CoreLocation.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif
#import "source-transport.h"
#import "background-policy.h"

// Trial startup diagnostics and a guarded, lease-owned navigation GPS initializer.
extern double GVMWazeLastGPSSample(void);
static void RecordStartup(NSString *event);
static BOOL navigationInitializing, navigationInitialized, navigationConfirmed;
static unsigned navigationAttempts;
static double navigationStarted, navigationNextRetry;
static __weak CLLocationManager *navigationOwnedManager;
static void (*nativeNavigationStop)(void);
BOOL GVMWazeOwnsNavigation(CLLocationManager *manager) { return manager && manager==navigationOwnedManager; }
void GVMWazeTransferNavigation(void) { navigationOwnedManager=nil; navigationInitialized=YES; }
BOOL GVMStopWazeNavigation(CLLocationManager *manager) {
    if (!GVMWazeOwnsNavigation(manager) || !nativeNavigationStop) return NO;
    navigationInitializing=YES;
    @try { nativeNavigationStop(); navigationInitialized=NO; navigationAttempts=0; navigationConfirmed=NO; }
    @finally { navigationInitializing=NO; }
    return YES;
}
BOOL GVMWazeNavigationInitializing(void) { return navigationInitializing; }
BOOL GVMInitializeWazeNavigation(CLLocationManager *authorizedManager) {
    if (!NSThread.isMainThread || navigationInitializing || UIApplication.sharedApplication.applicationState==UIApplicationStateActive ||
        ![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.waze.iphone"] ||
        ![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"5.25.0"]) return NO;
    double now=NSProcessInfo.processInfo.systemUptime;
    if (navigationInitialized) {
        if (!navigationOwnedManager) return NO;
        // A GPS sample received after the start confirms it; a held stationary speed does not.
        if (GVMWazeLastGPSSample()>=navigationStarted) navigationConfirmed=YES;
        if (!GVMBackgroundGPSRetryDue(now,navigationNextRetry,navigationAttempts,navigationConfirmed)) return NO;
        // Restart only the GPS acquired by this lease; never close the app or grant rights.
        navigationInitializing=YES;
        @try { nativeNavigationStop(); navigationInitialized=NO; }
        @finally { navigationInitializing=NO; }
        RecordStartup(@"navigation GPS retry after no fresh startup sample");
    }
    const uint8_t uuid[]={0x90,0x94,0x7e,0x86,0xbf,0xf2,0x34,0x34,0xa2,0x8b,0x97,0x9c,0x65,0xdb,0x88,0x46};
    const uint8_t entry[]={0xf4,0x4f,0xbe,0xa9,0xfd,0x7b,0x01,0xa9,0xfd,0x43,0x00,0x91,0xb3,0x1c,0x04,0xf0,0x68,0x9e,0x47,0xf9,0x28,0x01,0x00,0xb5,0xc8,0xfe,0x03,0xf0,0x00,0x05,0x44,0xf9,0x22,0x11,0x19,0x95,0x68,0x9e,0x47,0xf9,0x60,0x9e,0x07,0xf9,0x5b,0x11,0x19,0x95,0xa8,0x1c,0x04,0xf0,0x1f,0x61,0x3d,0x39,0xfd,0x7b,0x41,0xa9,0xf4,0x4f,0xc2,0xa8,0x01,0x00,0x00,0x14};
    for (uint32_t n=0;n<_dyld_image_count();n++) {
        const struct mach_header_64 *header=(const void *)_dyld_get_image_header(n);
        if (!header || header->magic!=MH_MAGIC_64) continue;
        const struct load_command *load=(const void *)(header+1);
        BOOL match=NO;
        for (uint32_t c=0;c<header->ncmds;c++) {
            if (load->cmd==LC_UUID && !memcmp(((const struct uuid_command *)load)->uuid,uuid,16)) match=YES;
            load=(const void *)((const uint8_t *)load+load->cmdsize);
        }
        if (!match) continue;
        intptr_t slide=_dyld_get_image_vmaddr_slide(n);
        void *function=(void *)(slide+0x1000a6ddc);
        if (memcmp(function,entry,sizeof(entry))) return NO;
        const uint8_t stopEntry[]={0xff,0xc3,0x00,0xd1,0xf4,0x4f,0x01,0xa9,0xfd,0x7b,0x02,0xa9,0xfd,0x83,0x00,0x91,0xa8,0x1c,0x04,0xf0,0x1f,0x61,0x3d,0x39,0x09,0x54,0x40,0x94,0xb3,0x1c,0x04,0xf0,0x1f,0x0c,0x00,0x71,0x8c,0x01,0x00,0x54,0x68,0x9a,0x47,0xf9,0xe1,0x8f,0x03,0xd0,0x21,0x34,0x23,0x91,0xe3,0x8f,0x03,0xf0,0x63,0xbc,0x12,0x91,0xe4,0x8f,0x03,0xf0,0x84,0xd4,0x12,0x91,0xe8,0x03,0x00,0xf9,0x60,0x00,0x80,0x52,0xa2,0x0f,0x80,0x52,0x95,0xd5,0x40,0x94,0x60,0x9a,0x47,0xf9,0x4f,0xe1,0x1a,0x95,0x60,0x9a,0x47,0xf9,0xfd,0x7b,0x42,0xa9,0xf4,0x4f,0x41,0xa9,0xff,0xc3,0x00,0x91,0x42,0xe1,0x1a,0x15};
        void *stopFunction=(void *)(slide+0x1000a6d6c);
        if (memcmp(stopFunction,stopEntry,sizeof(stopEntry))) return NO;
        // This measured native routine creates its singleton controller and starts GPS.
        // It is used by Waze's mobile foreground path; no scene activation is requested.
        id manager=(__bridge id)(*(void **)(slide+0x10843df30));
        id controller=(__bridge id)(*(void **)(slide+0x10843df38));
        if (controller && manager!=navigationOwnedManager) { navigationInitialized=YES; return NO; }
        if (manager && ![manager isKindOfClass:CLLocationManager.class]) return NO;
        CLAuthorizationStatus permission=authorizedManager.authorizationStatus;
        if ((permission!=kCLAuthorizationStatusAuthorizedAlways && permission!=kCLAuthorizationStatusAuthorizedWhenInUse) ||
            !CLLocationManager.locationServicesEnabled) return NO;
#if __has_feature(ptrauth_calls)
        function=ptrauth_sign_unauthenticated(function,ptrauth_key_function_pointer,0);
        stopFunction=ptrauth_sign_unauthenticated(stopFunction,ptrauth_key_function_pointer,0);
#endif
        nativeNavigationStop=(void (*)(void))stopFunction;
        navigationInitializing=YES;
        @try {
            ((void (*)(void))function)();
            navigationOwnedManager=(__bridge id)(*(void **)(slide+0x10843df30));
            navigationInitialized=YES;
            navigationStarted=now; navigationAttempts++;
            navigationNextRetry=now+2*GVMBackgroundRetryDelay(navigationAttempts);
        }
        @finally { navigationInitializing=NO; }
        return YES;
    }
    return NO;
}
static NSString *StartupFlag(NSString *name) {
    id delegate=UIApplication.sharedApplication.delegate;
    SEL selector=NSSelectorFromString(name);
    Method method=class_getInstanceMethod(object_getClass(delegate),selector);
    if (!method || strcmp(method_getTypeEncoding(method),"B16@0:8")) return @"unknown";
    return ((BOOL (*)(id,SEL))objc_msgSend)(delegate,selector) ? @"1" : @"0";
}
static void RecordStartup(NSString *event) {
    double now=NSProcessInfo.processInfo.systemUptime;
    NSDictionary *output=GVMReadSourceOutput(now);
    NSString *line=[NSString stringWithFormat:@"%.3f %@ app=%ld selected=%lu outputSource=%@ speedPresent=%d limitPresent=%d started=%@ dependencies=%@ window=%@ root=%@\n",
        now,event,(long)UIApplication.sharedApplication.applicationState,
        (unsigned long)GVMSelectedSourceID(),output[@"sourceID"] ?: @0,
        output[@"speed"]!=nil,output[@"speedLimit"]!=nil,StartupFlag(@"appStarted"),
        StartupFlag(@"appDependencyManagerIsInitialized"),StartupFlag(@"isWindowSet"),StartupFlag(@"isRootVCSet")];
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-waze-startup.log"];
    NSFileManager *fm=NSFileManager.defaultManager;
    if ([[fm attributesOfItemAtPath:path error:nil] fileSize]>32768) [fm removeItemAtPath:path error:nil];
    if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:path];
    @try { [file seekToEndOfFile]; [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; }
    @catch (__unused NSException *exception) {}
    @finally { [file closeFile]; }
}
static void ObserveStartupMethods(void) {
    Class cls=NSClassFromString(@"WazeApp");
    for (NSString *name in @[@"initDependencies",@"onStart",@"initWCDAndAppDependencyManager",
            @"initAppForOfflineLocationUpdates",@"windowSceneDidBecomeActive"]) {
        SEL selector=NSSelectorFromString(name);
        Method method=class_getInstanceMethod(cls,selector);
        if (!method || strcmp(method_getTypeEncoding(method),"v16@0:8")) continue;
        __block void (*original)(id,SEL);
        IMP wrapper=imp_implementationWithBlock(^(id self) {
            RecordStartup([@"enter " stringByAppendingString:name]);
            original(self,selector);
            RecordStartup([@"leave " stringByAppendingString:name]);
        });
        MSHookMessageEx(cls,selector,wrapper,(IMP *)&original);
    }
}
// Record the native caller chain once per controller creation, without location values.
typedef id (*NavigationInitializer)(id __attribute__((ns_consumed)),SEL) __attribute__((ns_returns_retained));
static NavigationInitializer originalNavigationInit;
static id NavigationInit(id self __attribute__((ns_consumed)),SEL cmd) __attribute__((ns_returns_retained));
static id NavigationInit(id self __attribute__((ns_consumed)),SEL cmd) {
    id result=originalNavigationInit(self,cmd);
    NSMutableArray *frames=[NSMutableArray new];
    for (NSNumber *address in NSThread.callStackReturnAddresses) {
        uintptr_t pc=address.unsignedLongLongValue;
        Dl_info info={0};
        if (!dladdr((void *)pc,&info) || !info.dli_fname || !strstr(info.dli_fname,"/Waze.app/")) continue;
        [frames addObject:@{@"offset":@(pc-(uintptr_t)info.dli_fbase),
            @"symbol":info.dli_sname ? @(info.dli_sname) : @"unknown",
            @"bytes":[[NSData dataWithBytes:(void *)(pc-2048) length:(frames.count==0 ? 4096 : 2048)] base64EncodedStringWithOptions:0]}];
        if (frames.count>=12) break;
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:frames options:NSJSONWritingSortedKeys error:nil];
    [data writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-waze-navigation-init.json"] atomically:YES];
    RecordStartup(@"navigation-controller-created");
    return result;
}
static BOOL (*originalLocationFilter)(id,SEL,SEL);
static BOOL LocationFilter(id self,SEL cmd,SEL callback) {
    BOOL allowed=originalLocationFilter(self,cmd,callback);
    if (callback==@selector(locationManager:didUpdateLocations:)) {
        static NSMutableDictionary *observations;
        if (!observations) observations=[NSMutableDictionary new];
        double now=NSProcessInfo.processInfo.systemUptime;
        NSInteger state=(UIApplication.sharedApplication.applicationState<<1)|allowed;
        Ivar originalDelegate=class_getInstanceVariable(object_getClass(self),"_originalDelegate");
        id receiver=originalDelegate ? object_getIvar(self,originalDelegate) : nil;
        NSString *key=receiver ? NSStringFromClass(object_getClass(receiver)) : @"nil";
        NSArray *prior=observations[key];
        if (!prior || state!=[prior[0] integerValue] || now-[prior[1] doubleValue]>=10) {
            observations[key]=@[@(state),@(now)];
            NSMutableArray *targets=[NSMutableArray new];
            unsigned count=0;
            Ivar *ivars=class_copyIvarList(object_getClass(self),&count);
            for (unsigned v=0;v<count;v++) {
                const char *name=ivar_getName(ivars[v]),*type=ivar_getTypeEncoding(ivars[v]);
                if (!name || (!strstr(name,"delegate") && !strstr(name,"Delegate")) || !type || type[0]!='@') continue;
                id target=object_getIvar(self,ivars[v]);
                [targets addObject:[NSString stringWithFormat:@"%s=%@",name,target ? NSStringFromClass(object_getClass(target)) : @"nil"]];
            }
            free(ivars);
            RecordStartup([NSString stringWithFormat:@"native-location-forward allowed=%d targets=%@",allowed,[targets componentsJoinedByString:@","]]);
        }
    }
    return allowed;
}
static NSArray *CodeReferences(const uint32_t *words, unsigned count, NSDictionary *references, void *imageBase) {
    NSMutableArray *refs=[NSMutableArray new];
    for (unsigned n=0;n+1<count;n++) {
        uint32_t a=words[n],b=words[n+1];
        if ((a&0x9f000000)!=0x90000000 || (b&0xffc00000)!=0xf9400000 ||
            (a&31)!=((b>>5)&31)) continue;
        int32_t immediate=(int32_t)((((a>>5)&0x7ffff)<<2)|((a>>29)&3));
        immediate=(int32_t)((uint32_t)immediate<<11)>>11;
        uintptr_t literal=(((uintptr_t)words+n*4)&~(uintptr_t)4095)+(int64_t)immediate*4096+(((b>>10)&4095)*8);
        Dl_info region={0};
        if (!dladdr((void *)literal,&region) || region.dli_fbase!=imageBase) continue;
        NSString *known=references[@(*(uintptr_t *)literal)];
        if (known) [refs addObject:@{@"offset":@(n*4),@"reference":known}];
    }
    return refs;
}
static void CaptureStartupMetadata(void) {
    NSMutableString *report=[NSMutableString stringWithFormat:@"Waze %@ startup ABI inventory\n",
        [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
    Class delegateClass=object_getClass(UIApplication.sharedApplication.delegate);
    unsigned count=0;
    Class *classes=objc_copyClassList(&count);
    NSMutableDictionary *references=[NSMutableDictionary new];
    for (unsigned i=0;i<count;i++) {
        // Any image in the process may register a class whose name does not convert (nil); those
        // are skipped rather than ending Waze, as five launches did on 17/10.
        NSString *className=NSStringFromClass(classes[i]);
        if (className) references[@((uintptr_t)classes[i])]=[@"class " stringByAppendingString:className];
        const char *image=class_getImageName(classes[i]);
        if (!image || !strstr(image,"/Waze.app/")) continue;
        for (unsigned meta=0;meta<2;meta++) {
            unsigned n=0;
            Method *methods=class_copyMethodList(meta ? object_getClass(classes[i]) : classes[i],&n);
            for (unsigned m=0;m<n;m++) {
                SEL selector=method_getName(methods[m]);
                uintptr_t reference=0;
                _Static_assert(sizeof(reference)==sizeof(selector),"selector reference width");
                memcpy(&reference,&selector,sizeof(reference));
                NSString *selectorName=NSStringFromSelector(selector);
                if (selectorName) references[@(reference)]=[@"selector " stringByAppendingString:selectorName];
            }
            free(methods);
        }
    }
    unsigned included=0;
    for (unsigned i=0;i<count && included<64;i++) {
        Class cls=classes[i];
        const char *image=class_getImageName(cls);
        if (!image || !strstr(image,"/Waze.app/")) continue;
        NSString *name=NSStringFromClass(cls), *lower=name.lowercaseString;
        if (cls!=delegateClass && ![lower containsString:@"locationmanager"] &&
            ![lower containsString:@"locationcontroller"] &&
            ![lower containsString:@"appdelegate"] && ![lower containsString:@"scenedelegate"] &&
            ![lower containsString:@"nativeengine"] && ![lower containsString:@"nativemanager"] &&
            ![lower containsString:@"startupprocess"] && ![lower containsString:@"applicationmanager"]) continue;
        included++;
        [report appendFormat:@"\nCLASS %@ delegate=%d\n",name,cls==delegateClass];
        unsigned ivarCount=0;
        Ivar *ivars=class_copyIvarList(cls,&ivarCount);
        for (unsigned v=0;v<ivarCount;v++)
            [report appendFormat:@"IVAR %s %s\n",ivar_getName(ivars[v]),ivar_getTypeEncoding(ivars[v])];
        free(ivars);
        for (unsigned meta=0;meta<2;meta++) {
            unsigned methodsCount=0;
            Method *methods=class_copyMethodList(meta ? object_getClass(cls) : cls,&methodsCount);
            for (unsigned m=0;m<methodsCount && m<256;m++)
                [report appendFormat:@"%c %s %s\n",meta ? '+' : '-',
                    sel_getName(method_getName(methods[m])),method_getTypeEncoding(methods[m])];
            free(methods);
        }
        if (report.length>131072) break;
    }
    free(classes);
    [report writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-waze-startup-abi.txt"]
        atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // Inspect only verified app lifecycle code and direct branch symbol names.
    // No object memory, GPS or account values are read.
    NSMutableArray *code=[NSMutableArray new];
    for (NSString *name in @[@"applicationWillEnterForeground:",@"applicationDidBecomeActive:",@"applicationDidEnterBackground:"]) {
        Method method=class_getInstanceMethod(NSClassFromString(@"WazeApp"),NSSelectorFromString(name));
        if (!method || strcmp(method_getTypeEncoding(method),"v24@0:8@16")) continue;
        void *pointer=(void *)method_getImplementation(method);
#if __has_feature(ptrauth_calls)
        pointer=ptrauth_strip(pointer,ptrauth_key_function_pointer);
#endif
        Dl_info info={0};
        if (!dladdr(pointer,&info) || !info.dli_fname || !strstr(info.dli_fname,"/Waze.app/")) continue;
        const uint32_t *words=pointer;
        NSMutableArray *branches=[NSMutableArray new];
        for (unsigned i=0;i<128;i++) {
            uint32_t instruction=words[i];
            if ((instruction&0xfc000000)!=0x94000000) continue;
            int32_t delta=((int32_t)(instruction<<6)>>4);
            void *target=(char *)pointer+i*4+delta;
            Dl_info branch={0};
            dladdr(target,&branch);
            NSArray *refs=branch.dli_fname && strstr(branch.dli_fname,"/Waze.app/") ?
                CodeReferences(target,64,references,info.dli_fbase) : @[];
            [branches addObject:@{@"offset":@(i*4),@"target":@((uintptr_t)target),
                @"symbol":branch.dli_sname ? @(branch.dli_sname) : @"unknown",
                @"references":refs,
                @"bytes":branch.dli_fname && strstr(branch.dli_fname,"/Waze.app/") ?
                    [[NSData dataWithBytes:target length:256] base64EncodedStringWithOptions:0] : @""}];
        }
        [code addObject:@{@"method":name,@"address":@((uintptr_t)pointer),@"references":CodeReferences(pointer,128,references,info.dli_fbase),
            @"bytes":[[NSData dataWithBytes:pointer length:512] base64EncodedStringWithOptions:0],@"branches":branches}];
    }
    NSData *codeData=[NSJSONSerialization dataWithJSONObject:code options:NSJSONWritingSortedKeys error:nil];
    [codeData writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-waze-lifecycle-code.json"] atomically:YES];
}
__attribute__((constructor)) static void ObserveWazeStartup(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.waze.iphone"] ||
        ![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"5.25.0"]) return;
    ObserveStartupMethods();
    Class navigation=NSClassFromString(@"LocationController");
    Method initializer=class_getInstanceMethod(navigation,@selector(init));
    if (initializer && !strcmp(method_getTypeEncoding(initializer),"@16@0:8"))
        MSHookMessageEx(navigation,@selector(init),(IMP)NavigationInit,(IMP *)&originalNavigationInit);
    Class location=NSClassFromString(@"WazeLocationManager");
    SEL filter=NSSelectorFromString(@"shouldTriggerDelegateWithSelector:");
    Method method=class_getInstanceMethod(location,filter);
    if (method && !strcmp(method_getTypeEncoding(method),"B24@0:8:16"))
        MSHookMessageEx(location,filter,(IMP)LocationFilter,(IMP *)&originalLocationFilter);
    dispatch_async(dispatch_get_main_queue(), ^{
        RecordStartup(@"startup-observer-loaded");
        CaptureStartupMetadata();
        for (NSString *name in @[UIApplicationDidFinishLaunchingNotification,UIApplicationWillEnterForegroundNotification,
                UIApplicationDidBecomeActiveNotification,UIApplicationWillResignActiveNotification,UIApplicationDidEnterBackgroundNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification *notification) {
                    RecordStartup(name);
                    if ([name isEqual:UIApplicationDidFinishLaunchingNotification]) CaptureStartupMetadata();
                }];
        }
    });
}
