/*
 * lwIP configuration for the JASA1 + ENC424J600 loopback demo running as a
 * micro T-Kernel task (see ether_task.c), alongside other kernel tasks.
 *
 * Derived from ether/lwip_port/lwipopts.h (the standalone bare-metal
 * bring-up). Differs in exactly one respect: MEM_LIBC_MALLOC is off here.
 * The standalone build rides on newlib's malloc/_sbrk (cfile/add_for_cmpl2.c)
 * over a dedicated heap region reserved by its own linker script. Under
 * micro T-Kernel, all free RAM past .bss is already claimed as the kernel's
 * own Imalloc pool (see kernel/tkernel/memory.c) -- there is no separate
 * "raw" heap left for a second, independent allocator to run on top of, and
 * this build has no libc linked in anyway (Makefile.swc1 is -nostdlib). So
 * lwIP uses its own internal static-pool allocator instead (mem.c), sized by
 * MEM_SIZE below, entirely independent of the kernel's Imalloc pool.
 */
#ifndef LWIPOPTS_H
#define LWIPOPTS_H

#define NO_SYS                     1
#define LWIP_NETCONN               0
#define LWIP_SOCKET                0

/* No interrupts are used anywhere in this port (SPI/ENC424J600 polling only,
 * see ether_task.c) -- SYS_ARCH_PROTECT/UNPROTECT's no-op defaults are fine. */
#define SYS_LIGHTWEIGHT_PROT       0

#define MEM_ALIGNMENT              4
#define MEM_LIBC_MALLOC            0
#define MEMP_MEM_MALLOC            0
/* Static heap for lwIP's own allocator (pbufs, pcbs, etc). Comfortably more
 * than a single UDP echo + ARP + a handful of TCP connections need. */
#define MEM_SIZE                   (24 * 1024)

#define LWIP_ARP                   1
#define LWIP_ICMP                  1
#define LWIP_UDP                   1
/* Off: this app is UDP-only, and ether_task.c's header notes that
 * enabling TCP corrupted micro T-Kernel's task timer queue on real JASA1
 * hardware -- a suspect for the rare ether_task hang. */
#define LWIP_TCP                   0
#define LWIP_RAW                   0

#define LWIP_DHCP                  0

#define TCP_MSS                    1460

#define LWIP_NETIF_LINK_CALLBACK   1
#define LWIP_NETIF_STATUS_CALLBACK 0
#define LWIP_STATS                 0

/* newlib's <ctype.h> #defines _B (a ctype bitmask constant) which collides
 * with micro T-Kernel's own `typedef volatile B _B;` in tk/typedef.h. Skip
 * <ctype.h> entirely -- lwip/arch.h falls back to its own tiny isdigit()/
 * isspace()/etc macros, which is all lwIP actually needs here. */
#define LWIP_NO_CTYPE_H            1

/* No <assert.h>/no libc under -nostdlib -- strip LWIP_ASSERT entirely rather
 * than supply LWIP_PLATFORM_ASSERT (see arch/cc.h for LWIP_PLATFORM_DIAG,
 * which IS still supplied, routed to the UART printf shim). */
#define LWIP_NOASSERT              1

/* Only for sys_timeouts_get_next_timeout(): ether_task.c clears lwIP's
 * timeout list before re-running lwip_init() after a watchdog restart.
 * In this lwIP version LWIP_TESTMODE does nothing else that matters here
 * (it also un-statics lwip_cyclic_timer() and adds netif_get_loopif()). */
#define LWIP_TESTMODE              1

#endif /* LWIPOPTS_H */
