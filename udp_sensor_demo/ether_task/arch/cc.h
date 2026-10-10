/*
 * lwIP compiler/platform abstraction for JASA1 running as a micro T-Kernel
 * task (contrast with ether/lwip_port/arch/cc.h, the standalone bare-metal
 * variant). lwip/arch.h's defaults are otherwise fine: BYTE_ORDER, the
 * u8_t/u16_t/... typedefs, the X8_F/U16_F/... printf format macros, and
 * PACK_STRUCT_* are all unchanged from the standalone port.
 *
 * Two things differ from stock lwip/arch.h defaults, both because this is a
 * -nostdlib freestanding build (no libc, so no printf/rand/abort to fall
 * back on):
 *
 *  - LWIP_PLATFORM_DIAG: routed to the tiny UART printf shim in
 *    ether_printf.c (same printf() used by the ENC424J600 driver's debug
 *    logging) instead of libc printf.
 *  - LWIP_RAND: routed to JASA1's free-running cycle counter instead of
 *    libc rand()/srand(). Used for TCP ISN and ephemeral port selection
 *    (tcp.c, udp.c) -- cycle-count jitter is adequate entropy for a bring-up
 *    demo; this is not meant to be cryptographically sound.
 *
 * LWIP_PLATFORM_ASSERT is intentionally not defined here: LWIP_NOASSERT=1
 * in lwipopts.h strips every LWIP_ASSERT call site at the macro level, so
 * LWIP_PLATFORM_ASSERT is never referenced.
 */
#ifndef LWIP_ARCH_CC_H
#define LWIP_ARCH_CC_H

#include "swc1_time.h"		/* swc1_cycles() -- found via -I to lwip_port/drivers */

int printf(const char *fmt, ...);

#define LWIP_PLATFORM_DIAG(x)   do { printf x; } while (0)
#define LWIP_RAND()             ((u32_t)swc1_cycles())

#endif /* LWIP_ARCH_CC_H */
