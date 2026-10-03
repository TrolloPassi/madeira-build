/* FEXCore for the iOS app (FEX/build-ios) references hooks that, on Windows, the
 * FEX PE modules define (Source/Windows/ARM64EC/IosJitAlias.cpp, WOW64/IosMonoBridge.cpp,
 * WOW64/Module.cpp, Common/CallRetStack.h). The app links FEXCore without those
 * modules, so the link fails with undefined symbols. These weak definitions match
 * the modules' idle state (no Mono bridge armed, no sub-floor window, no FEX band);
 * a real definition elsewhere in the link takes precedence. */
#include <stdint.h>

#define WEAK __attribute__((weak, visibility("default")))

WEAK uintptr_t ios_fex_band_base = 0;
WEAK uintptr_t ios_fex_band_end = 0;

WEAK uint64_t IosMonoResolveRW(uint64_t addr, uint64_t size) { (void)addr; (void)size; return 0; }
WEAK uint64_t IosSubfloorToReal(uint64_t addr) { return addr; }
WEAK int IosSubfloorWindowForCode(uint64_t a, uint64_t *b, uint64_t *c, uint64_t *d)
{ (void)a; (void)b; (void)c; (void)d; return 0; }

WEAK int ios_fex_mono_bridge_armed(void) { return 0; }
WEAK int ios_fex_mono_take_pending(uint64_t *block, uint64_t *pc, uint64_t *fault)
{ (void)block; (void)pc; (void)fault; return 0; }
WEAK void ios_fex_mono_count_activated(void) {}
WEAK uint64_t ios_fex_mono_captured_count(void) { return 0; }
WEAK void ios_fex_mono_count_helper(int miss) { (void)miss; }

struct rpm_cas_snapshot;
WEAK int rpm_cas_snapshot_take(struct rpm_cas_snapshot *out) { (void)out; return 0; }
