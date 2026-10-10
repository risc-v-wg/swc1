#ifndef ETHER_TASK_H
#define ETHER_TASK_H

#include <tk/tkernel.h>

/* Incremented by ether_task on every main-loop iteration (and between its
 * init steps); ether_wdt_task restarts ether_task when it stops moving. */
extern volatile UW ether_task_heartbeat;

/* Incremented by sensor_send.c each time a datagram reaches the wire
 * (udp_sendto() == ERR_OK). ether_wdt_task also restarts ether_task when
 * this stops, even if the loop itself (heartbeat) keeps running. */
extern volatile UW ether_task_progress;

/* Which step of the main loop ether_task is in, and the longest single
 * pass through each step (FRC cycles) since ether_wdt_task last reported
 * (it clears them). For the watchdog's stall report only. */
enum {
    ETHER_PHASE_DELAY,      /* tk_dly_tsk(50) -- includes time preempted */
    ETHER_PHASE_POLL,       /* enc424j600if_poll(): link check + RX drain */
    ETHER_PHASE_TIMEOUTS,   /* sys_check_timeouts() */
    ETHER_PHASE_SEND,       /* sensor_send_poll(): sensor read + UDP TX */
    ETHER_PHASE_COUNT
};
extern volatile UW ether_task_phase;
extern volatile UW ether_task_max_cycles[ETHER_PHASE_COUNT];

/* stacd: 0 on the first start, restart count when started again by
 * ether_wdt_task (lwIP state is reset before re-initialising). */
void ether_task(INT stacd, void *exinf);

/* stacd: task ID of ether_task to watch. */
void ether_wdt_task(INT stacd, void *exinf);

#endif /* ETHER_TASK_H */
