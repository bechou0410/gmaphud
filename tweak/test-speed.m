#import <Foundation/Foundation.h>
#import "test-state.h"
#include <notify.h>
#include <errno.h>
#include <stdlib.h>

static BOOL Number(const char *text, NSInteger *value) {
    char *end; errno = 0;
    long parsed = strtol(text, &end, 10);
    if (errno || end == text || *end) return NO;
    *value = parsed; return YES;
}
int main(int argc, char **argv) {
    @autoreleasepool {
        uint64_t state = 0;
        if (!(argc == 2 && strcmp(argv[1], "off") == 0)) {
            NSInteger speed, limit, duration;
            if (argc != 4 || !Number(argv[1], &speed) || !Number(argv[2], &limit) || !Number(argv[3], &duration) ||
                !(state = GVMEncodeTest(speed, limit, NSProcessInfo.processInfo.systemUptime, duration))) {
                fprintf(stderr, "Usage: gvm-test-speed SPEED_KMH LIMIT_KMH SECONDS (1..300), or off\n"); return 2;
            }
        }
        int token;
        if (notify_register_check(GVMTestStateName, &token) != NOTIFY_STATUS_OK) return 3;
        uint32_t result = notify_set_state(token, state);
        if (result == NOTIFY_STATUS_OK) notify_post(GVMTestStateName);
        notify_cancel(token);
        if (result != NOTIFY_STATUS_OK) { fprintf(stderr, "Test publication refused\n"); return 3; }
        printf(state ? "TEST active; automatic expiry; only Google CarPlay speed model overridden\n" : "TEST off; live VietMap restored\n");
        return 0;
    }
}
