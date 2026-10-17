#import "source-transport.h"
#import <CoreFoundation/CoreFoundation.h>
#include <notify.h>
#include <string.h>

#ifndef GVM_OUTPUT_NAMESPACE
#define GVM_OUTPUT_NAMESPACE "com.chou.gmaphud"
#endif
static NSString *Prefix(void) { return @GVM_OUTPUT_NAMESPACE; }

// Commit and selection, then the payload words in order.
enum { GVMOutputSlotCount=2+GVMOutputWordCount };
@interface GVMOutputEndpoint : NSObject {
@public
    int tokens[GVMOutputSlotCount];
    GVMOutputWords previous;
    uint64_t previousSelection;
    uint64_t previousCommit;
    BOOL published;
}
- (instancetype)initWithSourceID:(NSUInteger)sourceID;
@end
@implementation GVMOutputEndpoint
- (instancetype)initWithSourceID:(NSUInteger)sourceID {
    if (!(self=[super init])) return nil;
    for (NSUInteger i=0;i<GVMOutputSlotCount;i++) tokens[i]=-1;
    NSArray *slots=@[@"commit",@"selection",@"speed",@"limit",@"alert.first",@"alert.first.value",@"alert.second",@"alert.second.value",
        @"lanes",@"lanes.first",@"lanes.second"];
    for (NSUInteger i=0;i<slots.count;i++) {
        NSString *name=[Prefix() stringByAppendingFormat:@".output.v1.%lu.%@",(unsigned long)sourceID,slots[i]];
        if (notify_register_check(name.UTF8String,&tokens[i])!=NOTIFY_STATUS_OK) return nil;
    }
    return self;
}
- (void)dealloc { for (NSUInteger i=0;i<GVMOutputSlotCount;i++) if (tokens[i]>=0) notify_cancel(tokens[i]); }
@end

static int selectionToken=-1;
static NSMutableDictionary<NSNumber *,GVMOutputEndpoint *> *endpoints;
static NSMutableDictionary<NSNumber *,NSNumber *> *requestTokens;
static BOOL Read(int token,uint64_t *state) {
    *state=0;
    return token>=0 && notify_get_state(token,state)==NOTIFY_STATUS_OK;
}
static BOOL Selection(uint64_t *state) {
    if (selectionToken<0 && notify_register_check([Prefix() stringByAppendingString:@".source.selection"].UTF8String,&selectionToken)!=NOTIFY_STATUS_OK) return NO;
    return Read(selectionToken,state);
}
BOOL GVMSourceEnabled(NSUInteger sourceID) {
    return sourceID==GVMSourceVietMap || sourceID==GVMSourceWaze || sourceID==GVMSourceGofa;
}
static GVMOutputEndpoint *Endpoint(NSUInteger sourceID) {
    if (!GVMSourceIDValid(sourceID)) return nil;
    if (!endpoints) endpoints=[NSMutableDictionary new];
    if (!endpoints[@(sourceID)]) endpoints[@(sourceID)]=[[GVMOutputEndpoint alloc] initWithSourceID:sourceID];
    return endpoints[@(sourceID)];
}
NSUInteger GVMSelectedSourceID(void) {
    @synchronized(NSProcessInfo.processInfo) {
        uint64_t selected=0;
        return Selection(&selected) ? GVMSourceIDForSelection(selected) : 0;
    }
}
static BOOL Select(NSUInteger sourceID,BOOL save) {
    if (!GVMSourceEnabled(sourceID)) return NO;
    @synchronized(NSProcessInfo.processInfo) {
        uint64_t selected=0;
        if (!Selection(&selected) || (selected>>3)==(UINT64_MAX>>3)) return NO;
        if (save) {
            CFPreferencesSetAppValue(CFSTR("sourceID"),(__bridge CFNumberRef)@(sourceID),CFSTR(GVM_OUTPUT_NAMESPACE));
            if (!CFPreferencesAppSynchronize(CFSTR(GVM_OUTPUT_NAMESPACE))) return NO;
        }
        // Changing selection creates an epoch: even switching back needs a new frame.
        uint64_t next=(((selected>>3)+1)<<3)|sourceID;
        if (notify_set_state(selectionToken,next)!=NOTIFY_STATUS_OK) return NO;
        notify_post([Prefix() stringByAppendingString:@".source.selection"].UTF8String);
        return YES;
    }
}
BOOL GVMSelectOutputSource(NSUInteger sourceID) { return Select(sourceID,YES); }
BOOL GVMSelectOutputSourceForNow(NSUInteger sourceID) { return Select(sourceID,NO); }
void GVMRestoreOutputSelection(void) {
    @synchronized(NSProcessInfo.processInfo) {
        CFPreferencesAppSynchronize(CFSTR(GVM_OUTPUT_NAMESPACE));
        id saved=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("sourceID"),CFSTR(GVM_OUTPUT_NAMESPACE)));
        NSUInteger sourceID=GVMSourceVietMap;
        if ([saved isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)saved)!=CFBooleanGetTypeID() &&
            [saved doubleValue]==[saved unsignedIntegerValue] && GVMSourceIDValid([saved unsignedIntegerValue])) sourceID=[saved unsignedIntegerValue];
        BOOL unavailable=!GVMSourceEnabled(sourceID);
        if (unavailable) sourceID=GVMSourceVietMap;
        uint64_t selected=0;
        if (Selection(&selected) && (unavailable || !selected || GVMSourceIDForSelection(selected)!=sourceID)) GVMSelectOutputSource(sourceID);
    }
}
BOOL GVMPublishSourceOutput(NSDictionary *output,NSTimeInterval now,BOOL force) {
    NSDictionary *normalized=GVMNormalizeSourceOutput(output,now);
    if (!normalized) return NO;
    NSUInteger sourceID=[normalized[@"sourceID"] unsignedIntegerValue];
    if (!GVMSourceEnabled(sourceID)) return NO;
    GVMOutputWords words;
    if (!GVMEncodeSourceOutput(normalized,now,&words)) return NO;
    @synchronized(NSProcessInfo.processInfo) {
        uint64_t selected=0, header=0;
        if (!Selection(&selected) || GVMSourceIDForSelection(selected)!=sourceID) return NO;
        GVMOutputEndpoint *endpoint=Endpoint(sourceID);
        if (!endpoint || !Read(endpoint->tokens[0],&header)) return NO;
        if (!force && endpoint->published && header==endpoint->previousCommit && selected==endpoint->previousSelection &&
            !memcmp(&words,&endpoint->previous,sizeof(words))) return YES;
        uint64_t revision=(header>>8)+1;
        if (!(revision&1)) revision++;
        if (revision>=(UINT64_MAX>>8)) return NO;
        endpoint->published=NO;
        if (notify_set_state(endpoint->tokens[0],(revision<<8)|GVMOutputSchemaVersion)!=NOTIFY_STATUS_OK ||
            notify_set_state(endpoint->tokens[1],selected)!=NOTIFY_STATUS_OK) return NO;
        for (NSUInteger i=0;i<GVMOutputWordCount;i++)
            if (notify_set_state(endpoint->tokens[i+2],words.words[i])!=NOTIFY_STATUS_OK) return NO;
        // Keep an interrupted write odd; a reader must never accept a partial frame.
        if (notify_set_state(endpoint->tokens[0],((revision+1)<<8)|GVMOutputSchemaVersion)!=NOTIFY_STATUS_OK) return NO;
        endpoint->previous=words; endpoint->previousSelection=selected;
        endpoint->previousCommit=((revision+1)<<8)|GVMOutputSchemaVersion; endpoint->published=YES;
        notify_post(GVMOutputChangedName(sourceID).UTF8String);
        return YES;
    }
}
NSDictionary *GVMReadSourceOutput(NSTimeInterval now) {
    @synchronized(NSProcessInfo.processInfo) {
        uint64_t selected=0, afterSelection=0, before=0, after=0, frameSelection=0;
        if (!Selection(&selected)) return nil;
        NSUInteger sourceID=GVMSourceIDForSelection(selected);
        if (!GVMSourceEnabled(sourceID)) return nil;
        GVMOutputEndpoint *endpoint=Endpoint(sourceID);
        if (!endpoint || !Read(endpoint->tokens[0],&before) || !Read(endpoint->tokens[1],&frameSelection)) return nil;
        GVMOutputWords words={0};
        for (NSUInteger i=0;i<GVMOutputWordCount;i++) if (!Read(endpoint->tokens[i+2],&words.words[i])) return nil;
        if (!Read(endpoint->tokens[0],&after) || !Selection(&afterSelection) ||
            !GVMOutputFrameReadable(before,after,selected,afterSelection,frameSelection,sourceID)) return nil;
        return GVMDecodeSourceOutput(sourceID,words,now);
    }
}
NSString *GVMOutputChangedName(NSUInteger sourceID) {
    return [Prefix() stringByAppendingFormat:@".output.v1.%lu.changed",(unsigned long)sourceID];
}
void GVMObserveSelection(dispatch_queue_t queue,dispatch_block_t handler) {
    if (!queue || !handler) return;
    int token=-1;
    notify_register_dispatch([Prefix() stringByAppendingString:@".source.selection"].UTF8String,&token,queue,
        ^(__unused int fired) { handler(); });
}
void GVMObserveSourceOutput(dispatch_queue_t queue,dispatch_block_t handler) {
    if (!queue || !handler) return;
    int token=-1;
    for (NSUInteger sourceID=GVMSourceVietMap;sourceID<=GVMSourceGofa;sourceID++)
        notify_register_dispatch(GVMOutputChangedName(sourceID).UTF8String,&token,queue,^(__unused int fired) { handler(); });
    GVMObserveSelection(queue,handler);
}
NSString *GVMOutputRequestName(NSUInteger sourceID) {
    return GVMSourceEnabled(sourceID) ? [Prefix() stringByAppendingFormat:@".source.%lu.request",(unsigned long)sourceID] : nil;
}
BOOL GVMRequestSelectedSource(void) {
    @synchronized(NSProcessInfo.processInfo) {
        NSUInteger sourceID=GVMSelectedSourceID();
        NSString *name=GVMOutputRequestName(sourceID);
        if (!name) return NO;
        if (!requestTokens) requestTokens=[NSMutableDictionary new];
        if (!requestTokens[@(sourceID)]) {
            int token=-1;
            if (notify_register_check(name.UTF8String,&token)!=NOTIFY_STATUS_OK) return NO;
            requestTokens[@(sourceID)]=@(token);
        }
        return notify_post(name.UTF8String)==NOTIFY_STATUS_OK;
    }
}
