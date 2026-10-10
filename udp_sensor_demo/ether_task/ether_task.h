#ifndef ETHER_TASK_H
#define ETHER_TASK_H

#include <tk/tkernel.h>

/* Incremented by ether_task on every main-loop iteration (and between its
 * init steps); ether_wdt_task restarts ether_task when it stops moving. */
extern volatile UW ether_task_heartbeat;

/* stacd: 0 on the first start, restart count when started again by
 * ether_wdt_task (lwIP state is reset before re-initialising). */
void ether_task(INT stacd, void *exinf);

/* stacd: task ID of ether_task to watch. */
void ether_wdt_task(INT stacd, void *exinf);

#endif /* ETHER_TASK_H */
