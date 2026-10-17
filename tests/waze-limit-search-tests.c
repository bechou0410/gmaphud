#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "waze-limit-search.h"

// The 5.25.0 getter words, as Waze laid them out at 0x101028ff4.
static const uint32_t Reader[]={
    0xd100c3ff,0xa9014ff4,0xa9027bfd,0x910083fd,0x9003b268,0x9113c108,0x08dffd08,0x9003b273,
    0x360001e8,0xf9427260,0xf9400008,0xf9400908,0xd63f0100,0xa90007e0,0xd35dfc28,0x927d1108,
    0x910003e9,0xf8686928,0x92409d00,0xa9427bfd,0xa9414ff4,0x9100c3ff,0xd65f03c0,0x9003b260,
    0x9113c000,0x94db04ef,0x34fffde0,0x940062ba,0xf9400408,0x3dc00000,0x3d813a60,0xb40000c8,
    0x91002108,0xc85f7d09,0x91000529,0xc80a7d09,0x35ffffaa,0x90000000,0x9113c000,0x9003b261,
    0x91138021,0xf0ff7ea2,0x91000042,0x94db04c5,0x9003b260,0x9113c000,0x94db04dd,0x17ffffda,
};
enum { Count=600, Words=sizeof(Reader)/sizeof(*Reader) };

static void Place(uint32_t *text, size_t at) { memcpy(text+at,Reader,sizeof(Reader)); }
static void Call(uint32_t *text, size_t from, size_t to, uint32_t next) {
    text[from]=0x94000000|((uint32_t)((int32_t)to-(int32_t)from)&0x03ffffff);
    text[from+1]=next;
}

int main(void) {
    uint32_t text[Count];
    memset(text,0,sizeof(text));
    Place(text,120);
    Call(text,400,120,0xb7000060);                 // bl reader; tbnz x0, #32
    assert(GVMFindWazeLimitReader(text,Count)==120);
    assert(GVMWazeLimitReaderAt(text,Count,120) && !GVMWazeLimitReaderAt(text,Count,121));
    assert(!GVMWazeLimitReaderAt(text,Count,Count-Words+1));
    // A measured address maps to its word index only while the getter's code is there.
    assert(GVMWazeLimitReaderIndex(text,Count,(uintptr_t)(text+120))==120);
    assert(GVMWazeLimitReaderIndex(text,Count,(uintptr_t)(text+121))==-1 && GVMWazeLimitReaderIndex(text,Count,(uintptr_t)text+482)==-1);
    assert(GVMWazeLimitReaderIndex(text,Count,(uintptr_t)text-4)==-1 && GVMWazeLimitReaderIndex(NULL,Count,0)==-1);

    // Another build: new pages, page offsets and branch targets still match.
    text[120+4]=0x90012348; text[120+5]=0x91000108; text[120+9]=0xf9400260;
    text[120+25]=0x94000001; text[120+47]=0x17ffff00;
    assert(GVMFindWazeLimitReader(text,Count)==120);

    // A caller placed before the getter (a forward branch) is found too.
    uint32_t backward[Count];
    memset(backward,0,sizeof(backward));
    Place(backward,500);
    Call(backward,10,500,0xb7000040);
    assert(GVMFindWazeLimitReader(backward,Count)==500);

    // Without a presence test after the call, or with an unrelated instruction there: refused.
    text[401]=0xd503201f;
    assert(GVMFindWazeLimitReader(text,Count)==-1);
    text[401]=0xb7000060;

    // A changed instruction outside the masked fields: not the getter.
    text[120+11]=0xf9400d08;                       // virtual slot 0x18 instead of 0x10
    assert(GVMFindWazeLimitReader(text,Count)==-1);
    text[120+11]=0xf9400908;

    // Two copies are ambiguous.
    Place(text,250);
    assert(GVMFindWazeLimitReader(text,Count)==-1);

    assert(GVMFindWazeLimitReader(NULL,Count)==-1 && GVMFindWazeLimitReader(text,10)==-1);
    puts("waze limit search tests passed");
    return 0;
}
