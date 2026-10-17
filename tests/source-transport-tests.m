#import "source-transport.h"
#import <CoreFoundation/CoreFoundation.h>
#include <notify.h>
#include <sys/wait.h>
#include <unistd.h>
#include <spawn.h>
extern char **environ;

#ifndef GVM_OUTPUT_NAMESPACE
#error Transport tests require a private notification and preferences namespace.
#endif
static void Require(BOOL condition,NSString *name) {
    if (!condition) { fprintf(stderr,"FAIL: %s\n",name.UTF8String); exit(1); }
}
static NSDictionary *Output(NSUInteger sourceID,double now) {
    return GVMSourceOutput(sourceID,@{@"speed":@{@"value":@42,@"receivedAt":@(now)},@"speedLimit":@{@"value":@50,@"receivedAt":@(now)}},@[],now);
}
int main(int argc,char **argv) { @autoreleasepool {
    double now=NSProcessInfo.processInfo.systemUptime;
    if (argc==2) {
        NSDictionary *output=GVMReadSourceOutput(now);
        Require([output[@"sourceID"] isEqual:@1] && [output[@"speed"][@"value"] isEqual:@42] && [output[@"speedLimit"][@"value"] isEqual:@50],@"independent consumer reads the complete selected frame");
        return 0;
    }
    Require(GVMSelectedSourceID()==1 && !GVMReadSourceOutput(now),@"initial source is VietMap, no invented data");
    GVMRestoreOutputSelection();
    int changed=-1, fired=0;
    Require(notify_register_check(GVMOutputChangedName(1).UTF8String,&changed)==NOTIFY_STATUS_OK,@"change notification registers");
    notify_check(changed,&fired); fired=0;   // the first check after registering always reports 1
    Require(GVMPublishSourceOutput(Output(1,now),now,NO),@"selected source publishes");
    // notifyd delivers asynchronously; give it a moment.
    for (int i=0;i<100 && !fired;i++) { usleep(10000); notify_check(changed,&fired); }
    Require(fired==1,@"a committed frame posts its change notification");
    Require(GVMPublishSourceOutput(Output(1,now),now,NO),@"an unchanged frame is accepted");
    usleep(200000); notify_check(changed,&fired);
    Require(fired==0,@"an unchanged frame posts nothing");
    Require([GVMReadSourceOutput(now)[@"speedLimit"][@"value"] isEqual:@50],@"Darwin frame read");
    Require(!GVMSelectOutputSource(0) && !GVMSelectOutputSource(8),@"invalid selection refused");
    for (NSNumber *source in @[@4,@5,@6,@7]) {
        NSUInteger sourceID=source.unsignedIntegerValue;
        Require(!GVMSourceEnabled(sourceID) && !GVMSelectOutputSource(sourceID) && !GVMOutputRequestName(sourceID) && !GVMPublishSourceOutput(Output(sourceID,now),now,YES),@"upcoming source rejected by all write/request boundaries");
        Require(GVMSelectedSourceID()==1 && [GVMReadSourceOutput(now)[@"sourceID"] isEqual:@1],@"refusal preserves current VietMap frame");
    }
    Require(GVMSourceEnabled(2) && GVMSelectOutputSource(2) && !GVMReadSourceOutput(now),@"Waze selection clears old source frame");
    Require(!GVMPublishSourceOutput(Output(1,now),now,YES),@"unselected VietMap cannot publish into Waze session");
    Require(GVMPublishSourceOutput(Output(2,now),now,YES) && [GVMReadSourceOutput(now)[@"sourceID"] isEqual:@2],@"selected Waze uses common output");
    CFPreferencesSetAppValue(CFSTR("sourceID"),(__bridge CFNumberRef)@2,CFSTR(GVM_OUTPUT_NAMESPACE));
    CFPreferencesAppSynchronize(CFSTR(GVM_OUTPUT_NAMESPACE)); GVMRestoreOutputSelection();
    Require(GVMSelectedSourceID()==2,@"enabled Waze selection survives restoration");
    Require(GVMSelectOutputSource(1) && !GVMReadSourceOutput(now),@"return requires a new frame, cannot replay old source");
    Require(GVMPublishSourceOutput(Output(1,now),now,NO),@"same values publish in new epoch");
    Require(!GVMReadSourceOutput(now+5)[@"speed"],@"expiry checked by reader without publisher");
    Require(GVMPublishSourceOutput(Output(1,now),now+5,YES) && !GVMReadSourceOutput(now+5)[@"speedLimit"],@"forced reply cannot revive expired values");
    Require(GVMPublishSourceOutput(GVMSourceOutput(1,nil,@[],now),now,YES) && !GVMReadSourceOutput(now)[@"speed"],@"explicit empty output clears");
    NSDictionary *lanes=@{@"distance":@84,@"items":@[@{@"code":@1,@"enabled":@YES},@{@"code":@5,@"enabled":@NO}],@"receivedAt":@(now)};
    Require(GVMPublishSourceOutput(GVMSourceOutput(1,@{@"lanes":lanes},@[],now),now,YES) &&
        [GVMReadSourceOutput(now)[@"lanes"][@"items"] isEqual:lanes[@"items"]] && [GVMReadSourceOutput(now)[@"lanes"][@"distance"] isEqual:@84],@"lanes travel in the committed frame");
    Require(GVMPublishSourceOutput(GVMSourceOutput(1,nil,@[],now),now,YES) && !GVMReadSourceOutput(now)[@"lanes"],@"a frame without lanes clears them");

    NSString *commit=[@GVM_OUTPUT_NAMESPACE stringByAppendingString:@".output.v1.1.commit"];
    int token=-1; uint64_t header=0;
    Require(notify_register_check(commit.UTF8String,&token)==NOTIFY_STATUS_OK,@"inspect real channel");
    Require(notify_get_state(token,&header)==NOTIFY_STATUS_OK && notify_set_state(token,((((header>>8)+1)|1)<<8)|1)==NOTIFY_STATUS_OK,@"interrupt write");
    Require(!GVMReadSourceOutput(now),@"real incomplete frame unavailable");
    Require(GVMPublishSourceOutput(Output(1,now),now,NO) && GVMReadSourceOutput(now)[@"speed"],@"publisher recovers odd frame");
    Require(GVMSourceEnabled(3) && GVMSelectOutputSource(3) && !GVMReadSourceOutput(now),@"GOFA selection invalidates the previous epoch");
    Require(!GVMPublishSourceOutput(Output(2,now),now,YES),@"unselected Waze cannot publish into GOFA session");
    Require(GVMPublishSourceOutput(Output(3,now),now,YES) && [GVMReadSourceOutput(now)[@"sourceID"] isEqual:@3],@"GOFA uses the common output exclusively");
    CFPreferencesSetAppValue(CFSTR("sourceID"),(__bridge CFNumberRef)@3,CFSTR(GVM_OUTPUT_NAMESPACE));
    CFPreferencesAppSynchronize(CFSTR(GVM_OUTPUT_NAMESPACE)); GVMRestoreOutputSelection();
    Require(GVMSelectedSourceID()==3,@"saved GOFA survives restoration");
    // A fallback is live but not saved, observers hear it, and restoring brings the saved choice back.
    dispatch_semaphore_t selectionSignal=dispatch_semaphore_create(0);
    GVMObserveSelection(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{ dispatch_semaphore_signal(selectionSignal); });
    Require(GVMSelectOutputSourceForNow(2) && GVMSelectedSourceID()==2,@"fallback selection is live");
    Require(dispatch_semaphore_wait(selectionSignal,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0,@"selection observers hear a fallback");
    CFPreferencesAppSynchronize(CFSTR(GVM_OUTPUT_NAMESPACE));
    Require([CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("sourceID"),CFSTR(GVM_OUTPUT_NAMESPACE))) isEqual:@3],@"fallback selection is not saved");
    GVMRestoreOutputSelection();
    Require(GVMSelectedSourceID()==3,@"restoring brings the saved choice back");
    Require(GVMSelectOutputSource(1) && !GVMReadSourceOutput(now),@"leaving GOFA requires a new VietMap frame");
    Require(GVMPublishSourceOutput(Output(1,now),now,YES),@"publish after GOFA isolation test");
    // Independent executable has separate globals/tokens, exercising actual IPC.
    pid_t child=0;
    char *arguments[]={argv[0],"--read",NULL};
    Require(posix_spawn(&child,argv[0],NULL,NULL,arguments,environ)==0,@"start independent consumer");
    int status=0; Require(child>0 && waitpid(child,&status,0)==child && WIFEXITED(status) && WEXITSTATUS(status)==0,@"committed state visible across process boundary");

    __block NSUInteger calls=0;
    dispatch_semaphore_t semaphore=dispatch_semaphore_create(0);
    int requestToken=-1;
    Require(notify_register_dispatch(GVMOutputRequestName(1).UTF8String,&requestToken,dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^(__unused int t) { calls++; dispatch_semaphore_signal(semaphore); })==NOTIFY_STATUS_OK,@"source request receiver");
    Require(GVMRequestSelectedSource() && dispatch_semaphore_wait(semaphore,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0 && calls==1,@"selected source receives refresh request");
    Require(GVMSelectOutputSource(3) && GVMRequestSelectedSource(),@"request switches exclusively to GOFA");
    Require(dispatch_semaphore_wait(semaphore,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC))!=0,@"unselected VietMap receives no GOFA request");
    notify_cancel(requestToken); notify_cancel(token);
    CFPreferencesSetAppValue(CFSTR("sourceID"),NULL,CFSTR(GVM_OUTPUT_NAMESPACE));
    CFPreferencesAppSynchronize(CFSTR(GVM_OUTPUT_NAMESPACE));
    puts("source-transport tests passed");
} return 0; }
