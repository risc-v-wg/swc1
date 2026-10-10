/*
 * Thin, memory-only wrapper around JASA1's byte-FIFO SPI block plus a
 * bit-banged GPIO chip-select. No filesystem, no block-device semantics --
 * just a full-duplex byte-transfer primitive, mirroring the pattern already
 * proven working in cfile/spi_ether_test2.c.
 *
 * IMPORTANT: the SPI block's MOSI/MISO FIFO empty/full status bits are
 * known-buggy in hardware (io_spi_lite.v / sfifo_withr.v use a plain
 * write-address == read-address comparison, which cannot distinguish
 * "empty" from "full after wraparound"). This driver therefore never polls
 * those bits -- it paces transfers by time instead, using the Free Run
 * Counter. See drivers/swc1_io.h.
 */
#ifndef SWC1_SPI_H
#define SWC1_SPI_H

#include <stdint.h>

/* Chip-select is JASA1 GPIO[0] (Arty A7 pin G3), driven manually because the
 * SPI block's own spi_csn output de-asserts every time its MOSI FIFO runs
 * dry, which happens between the software-paced writes of a multi-phase
 * ENC424J600 instruction. See drivers/swc1_io.h for details. */

/* sckdiv: SPI SCK period is 2*(sckdiv+1) CPU clocks (see io_spi_lite.v).
 * Start slow (e.g. 200, matching the value already validated against a real
 * ENC424J600 in spi_ether_test2.c) and only increase once basic register
 * reads are confirmed working -- the sck-to-mosi/miso phase-select bits
 * baked into swc1_spi_init() may need retuning at higher clock rates. */
void swc1_spi_init(uint16_t sckdiv);

/* Raise/lower the manual chip-select line. Call _select(1) before, and
 * _select(0) after, a whole multi-byte ENC424J600 SPI instruction. */
void swc1_spi_select(int asserted);

/* Full-duplex transfer of len bytes. tx or rx may be NULL if you only
 * care about one direction (dummy 0xFF bytes are sent when tx==NULL, and
 * received bytes are discarded when rx==NULL). Does NOT touch chip-select --
 * wrap calls in swc1_spi_select(1)/swc1_spi_select(0). */
void swc1_spi_xfer(const uint8_t *tx, uint8_t *rx, int len);

#endif /* SWC1_SPI_H */
