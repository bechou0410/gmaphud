#include "../tweak/gofa-alert-policy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    bool passed=false;
    double approach[]={293,149,34,10};
    for (unsigned i=0;i<sizeof(approach)/sizeof(approach[0]);i++) {
        passed=GVMGofaPointPassed(passed,approach[i]); assert(!passed);
    }
    passed=GVMGofaPointPassed(passed,4); assert(passed);
    assert(GVMGofaPointPassed(passed,14));
    assert(GVMGofaPointPassed(passed,27));
    assert(!GVMGofaPointPassed(false,293)); // A new native membership can approach again.
    assert(GVMGofaPointPassed(false,5));
    assert(!GVMGofaPointPassed(false,NAN));
    assert(!GVMGofaPointPassed(false,-1));
    // The latest native board stays current only while the latest GPS remains near its anchor.
    assert(GVMGofaBoardNear(0));
    assert(GVMGofaBoardNear(GVM_GOFA_BOARD_RADIUS));
    assert(!GVMGofaBoardNear(GVM_GOFA_BOARD_RADIUS+1));
    assert(!GVMGofaBoardNear(NAN));
    assert(!GVMGofaBoardNear(-1));
    assert(!GVMGofaBoardNear(INFINITY));
    // Lane boards, as GOFA sent one on Xa lo Ha Noi: left or through, through or right, right.
    unsigned codes[12];
    assert(GVMGofaLaneCodes("left;through|through;right|right",codes,12)==3 && codes[0]==65 && codes[1]==5 && codes[2]==4);
    assert(GVMGofaLaneCodes("reverse;left|slight_right|sharp_left",codes,12)==3 && codes[0]==80 && codes[1]==4 && codes[2]==64);
    assert(GVMGofaLaneCodes("none|through||merge_to_left",codes,12)==4 && codes[0]==0 && codes[1]==1 && codes[2]==0 && codes[3]==0);
    assert(GVMGofaLaneCodes("through",codes,12)==1 && codes[0]==1);
    assert(!GVMGofaLaneCodes("none|none",codes,12) && !GVMGofaLaneCodes("",codes,12) && !GVMGofaLaneCodes("forward",codes,12));
    assert(!GVMGofaLaneCodes("through|through|through",codes,2) && GVMGofaLaneCodes("through|through",codes,2)==2);
    assert(!GVMGofaLaneCodes(NULL,codes,12) && !GVMGofaLaneCodes("through",NULL,12) && !GVMGofaLaneCodes("through",codes,0));
    puts("GOFA passed-point and board policy passed");
}
