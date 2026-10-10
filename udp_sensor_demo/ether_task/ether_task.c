/*
 * BME280 UDP sender (ENC424J600 + lwIP): once a second, reads the BME280
 * over bit-banged I2C (sensor/) and sends one datagram of
 * temperature/humidity/pressure in sensor_sim.py's format to sensor_monitor.py on the PC -- see
 * lwip_port/app/sensor_send.c. Send-only; nothing is received.
 *
 * Originally the ether/lwip_port loopback demo (ENC424J600 + lwIP + UDP echo), ported
 * from a standalone bare-metal super-loop (ether/lwip_port/app/ether_main.c,
 * NO_SYS=1, its own start.s/link.ld/_sbrk) into one micro T-Kernel task.
 *
 * Everything below main() in ether_main.c is unchanged in substance: same
 * netif_add/lwip_init/udp_echo_init sequence, same enc424j600if_poll() +
 * sys_check_timeouts() loop body. The only real changes are that the loop
 * yields the CPU every iteration via tk_dly_tsk() instead of spinning
 * forever (so sender/receiver and the kernel's own tasks actually get to
 * run -- see usermain_ether.c), and LWIP_TCP is off (see lwipopts.h --
 * enabling TCP corrupted the kernel's task timer queue on real JASA1
 * hardware; root cause not fully isolated, but TCP isn't needed for the
 * UDP loopback test this port exists to run).
 *
 * Demo of the watchdog: the GPIO[3] LED toggles on every send period (see
 * sensor_send.c), and the loop hangs on purpose ETHER_HANG_INTERVAL_MS (40 s) after every
 * (re)start, which stops the blinking until the watchdog restarts it.
 *
 * Watchdog: ether_task bumps ether_task_heartbeat every loop iteration;
 * ether_wdt_task (ether_wdt.c) kills and restarts it if that stops for
 * 10 s. On a restart (stacd != 0) the lwIP globals that lwip_init() does not
 * clear are reset first -- see lwip_reset_for_restart().
 *
 * Resource notes: the ENC424J600 driver is polling-only (no interrupts),
 * so it doesn't compete with micro T-Kernel's sole timer/external
 * interrupt sources. Its SPI pacing (swc1_delay_cycles) only *reads* the
 * Free Run Counter that micro T-Kernel's tick uses -- it never touches
 * FRC_CMP/FRC_CTL, so the two don't collide.
 */
#include "lwip/init.h"
#include "lwip/netif.h"
#include "lwip/timeouts.h"
#include "lwip/ip4_addr.h"
#include "lwip/udp.h"
#include "lwip/etharp.h"
#include "netif/ethernet.h"

#include "enc424j600if.h"
#include "swc1_time.h"
#include "sensor_send.h"
#include "ether_task.h"

int printf(const char *fmt, ...);

/* Demo: ether_task hangs on purpose this long after every (re)start, so
 * the watchdog (ether_wdt.c) gets exercised. 0 = never. */
#ifndef ETHER_HANG_INTERVAL_MS
#define ETHER_HANG_INTERVAL_MS 40000
#endif

static struct netif s_netif;

/* Kernel operating time in ms (wraps after ~49 days; differences only). */
static UW now_ms(void)
{
    SYSTIM tim;
    tk_get_otm(&tim);
    return tim.lo;
}

volatile UW ether_task_heartbeat;

/*
 * lwip_init() re-initialises the heap and the memp pools, but not the
 * lists that point into them: netif_list / netif_default, udp_pcbs, the
 * timeout list (next_timeout, static in timeouts.c -- reachable through
 * LWIP_TESTMODE's sys_timeouts_get_next_timeout(), see lwipopts.h) and the
 * ARP table. After ether_task was killed those still point at the old
 * heap/pools, so clear them before lwip_init() runs again. TCP is not
 * used by this app, so the tcp_*_pcbs lists are always empty.
 */
static void lwip_reset_for_restart(void)
{
    etharp_cleanup_netif(&s_netif); /* frees any pbuf queued on an ARP entry */
    netif_list = NULL;
    netif_default = NULL;
    udp_pcbs = NULL;
    *sys_timeouts_get_next_timeout() = NULL;
    s_netif = (struct netif){0};
}

/* lwIP wants milliseconds since some fixed epoch; reuses the same
 * FRC-cycle-counter approach as the standalone build (see
 * ether/lwip_port/app/ether_main.c's sys_now()). Reading the FRC is safe
 * here: micro T-Kernel owns FRC_CMP/FRC_CTL for its tick, this only reads
 * the free-running counter, so the two never step on each other. */
u32_t sys_now(void)
{
    static uint32_t boot_cycles;
    static int inited = 0;

    if (!inited) {
        boot_cycles = swc1_cycles();
        inited = 1;
    }
    uint32_t elapsed_cycles = (uint32_t)(swc1_cycles() - boot_cycles);
    return elapsed_cycles / (SWC1_CLK_HZ / 1000u);
}

static void print_hwaddr(const uint8_t *hw)
{
    printf("hwaddr=%d.%d.%d.%d.%d.%d\n",
           hw[0], hw[1], hw[2], hw[3], hw[4], hw[5]);
}

/* micro T-Kernel task entry point (T_CTSK.task signature). */
void ether_task(INT stacd, void *exinf)
{
    ip4_addr_t ipaddr, netmask, gw;

    (void)exinf;
    ether_task_heartbeat++;
    if (stacd != 0) {
        printf("ether_task: restarted by watchdog (#%d), resetting lwIP\n", (int)stacd);
        lwip_reset_for_restart();
    }

    IP4_ADDR(&ipaddr, 192, 168, 0, 221);
    IP4_ADDR(&netmask, 255, 255, 255, 0);
    IP4_ADDR(&gw, 0, 0, 0, 0);

    lwip_init();
    ether_task_heartbeat++;

    if (netif_add(&s_netif, &ipaddr, &netmask, &gw, NULL,
                  enc424j600if_init, ethernet_input) == NULL) {
        printf("ether_task: netif_add failed -- check SPI wiring to ENC424J600\n");
        tk_ext_tsk();
    }
    netif_set_default(&s_netif);
    netif_set_up(&s_netif);
    ether_task_heartbeat++;

    sensor_send_init();     /* ~1 s: BME280 setup + calibration over I2C */
    ether_task_heartbeat++;

    print_hwaddr(s_netif.hwaddr);
    printf("ether_task: lwIP up, static IP 192.168.0.221/24, polling...\n");

    UW start_ms = now_ms();
    int was_link_up = 0;
    for (;;) {
        ether_task_heartbeat++;

        UW t = now_ms();

#if ETHER_HANG_INTERVAL_MS > 0
        /* Demo: hang on purpose (busy loop, so the GPIO[3] LED stops blinking)
         * ETHER_HANG_INTERVAL_MS after every (re)start, for
         * ether_wdt_task to recover. */
        if ((UW)(t - start_ms) >= ETHER_HANG_INTERVAL_MS) {
            printf("ether_task: deliberate hang (ETHER_HANG_INTERVAL_MS=%u)\n",
                   (unsigned)ETHER_HANG_INTERVAL_MS);
            for (;;)
                ;
        }
#endif

        enc424j600if_poll(&s_netif);

        int is_link_up = netif_is_link_up(&s_netif);
        if (is_link_up != was_link_up) {
            printf(is_link_up ? "ether_task: link UP\n" : "ether_task: link DOWN\n");
            was_link_up = is_link_up;
        }

        sys_check_timeouts();

        sensor_send_poll();

        /* Yield to other tasks (sender/receiver demo tasks, init task) each
         * iteration -- this is what actually makes the ethernet loopback
         * demo coexist with the rest of micro T-Kernel instead of
         * monopolizing the single RV32I core. */
        tk_dly_tsk(50);
    }
}
