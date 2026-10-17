#include <stddef.h>
#include <stdint.h>

// Waze's native current speed limit getter, found by its code instead of a fixed address so
// builds other than 5.25.0 can still be read. `text` is the app's __TEXT,__text as 32-bit
// instruction words. Returns the getter's word index, or -1 when it is missing, appears more
// than once, or has no caller that tests its presence bit.
long GVMFindWazeLimitReader(const uint32_t *text, size_t count);
// Whether the getter's code is still at `index` (to reuse an index cached for this build).
int GVMWazeLimitReaderAt(const uint32_t *text, size_t count, size_t index);
// The word index of a known getter address in `text` (5.25.0's measured one), or -1 when the
// address is outside the text or its code no longer matches.
long GVMWazeLimitReaderIndex(const uint32_t *text, size_t count, uintptr_t address);
// Bump when the searched code changes, so indexes cached by an older search are not trusted.
enum { GVMWazeLimitSearchVersion=1 };
