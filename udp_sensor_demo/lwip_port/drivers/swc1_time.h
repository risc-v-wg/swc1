/*
 * Cycle-accurate timing helpers built on JASA1's Free Run Counter
 * (0xC000_F800, JASA1 spec section 2.4.2). Used both for pacing SPI
 * transfers (see swc1_spi.c -- the FIFO status bits can't be trusted, see
 * drivers/swc1_io.h) and for lwIP's sys_now().
 */
#ifndef SWC1_TIME_H
#define SWC1_TIME_H

#include <stdint.h>
#include "swc1_io.h"

/* System clock as configured in the FPGA bitstream (PLL output feeding
 * JASA1's clk pin). The JASA1 spec targets 25-50 MHz; the FPGA bring-up
 * walkthrough in the spec configures the Vivado Clocking Wizard for 50 MHz,
 * so that is the default here. Override with -DSWC1_CLK_HZ=<value> at
 * build time if your bitstream uses a different PLL setting. */
#ifndef SWC1_CLK_HZ
#define SWC1_CLK_HZ 50000000UL
#endif

/* Make sure the Free Run Counter is actually running. Idempotent/harmless
 * to call more than once; does not touch the compare registers, so it does
 * not enable any timer interrupt. */
void swc1_time_init(void);

/* Low 32 bits of the free-running cycle counter. Wraps every ~2^32 cycles
 * (~86s @ 50MHz); only subtraction-based (unsigned wraparound-safe) deltas
 * should be used, never absolute comparisons across a long idle period. */
static inline uint32_t swc1_cycles(void)
{
    return SWC1_FRC_LOW;
}

/* Busy-wait for at least `cycles` system-clock cycles. */
void swc1_delay_cycles(uint32_t cycles);

/* Busy-wait for at least `us` microseconds. */
void swc1_delay_us(uint32_t us);

#endif /* SWC1_TIME_H */
