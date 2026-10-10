#include "swc1_io.h"
#include "swc1_time.h"

void swc1_time_init(void)
{
    SWC1_FRC_CTRL = SWC1_FRC_CTRL_ENABLE;
}

void swc1_delay_cycles(uint32_t cycles)
{
    uint32_t start = swc1_cycles();
    while ((uint32_t)(swc1_cycles() - start) < cycles) {
        /* busy wait */
    }
}

void swc1_delay_us(uint32_t us)
{
    /* 32-bit only: 64-bit math would call libgcc's __muldi3/__udivdi3,
     * and the only libgcc in this toolchain is built for rv32im -- those
     * helpers contain mul/divu, which the RV32I core doesn't execute
     * correctly (swc1_delay_us(1000) measured ~195M cycles instead of 50k).
     * The cycles-per-us constant folds at compile time; us up to ~85 s at
     * 50 MHz before the product overflows. */
    swc1_delay_cycles(us * (uint32_t)(SWC1_CLK_HZ / 1000000UL));
}
