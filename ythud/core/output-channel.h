#pragma once
#include <notify.h>
#include <mach/mach_time.h>
#include <signal.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <errno.h>
#include "runtime-mode.h"

// Only a context ID, owner PID, monotonic deadline and host visibility cross processes.
typedef struct { int context, deadline, dashboard; bool open; } YTAVOutputChannel;
#ifndef YTAV_CHANNEL_PREFIX
#if YTAV_RELEASE
#define YTAV_CHANNEL_PREFIX "com.duodash.youtube.dashboard"
#else
#define YTAV_CHANNEL_PREFIX "com.duodash.youtube.output"
#endif
#endif
#define YTAV_OWNER_LIFETIME UINT64_MAX
static inline uint64_t YTAVChannelMillis(void) {
    mach_timebase_info_data_t info; mach_timebase_info(&info);
    return (uint64_t)((long double)mach_continuous_time() * info.numer / info.denom / 1000000);
}
static inline void YTAVChannelClose(YTAVOutputChannel *c) {
    if (c->context >= 0) notify_cancel(c->context);
    if (c->deadline >= 0) notify_cancel(c->deadline);
    if (c->dashboard >= 0) notify_cancel(c->dashboard);
    *c = (YTAVOutputChannel){ -1, -1, -1, false };
}
static inline bool YTAVChannelOpen(YTAVOutputChannel *c) {
    if (c->open) return true;
    *c = (YTAVOutputChannel){ -1, -1, -1, false };
    if (notify_register_check(YTAV_CHANNEL_PREFIX ".context.v1", &c->context) != NOTIFY_STATUS_OK ||
        notify_register_check(YTAV_CHANNEL_PREFIX ".deadline.v1", &c->deadline) != NOTIFY_STATUS_OK ||
        notify_register_check(YTAV_CHANNEL_PREFIX ".dashboard.v1", &c->dashboard) != NOTIFY_STATUS_OK) {
        YTAVChannelClose(c); return false;
    }
    c->open = true; return true;
}
static inline bool YTAVChannelRead(int token, uint64_t *value) {
    *value = 0; return token >= 0 && notify_get_state(token, value) == NOTIFY_STATUS_OK;
}
static inline bool YTAVChannelPublish(YTAVOutputChannel *c, uint32_t context, uint64_t deadline) {
    if (!YTAVChannelOpen(c)) return false;
    uint64_t identity = ((uint64_t)(uint32_t)getpid() << 32) | context;
    // Invalidate the old deadline before replacing an identity.
    if (notify_set_state(c->deadline, 0) != NOTIFY_STATUS_OK ||
        notify_set_state(c->context, context ? identity : 0) != NOTIFY_STATUS_OK ||
        notify_set_state(c->deadline, context ? deadline : 0) != NOTIFY_STATUS_OK) return false;
    return true;
}
static inline void YTAVChannelWithdraw(YTAVOutputChannel *c) {
    uint64_t identity;
    if (c->open && YTAVChannelRead(c->context, &identity) && (uint32_t)(identity >> 32) == (uint32_t)getpid())
        YTAVChannelPublish(c, 0, 0);
}
static inline bool YTAVChannelExport(YTAVOutputChannel *c, uint32_t *context) {
    uint64_t identity, deadline, confirm, now = YTAVChannelMillis();
    *context = 0;
    if (!YTAVChannelOpen(c) || !YTAVChannelRead(c->deadline, &deadline) || !deadline ||
        (!(YTAV_RELEASE && deadline == YTAV_OWNER_LIFETIME) && (deadline <= now || deadline - now > 1800000)) ||
        !YTAVChannelRead(c->context, &identity) || !(uint32_t)identity || !(uint32_t)(identity >> 32) ||
        !YTAVChannelRead(c->deadline, &confirm) || confirm != deadline) return false;
    pid_t owner = (pid_t)(uint32_t)(identity >> 32);
    if (owner <= 0 || (kill(owner, 0) != 0 && errno != EPERM)) return false;
    *context = (uint32_t)identity; return true;
}
static inline bool YTAVChannelHostPublish(YTAVOutputChannel *c, bool visible) {
    return YTAVChannelOpen(c) && notify_set_state(c->dashboard, (YTAVChannelMillis() << 1) | visible) == NOTIFY_STATUS_OK;
}
static inline bool YTAVChannelHost(YTAVOutputChannel *c, bool *visible) {
    uint64_t value, now = YTAVChannelMillis();
    *visible = false;
    if (!YTAVChannelOpen(c) || !YTAVChannelRead(c->dashboard, &value)) return false;
    uint64_t stamp = value >> 1;
    if (!stamp || stamp > now || now - stamp > 2000) return false;
    *visible = (value & 1) != 0; return true;
}
