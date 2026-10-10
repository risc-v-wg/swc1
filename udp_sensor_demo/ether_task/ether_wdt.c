/*
 * ether_wdt_task -- software watchdog for ether_task.
 *
 * Two things are watched:
 *  - ether_task_heartbeat: bumped every main-loop iteration (~50 ms plus
 *    the 1 s sensor read/send). Stops when the loop itself is stuck.
 *  - ether_task_progress: bumped by sensor_send.c every time a datagram
 *    reaches the wire (once a second). Stops also when the loop keeps
 *    running but nothing gets sent -- the real ~20 s hang looks like this
 *    (heartbeat and the kernel's sender/receiver demo keep going).
 *
 * If either hasn't moved for ETHER_WDT_TIMEOUT_MS, ether_task is killed
 * with tk_ter_tsk() and started again from its entry point with
 * tk_sta_tsk(); ether_task resets lwIP and re-initialises the ENC424J600
 * and the BME280 when started with stacd != 0.
 *
 * From ETHER_WDT_REPORT_MS without progress, a one-line report is printed
 * every ETHER_WDT_REPORT_EVERY_MS: how far the heartbeat moved, which loop
 * step ether_task is in, the longest pass through each step, and the
 * ENC424J600 TX/RX counters -- to see where the time goes during a stall.
 * If progress comes back by itself, how long it was stalled is printed.
 *
 * Runs at a higher priority than ether_task, so it still gets the CPU when
 * ether_task is stuck in a busy loop. It cannot recover a hang that stops
 * the kernel itself (interrupts disabled, timer queue broken) -- then this
 * task stops too.
 */
#include <tk/tkernel.h>

#include "ether_task.h"
#include "enc424j600.h"
#include "swc1_time.h"

int printf(const char *fmt, ...);

#ifndef ETHER_WDT_TIMEOUT_MS
#define ETHER_WDT_TIMEOUT_MS 10000
#endif
#ifndef ETHER_WDT_CHECK_MS
#define ETHER_WDT_CHECK_MS   100
#endif
#ifndef ETHER_WDT_REPORT_MS
#define ETHER_WDT_REPORT_MS  3000
#endif
#ifndef ETHER_WDT_REPORT_EVERY_MS
#define ETHER_WDT_REPORT_EVERY_MS 1000
#endif

static const char *const phase_name[ETHER_PHASE_COUNT] = {
    "delay", "poll", "timeouts", "send"
};

/* FRC cycles -> ms (32-bit only, see swc1_time.c). */
static unsigned cyc_to_ms(UW cyc)
{
    return (unsigned)(cyc / (SWC1_CLK_HZ / 1000u));
}

/* One line: what ether_task did while no datagram went out. Clears the
 * per-step maxima and the TX wait maximum. */
static void report(const char *what, UW stale_ms, UW hb_moved)
{
    UW mx[ETHER_PHASE_COUNT];
    for (int i = 0; i < ETHER_PHASE_COUNT; i++) {
        mx[i] = ether_task_max_cycles[i];
        ether_task_max_cycles[i] = 0;
    }
    UW tx_wait = enc424j600_tx_wait_max;
    enc424j600_tx_wait_max = 0;
    UW ph = ether_task_phase;

    printf("ether_wdt: %s %u ms: hb +%u, in %s, max ms delay=%u poll=%u tmo=%u send=%u,"
           " tx ok=%u err=%u wait=%u, rx=%u\n",
           what, (unsigned)stale_ms, (unsigned)hb_moved,
           ph < ETHER_PHASE_COUNT ? phase_name[ph] : "init",
           cyc_to_ms(mx[ETHER_PHASE_DELAY]), cyc_to_ms(mx[ETHER_PHASE_POLL]),
           cyc_to_ms(mx[ETHER_PHASE_TIMEOUTS]), cyc_to_ms(mx[ETHER_PHASE_SEND]),
           (unsigned)enc424j600_tx_ok, (unsigned)enc424j600_tx_err,
           (unsigned)tx_wait, (unsigned)enc424j600_rx_cnt);
}

void ether_wdt_task(INT stacd, void *exinf)
{
    ID ether_id = (ID)stacd;
    UW last_hb = ether_task_heartbeat;
    UW last_prog = ether_task_progress;
    UW hb_at_prog = last_hb;   /* heartbeat when progress last moved */
    UW hb_stale_ms = 0;
    UW prog_stale_ms = 0;
    UW next_report_ms = ETHER_WDT_REPORT_MS;
    INT restarts = 0;

    (void)exinf;
    printf("ether_wdt: watching ether_task (id %d), timeout %u ms\n",
           (int)ether_id, (unsigned)ETHER_WDT_TIMEOUT_MS);

    for (;;) {
        tk_dly_tsk(ETHER_WDT_CHECK_MS);

        UW hb = ether_task_heartbeat;
        if (hb != last_hb) {
            last_hb = hb;
            hb_stale_ms = 0;
        } else {
            hb_stale_ms += ETHER_WDT_CHECK_MS;
        }

        UW prog = ether_task_progress;
        if (prog != last_prog) {
            if (prog_stale_ms >= ETHER_WDT_REPORT_MS)
                report("send resumed after", prog_stale_ms, hb - hb_at_prog);
            last_prog = prog;
            hb_at_prog = hb;
            prog_stale_ms = 0;
            next_report_ms = ETHER_WDT_REPORT_MS;
            continue;
        }
        prog_stale_ms += ETHER_WDT_CHECK_MS;

        if (prog_stale_ms >= next_report_ms) {
            report("no send for", prog_stale_ms, hb - hb_at_prog);
            next_report_ms += ETHER_WDT_REPORT_EVERY_MS;
        }

        if (hb_stale_ms < ETHER_WDT_TIMEOUT_MS && prog_stale_ms < ETHER_WDT_TIMEOUT_MS)
            continue;

        restarts++;
        if (hb_stale_ms >= ETHER_WDT_TIMEOUT_MS)
            printf("ether_wdt: no heartbeat for %u ms -- restarting ether_task (#%d)\n",
                   (unsigned)hb_stale_ms, (int)restarts);
        else
            printf("ether_wdt: no send for %u ms (loop still running) -- restarting ether_task (#%d)\n",
                   (unsigned)prog_stale_ms, (int)restarts);

        /* E_OBJ: already DORMANT (ether_task exited by itself, e.g.
         * netif_add failed) -- just start it again. */
        ER er = tk_ter_tsk(ether_id);
        if (er < E_OK && er != E_OBJ)
            printf("ether_wdt: tk_ter_tsk failed, er=%d\n", (int)er);
        er = tk_sta_tsk(ether_id, restarts);
        if (er < E_OK)
            printf("ether_wdt: tk_sta_tsk failed, er=%d\n", (int)er);

        last_hb = hb_at_prog = ether_task_heartbeat;
        last_prog = ether_task_progress;
        hb_stale_ms = 0;
        prog_stale_ms = 0;
        next_report_ms = ETHER_WDT_REPORT_MS;
    }
}
