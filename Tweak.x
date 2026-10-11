// DualBT - tu dong ep Audio Sharing chap nhan thiet bi Bluetooth thuong.
// Khong can log: luc chay, tweak tu quet cac ham ObjC trong bluetoothd /
// mediaserverd / SpringBoard, ham nao la "kiem tra kha nang chia se am thanh"
// (tra ve BOOL, khong tham so) thi ep tra ve YES.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

static NSMutableSet *gPatched;

static BOOL NameMatches(const char *sel) {
    if (!(strcasestr(sel, "audiosharing") || strcasestr(sel, "shareaudio") || strcasestr(sel, "sharingaudio")))
        return NO;
    static const char *keys[] = {"support", "eligib", "compatib", "canshare", "allow", NULL};
    for (int i = 0; keys[i]; i++) if (strcasestr(sel, keys[i])) return YES;
    return NO;
}

static void PatchClassOne(Class c, const char *cname) {
    unsigned int mc = 0;
    Method *ms = class_copyMethodList(c, &mc);
    for (unsigned int j = 0; j < mc; j++) {
        const char *name = sel_getName(method_getName(ms[j]));
        if (strchr(name, ':')) continue;          // chi ham khong tham so
        if (!NameMatches(name)) continue;
        char *rt = method_copyReturnType(ms[j]);
        BOOL isBool = rt && (rt[0] == 'B' || rt[0] == 'c');
        free(rt);
        if (!isBool) continue;
        NSString *key = [NSString stringWithFormat:@"%s|%s|%p", cname, name, c];
        if ([gPatched containsObject:key]) continue;
        [gPatched addObject:key];
        method_setImplementation(ms[j], imp_implementationWithBlock(^BOOL(id _self) { return YES; }));
        NSLog(@"[DualBT] patched %s %s in %s", class_isMetaClass(c) ? "+" : "-", name, getprogname());
    }
    free(ms);
}

static void ScanAndPatch(void) {
    @autoreleasepool {
        unsigned int count = 0;
        Class *list = objc_copyClassList(&count);
        for (unsigned int i = 0; i < count; i++) {
            const char *cn = class_getName(list[i]);
            PatchClassOne(list[i], cn);                    // ham instance
            PatchClassOne(object_getClass(list[i]), cn);   // ham class (+)
        }
        free(list);
    }
}

%ctor {
    @autoreleasepool {
        gPatched = [NSMutableSet set];
        NSLog(@"[DualBT] loaded in %s pid=%d", getprogname(), getpid());
        // Quet nhieu lan vi mot so framework chi nap sau khi khoi dong
        int delays[] = {3, 15, 45};
        for (int i = 0; i < 3; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delays[i] * NSEC_PER_SEC),
                           dispatch_get_global_queue(0, 0), ^{ ScanAndPatch(); });
        }
    }
}
