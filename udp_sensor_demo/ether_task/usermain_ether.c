/*
 * usermain() for the "ethernet loopback demo + micro T-Kernel" coexistence
 * build (Makefile.swc1_ether). Identical to kernel/usermain/usermain.c's
 * sender/receiver demo -- kept verbatim to prove the rest of the kernel
 * keeps running normally -- plus one additional task: ether_task (see
 * ether_task.c), the ported ENC424J600 + lwIP loopback/UDP-echo demo.
 *
 * This is a separate file (not a modification of usermain.c) so the
 * original Makefile.swc1 build is untouched; Makefile.swc1_ether links
 * this instead of kernel/usermain/usermain.c.
 */
#include <tk/tkernel.h>
#include <tm/tmonitor.h>

static ID mbf_id;

/* format decimal integer into buf; return pointer past the digits */
static UB *put_dec(UB *p, INT v)
{
	UB tmp[12];
	int n = 0;
	if (v < 0) { *p++ = '-'; v = -v; }
	if (v == 0) { *p++ = '0'; return p; }
	while (v > 0) { tmp[n++] = (UB)('0' + v % 10); v /= 10; }
	while (n-- > 0) *p++ = tmp[n];
	return p;
}

/* ---- Sender: sends incrementing integer every 1 second ------------ */
static void sender_task(INT stacd, void *exinf)
{
	INT count = 0;
	UB buf[32];
	UB *p;

	tm_putstring((UB *)"sender\r\n");
	for (;;) {
		tk_dly_tsk(1000);
		count++;
		p = buf;
		__builtin_memcpy(p, "[send] ", 7); p += 7;
		p = put_dec(p, count);
		*p++ = '\r'; *p++ = '\n'; *p = '\0';
		tm_putstring(buf);
		tk_snd_mbf(mbf_id, &count, sizeof(INT), TMO_FEVR);
	}
}

/* ---- Receiver: receives integer and displays it ------------------- */
static void receiver_task(INT stacd, void *exinf)
{
	INT value;
	UB buf[32];
	UB *p;

	tm_putstring((UB *)"receiver\r\n");
	for (;;) {
		tk_rcv_mbf(mbf_id, &value, TMO_FEVR);
		p = buf;
		__builtin_memcpy(p, "[recv] ", 7); p += 7;
		p = put_dec(p, value);
		*p++ = '\r'; *p++ = '\n'; *p = '\0';
		tm_putstring(buf);
	}
}

/* ---- ether_task (ENC424J600 + lwIP + BME280 sender) and its watchdog,
 * see ether_task.c / ether_wdt.c ---- */
#include "ether_task.h"

/* ---- Initial task ------------------------------------------------- */
WEAK_FUNC EXPORT INT usermain(void)
{
	T_CMBF cmbf = {
		.exinf  = NULL,
		.mbfatr = TA_TFIFO,
		.bufsz  = 64,
		.maxmsz = sizeof(INT),
		.bufptr = NULL,
	};
	T_CTSK ctsk = {
		.exinf  = NULL,
		.tskatr = TA_HLNG | TA_RNG0,
		.stksz  = 1024,
		.bufptr = NULL,
	};
	ID sender_id, receiver_id, ether_id, wdt_id;

	tm_putstring((UB *)"usermain_ether: starting sender/receiver + ether_task\r\n");

	mbf_id = tk_cre_mbf(&cmbf);

	ctsk.task    = (FP)receiver_task;
	ctsk.itskpri = 5;
	ctsk.stksz   = 1024;
	receiver_id  = tk_cre_tsk(&ctsk);
	if (receiver_id >= E_OK)
		tk_sta_tsk(receiver_id, 0);

	ctsk.task    = (FP)sender_task;
	ctsk.itskpri = 6;
	ctsk.stksz   = 1024;
	sender_id    = tk_cre_tsk(&ctsk);
	if (sender_id >= E_OK)
		tk_sta_tsk(sender_id, 0);

	/* Ethernet loopback demo -- lower priority (larger number) than the
	 * sender/receiver demo tasks, and a bigger stack (lwIP + the SPI/
	 * ENC424J600 driver use more local buffer space than the tiny demo
	 * tasks above). */
	ctsk.task    = (FP)ether_task;
	ctsk.itskpri = 8;
	ctsk.stksz   = 16384;
	ether_id     = tk_cre_tsk(&ctsk);
	if (ether_id >= E_OK)
		tk_sta_tsk(ether_id, 0);

	/* Watchdog for ether_task: higher priority than ether_task so it can
	 * preempt it when it is stuck in a busy loop. stacd = ID to watch. */
	ctsk.task    = (FP)ether_wdt_task;
	ctsk.itskpri = 7;
	ctsk.stksz   = 1024;
	wdt_id       = tk_cre_tsk(&ctsk);
	if (wdt_id >= E_OK && ether_id >= E_OK)
		tk_sta_tsk(wdt_id, ether_id);

	for (;;) {
		tk_dly_tsk(1000);
	}
	return 0;
}
