#ifndef GVM_GOFA_ALERT_POLICY_H
#define GVM_GOFA_ALERT_POLICY_H
#include <stdbool.h>
#include <math.h>
#include <string.h>

// A point reached in this native candidate membership must not return while receding.
static inline bool GVMGofaPointPassed(bool alreadyPassed, double distance) {
    return alreadyPassed || (isfinite(distance) && distance >= 0 && distance <= 5);
}

// GOFA re-issues its speed board only as its pipeline accepts movement, and none while iOS
// delivers no GPS; its own map keeps the latest board meanwhile. That board stays current
// until GOFA replaces or clears it, or the latest GPS lies beyond this radius from the
// position at which it was observed (NAN when either position was unknown).
#define GVM_GOFA_BOARD_RADIUS 50.0
static inline bool GVMGofaBoardNear(double anchorDistance) {
    return isfinite(anchorDistance) && anchorDistance >= 0 && anchorDistance <= GVM_GOFA_BOARD_RADIUS;
}

// One direction of a GOFA lane, as an OSM turn:lanes value: 1 straight, 4 right, 16 U-turn, 64 left;
// 0 for none, a merge or an unknown value.
static inline unsigned GVMGofaLaneDirection(const char *token, size_t length) {
    static const struct { const char *name; unsigned code; } names[]={
        {"through",1},{"right",4},{"slight_right",4},{"sharp_right",4},
        {"left",64},{"slight_left",64},{"sharp_left",64},{"reverse",16}};
    for (unsigned i=0;i<sizeof(names)/sizeof(names[0]);i++)
        if (strlen(names[i].name)==length && !strncmp(token,names[i].name,length)) return names[i].code;
    return 0;
}
// GOFA's lane board (`detail_lanes`): lanes left to right separated by "|", each lane's directions by
// ";". Writes each lane's direction bitmask and returns the lane count, or 0 when there are more
// than `max` lanes or no lane has a known direction.
static inline unsigned GVMGofaLaneCodes(const char *detail, unsigned *codes, unsigned max) {
    if (!detail || !codes || !max) return 0;
    unsigned count=0;
    bool known=false;
    const char *cursor=detail;
    for (;;) {
        if (count>=max) return 0;
        unsigned code=0;
        for (;;) {
            const char *start=cursor;
            while (*cursor && *cursor!=';' && *cursor!='|') cursor++;
            code|=GVMGofaLaneDirection(start,(size_t)(cursor-start));
            if (*cursor!=';') break;
            cursor++;
        }
        if (code) known=true;
        codes[count++]=code;
        if (*cursor!='|') break;
        cursor++;
    }
    return known ? count : 0;
}
#endif
