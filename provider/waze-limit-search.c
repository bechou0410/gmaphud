#include "waze-limit-search.h"

// The getter as compiled in Waze 5.25.0 (0x101028ff4, read by the legacy speedometer): it
// lazily creates a static shared_ptr singleton, calls its virtual slot 0x10 and returns an
// optional<int> in km/h (value in the low 32 bits, presence at bit 32). Each pair is an
// instruction and the bits that must match; adrp pages, page offsets and branch targets
// change between builds and are masked out.
static const uint32_t ReaderCode[][2]={
    {0xd100c3ff,0xffffffff},{0xa9014ff4,0xffffffff},{0xa9027bfd,0xffffffff},{0x910083fd,0xffffffff},
    {0x9003b268,0x9f00001f},{0x9113c108,0xffc003ff},{0x08dffd08,0xffffffff},{0x9003b273,0x9f00001f},
    {0x360001e8,0xffffffff},{0xf9427260,0xffc003ff},{0xf9400008,0xffffffff},{0xf9400908,0xffffffff},
    {0xd63f0100,0xffffffff},{0xa90007e0,0xffffffff},{0xd35dfc28,0xffffffff},{0x927d1108,0xffffffff},
    {0x910003e9,0xffffffff},{0xf8686928,0xffffffff},{0x92409d00,0xffffffff},{0xa9427bfd,0xffffffff},
    {0xa9414ff4,0xffffffff},{0x9100c3ff,0xffffffff},{0xd65f03c0,0xffffffff},{0x9003b260,0x9f00001f},
    {0x9113c000,0xffc003ff},{0x94db04ef,0xfc000000},{0x34fffde0,0xffffffff},{0x940062ba,0xfc000000},
    {0xf9400408,0xffffffff},{0x3dc00000,0xffffffff},{0x3d813a60,0xffc003ff},{0xb40000c8,0xffffffff},
    {0x91002108,0xffffffff},{0xc85f7d09,0xffffffff},{0x91000529,0xffffffff},{0xc80a7d09,0xffffffff},
    {0x35ffffaa,0xffffffff},{0x90000000,0x9f00001f},{0x91033000,0xffc003ff},{0x9003b261,0x9f00001f},
    {0x91138021,0xffc003ff},{0xf0ff7ea2,0x9f00001f},{0x91000042,0xffc003ff},{0x94db04c5,0xfc000000},
    {0x9003b260,0x9f00001f},{0x9113c000,0xffc003ff},{0x94db04dd,0xfc000000},{0x17ffffda,0xfc000000},
};
static const size_t ReaderLength=sizeof(ReaderCode)/sizeof(*ReaderCode);

int GVMWazeLimitReaderAt(const uint32_t *text, size_t count, size_t index) {
    if (!text || index>count || count-index<ReaderLength) return 0;
    for (size_t k=0;k<ReaderLength;k++)
        if ((text[index+k]&ReaderCode[k][1])!=(ReaderCode[k][0]&ReaderCode[k][1])) return 0;
    return 1;
}

long GVMWazeLimitReaderIndex(const uint32_t *text, size_t count, uintptr_t address) {
    uintptr_t start=(uintptr_t)text;
    if (!text || address<start || (address-start)%4) return -1;
    size_t index=(address-start)/4;
    return GVMWazeLimitReaderAt(text,count,index) ? (long)index : -1;
}

long GVMFindWazeLimitReader(const uint32_t *text, size_t count) {
    if (!text || count<ReaderLength) return -1;
    long found=-1;
    for (size_t i=0;i+ReaderLength<=count;i++) {
        if (text[i]!=ReaderCode[0][0] || !GVMWazeLimitReaderAt(text,count,i)) continue;
        if (found>=0) return -1;
        found=(long)i;
    }
    if (found<0) return -1;
    // The same getter shape could serve another value; require a caller that, like the
    // speedometer, branches on the presence bit right after the call (tbnz x0, #32).
    for (size_t i=0;i+1<count;i++) {
        uint32_t word=text[i];
        if ((word&0xfc000000)!=0x94000000) continue;
        int64_t delta=(int64_t)((int32_t)(word<<6)>>6);
        if ((int64_t)i+delta!=found) continue;
        if ((text[i+1]&0xfff8001f)==0xb7000000) return found;
    }
    return -1;
}
