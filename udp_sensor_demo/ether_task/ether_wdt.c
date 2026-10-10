/*
 * ether_wdt_task -- software watchdog for ether_task.
 *
 * ether_task bumps ether_task_heartbeat every main-loop iteration (~50 ms
 * plus the 1 s sensor read/send). If it hasn't moved for
 * ETHER_WDT_TIMEOUT_MS, ether_task is killed with tk_ter_tsk() and started
 * again from its entry point with tk_sta_tsk(); ether_task resets lwIP and
 * re-initialises the ENC424J600 and the BME280 when started with
 * stacd != 0.
 *
 * Runs at a higher priority than ether_task, so it still gets the CPU when
 * ether_task is stuck in a busy loop. It cannot recover a hang that stops
 * the kernel itself (interrupts disabled, timer queue broken) -- then this
 * task stops too.
 */
#include <tk/tkernel.h>

#include "ether_task.h"

int printf(const char *fmt, ...);

#ifndef ETHER_WDT_TIMEOUT_MS
#define ETHER_WDT_TIMEOUT_MS 10000
#endif
#ifndef ETHER_WDT_CHECK_MS
#define ETHER_WDT_CHECK_MS   100
#endif

void ether_wdt_task(INT stacd, void *exinf)
{
    ID ether_id = (ID)stacd;
    UW last = ether_task_heartbeat;
    UW stale_ms = 0;
    INT restarts = 0;

    (void)exinf;
    printf("ether_wdt: watching ether_task (id %d), timeout %u ms\n",
           (int)ether_id, (unsigned)ETHER_WDT_TIMEOUT_MS);

    for (;;) {
        tk_dly_tsk(ETHER_WDT_CHECK_MS);

        UW now = ether_task_heartbeat;
        if (now != last) {
            last = now;
            stale_ms = 0;
            continue;
        }
        stale_ms += ETHER_WDT_CHECK_MS;
        if (stale_ms < ETHER_WDT_TIMEOUT_MS)
            continue;

        restarts++;
        printf("ether_wdt: no heartbeat for %u ms -- restarting ether_task (#%d)\n",
               (unsigned)stale_ms, (int)restarts);

        /* E_OBJ: already DORMANT (ether_task exited by itself, e.g.
         * netif_add failed) -- just start it again. */
        ER er = tk_ter_tsk(ether_id);
        if (er < E_OK && er != E_OBJ)
            printf("ether_wdt: tk_ter_tsk failed, er=%d\n", (int)er);
        er = tk_sta_tsk(ether_id, restarts);
        if (er < E_OK)
            printf("ether_wdt: tk_sta_tsk failed, er=%d\n", (int)er);

        last = ether_task_heartbeat;
        stale_ms = 0;
    }
}
