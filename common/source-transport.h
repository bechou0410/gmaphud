#import "source-output.h"

// All access is serialized internally. One adapter process owns each source namespace.
BOOL GVMPublishSourceOutput(NSDictionary *output, NSTimeInterval now, BOOL force);
NSDictionary *GVMReadSourceOutput(NSTimeInterval now);
NSUInteger GVMSelectedSourceID(void);
// Availability is a product gate, independent of stable wire IDs.
BOOL GVMSourceEnabled(NSUInteger sourceID);
BOOL GVMSelectOutputSource(NSUInteger sourceID);
// Selects without saving the choice: the supervisor's fallback while the chosen source fails. The
// saved choice comes back with GVMRestoreOutputSelection.
BOOL GVMSelectOutputSourceForNow(NSUInteger sourceID);
void GVMRestoreOutputSelection(void);
NSString *GVMOutputRequestName(NSUInteger sourceID);
BOOL GVMRequestSelectedSource(void);
// Posted after each committed frame, so readers refresh at once instead of waiting for their poll.
NSString *GVMOutputChangedName(NSUInteger sourceID);
// Calls `handler` on `queue` when any source commits a frame or the selection changes. The
// registration lasts for the life of the process; call once.
void GVMObserveSourceOutput(dispatch_queue_t queue, dispatch_block_t handler);
// Calls `handler` on `queue` when the selection changes (Settings, a fallback or a restore). The
// registration lasts for the life of the process; call once.
void GVMObserveSelection(dispatch_queue_t queue, dispatch_block_t handler);
