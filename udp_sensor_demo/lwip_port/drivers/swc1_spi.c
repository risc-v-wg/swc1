#include "swc1_io.h"
#include "swc1_spi.h"
#include "swc1_time.h"

/*
 * SPI mode register (0xF200) layout, from JASA1 spec 2.4.6:
 *   [0]     SPI enable
 *   [2:1]   CPHA, CPOL           -> 0,0 = SPI mode 0,0 (required by ENC424J600)
 *   [3]     bit endian           -> 1 = MSB first ("big endian")
 *   [18:16] sck phase vs. mosi shift-register tap
 *   [22:20] sck phase vs. miso shift-register tap
 *   [26:24] miso data latch timing
 *
 * The phase/latch tap values below (2, 2, 0) are the ones already proven
 * against a real ENC424J600 over SPI in cfile/spi_ether_test2.c (successful
 * EIDLED register read). They may need retuning if sckdiv is lowered a lot
 * (i.e. SCK sped up) since they compensate for board-level round-trip delay.
 */
#define SPI_MODE_ENABLE       (1u << 0)
#define SPI_MODE_CPHA0_CPOL0  (0u << 1)
#define SPI_MODE_MSB_FIRST    (1u << 3)
//#define SPI_MODE_SCK_PH_MOSI  (2u << 16)
//#define SPI_MODE_SCK_PH_MISO  (2u << 20)
//#define SPI_MODE_MISO_LATTMG  (0u << 24)
#define SPI_MODE_SCK_PH_MOSI  (3u << 16)
#define SPI_MODE_SCK_PH_MISO  (3u << 20)
#define SPI_MODE_MISO_LATTMG  (3u << 24)

/*
 * NOTE ON PACING: io_spi_lite.v's MOSI/MISO FIFO empty/full status bits are
 * buggy in hardware (sfifo_withr.v's rqempty/wqfull are a naive
 * write-addr==read-addr compare that cannot tell "empty" from "full after
 * wraparound"). We therefore never poll them. Instead we busy-wait a fixed
 * number of system-clock cycles -- comfortably longer than one SPI byte
 * takes at the configured divider -- before reading back each byte.
 *
 * SEPARATELY (confirmed by reading io_spi_lite.v/sfifo_withr.v directly):
 * the MISO FIFO's *write* side has no overflow protection at all --
 * `miso_fifo_we = miso_wen_byte;` in io_spi_lite.v, unconditional, unlike
 * the MOSI FIFO's write which is properly gated by `~mosi_fifo_full`. Every
 * byte written to MOSI drives out a full 8-SCK-cycle byte on the wire and
 * shifts a corresponding MISO byte into this same unguarded FIFO -- and the
 * underlying storage (sfifo_1r1w) is a hard-fixed 8-deep RAM (3-bit
 * address). If more than SWC1_SPI_FIFO_DEPTH bytes are ever written to
 * MOSI before an equal number of MISO bytes are read back out, the address
 * wraps and newly-arriving bytes silently overwrite still-unread ones --
 * with no backpressure possible even in principle, since there is nowhere
 * to buffer more than 8 bytes at the hardware level. This -- not a pure
 * timing-margin problem -- is what explains the "8-byte-periodic" data
 * corruption seen on real hardware (see enc424j600.c's read/write-verify
 * workarounds) and why widening the per-byte delay margin alone never
 * helped. swc1_spi_xfer() below enforces the hardware's actual contract
 * directly: never let more than SWC1_SPI_FIFO_DEPTH MOSI writes be
 * outstanding without reading back that many MISO bytes first.
 */
#define SWC1_SPI_FIFO_DEPTH 8

/* Burst size swc1_spi_xfer() actually uses per write/read round, kept
 * below SWC1_SPI_FIFO_DEPTH as headroom rather than driving the FIFO to
 * exactly its hard limit every round. */
//#define SWC1_SPI_BURST_LEN 4
#define SWC1_SPI_BURST_LEN 7

static uint32_t s_byte_delay_cycles;

void swc1_spi_init(uint16_t sckdiv)
{
    swc1_time_init();

    /* CS is JASA1 GPIO[0]; make it an output, idle high (deasserted).
     * Read-modify-write: GPIO[1..3] belong to the BME280 I2C driver and
     * the alive LED (sensor/gpio_ctrl.c). */
    SWC1_GPIO_OUT |= 0x1;
    SWC1_GPIO_ENABLE |= 0x1;

    SWC1_SPI_SCKDIV = sckdiv;
    SWC1_SPI_MODE = SPI_MODE_ENABLE | SPI_MODE_CPHA0_CPOL0 | SPI_MODE_MSB_FIRST |
                      SPI_MODE_SCK_PH_MOSI | SPI_MODE_SCK_PH_MISO | SPI_MODE_MISO_LATTMG;

    /* One SPI byte = 8 SCK periods = 8 * 2*(sckdiv+1) system clocks. Double
     * it and add a fixed pipeline margin (shift-register/latch chain plus
     * state-machine bootstrap latency) -- deliberately conservative until
     * this is measured/tuned on real hardware. */
    s_byte_delay_cycles = 16u * ((uint32_t)sckdiv + 1u) * 2u + 64u;

#ifndef SWC1_SPI_DEBUG_MARGIN_MULT
#define SWC1_SPI_DEBUG_MARGIN_MULT 1
#endif
    /*
     * Ruled out: quadrupling this margin did not change the corruption
     * rate at all, and the corruption was later shown (via two MISMATCHes
     * landing at the same mod-8 SPI transfer offset despite different
     * absolute buffer addresses) to be an io_spi_lite.v 8-deep-FIFO logic
     * issue, not a timing margin problem -- see the read/write-verify
     * retry workaround in enc424j600.c's enc424j600_recv()/_send(). Back
     * to 1 (no extra margin) now that this is understood; kept as a knob
     * only in case future measurement suggests retuning it for real.
     */
    s_byte_delay_cycles *= SWC1_SPI_DEBUG_MARGIN_MULT;

    /* One-time clear of whatever was left in the RX FIFO from a previous
     * run/reset. This is unrelated to the buggy empty/full comparator --
     * q_reset forces both wadr/radr back to 0. */
    SWC1_SPI_MISO = SWC1_SPI_MISO_RESET;
    swc1_delay_cycles(s_byte_delay_cycles);
}

void swc1_spi_select(int asserted)
{
    /* active low; read-modify-write so GPIO[1..3] are left alone */
    if (asserted)
        SWC1_GPIO_OUT &= ~0x1u;
    else
        SWC1_GPIO_OUT |= 0x1u;
}

void swc1_spi_xfer(const uint8_t *tx, uint8_t *rx, int len)
{
    /*
     * WORKAROUND: JASA1's QSPI PSRAM corrupts single-byte (`sb`) writes
     * landing 3 bytes before a 1024-byte page boundary (confirmed on real
     * hardware, see cfile/qspi_mem_stress_test.c and project notes) --
     * `rx` here is caller-supplied RAM (e.g. enc424j600if.c's `frame[]`),
     * just as exposed as any other QSPI-PSRAM-resident buffer. Accumulate
     * 4 received bytes purely in registers (`word`/`shift`, not a memory
     * scratch array -- that would just move the vulnerable byte-write
     * elsewhere) and issue one aligned 4-byte (`sw`) store into `rx` per 4
     * bytes, instead of 4 individual `sb`s. This is purely about how a
     * received byte gets stored into the caller's buffer -- it does not
     * change SPI wire protocol, timing, or burst size at all; `rx` callers
     * with len >= 4 must be 4-byte aligned (see call sites).
     */
    uint32_t word = 0;
    int shift = 0;
    int rx_idx = 0;

    int off = 0;
    while (off < len) {
        int chunk = len - off;
        if (chunk > SWC1_SPI_BURST_LEN)
            chunk = SWC1_SPI_BURST_LEN;

        /* Write this chunk's bytes as a burst -- MOSI writes are safely
         * gated by hardware (~mosi_fifo_full) and chunk is capped at the
         * FIFO depth, so this can never overflow. */
        for (int i = 0; i < chunk; i++) {
            uint8_t out = tx ? tx[off + i] : 0xFF;
            SWC1_SPI_MOSI = out;
        }

        /* Wait for the whole chunk's worth of SCK cycles to clock out (and
         * the corresponding MISO bytes to shift in) before reading any of
         * them back. */
        swc1_delay_cycles(s_byte_delay_cycles * (uint32_t)chunk);

        /* Drain exactly `chunk` MISO bytes -- matching the burst 1:1 --
         * before this loop is allowed to write the next chunk. This is the
         * hardware's actual contract: never let unread MISO bytes exceed
         * SWC1_SPI_FIFO_DEPTH. */
        for (int i = 0; i < chunk; i++) {
            uint32_t in = SWC1_SPI_MISO;
            if (rx) {
                word |= (uint32_t)(in & 0xFFu) << shift;
                shift += 8;
                if (shift == 32) {
                    *(uint32_t *)(rx + rx_idx) = word; /* one aligned sw */
                    rx_idx += 4;
                    word = 0;
                    shift = 0;
                }
            }
        }

        off += chunk;
    }

    if (rx) {
        while (shift > 0) {
            rx[rx_idx++] = (uint8_t)word; /* 0-3 byte tail: unavoidable sb */
            word >>= 8;
            shift -= 8;
        }
    }
}
