// dispbright — read or set the built-in display's backlight level.
//
// Uses Apple's own DisplayServices (a private framework, loaded via dlopen so
// the build never needs a linker stub). This is the only method found that
// still works while SleepDisabled=1, where `pmset displaysleepnow` and the
// `displaysleep` idle timer are both inert.
//
// Build: clang -O2 -o dispbright dispbright.c -framework CoreGraphics
// Usage: dispbright        -> prints current level, 0.0–1.0
//        dispbright 0.0    -> sets the level
#include <dlfcn.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    void *h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);
    if (!h) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); return 2; }
    int (*getB)(CGDirectDisplayID, float*) = dlsym(h, "DisplayServicesGetBrightness");
    int (*setB)(CGDirectDisplayID, float)  = dlsym(h, "DisplayServicesSetBrightness");
    CGDirectDisplayID d = CGMainDisplayID();
    if (argc < 2) {
        if (!getB) { fprintf(stderr, "DisplayServicesGetBrightness not found\n"); return 2; }
        float b = 0; if (getB(d, &b) == 0) { printf("%.4f\n", b); return 0; }
        fprintf(stderr, "read failed\n"); return 1;
    }
    if (!setB) { fprintf(stderr, "DisplayServicesSetBrightness not found\n"); return 2; }
    return setB(d, (float)atof(argv[1])) == 0 ? 0 : 1;
}
