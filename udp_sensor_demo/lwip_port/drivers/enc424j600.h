/*
 * Minimal, memory-only ENC424J600 SPI Ethernet controller driver for JASA1.
 *
 * Register/opcode constants come from the ENC424J600/624J600 data sheet
 * (Microchip DS39935B): Section 3 (SFR map), Section 4 (SPI instruction
 * set), Section 8 (initialization), Section 9 (packet TX/RX).
 *
 * There is no filesystem and no block-device notion here -- packets are
 * plain byte buffers in RAM, handed in/out by the caller (the lwIP netif
 * glue in netif/enc424j600if.c).
 */
#ifndef ENC424J600_H
#define ENC424J600_H

#include <stdint.h>

#define ENC424J600_MAX_FRAME 1518

/* Returns 0 on success, -1 if the chip did not respond as expected
 * (wiring/reset problem). Uses the ENC424J600's factory-programmed MAC
 * address; read it back with enc424j600_get_hwaddr() after init. */
int enc424j600_init(void);

void enc424j600_get_hwaddr(uint8_t hwaddr[6]);

/* 1 if the PHY reports link up, 0 otherwise. Safe to poll continuously;
 * internally resyncs MAC duplex settings the first time link comes up
 * after being down. */
int enc424j600_link_up(void);

/* Copies one pending frame into buf (buf must be at least buflen bytes) and
 * returns its length in bytes (destination MAC + source MAC + type/length +
 * payload + padding -- the trailing 4-byte hardware CRC is stripped, it is
 * not lwIP's concern), or 0 if no frame is pending or it was filtered out.
 * A frame whose on-the-wire size (including the 4-byte CRC) exceeds buflen
 * is dropped (still consumed from the device) and -1 is returned. */
int enc424j600_recv(uint8_t *buf, int buflen);

/* Transmits one frame of len bytes (len must be <= ENC424J600_MAX_FRAME).
 * Blocks (polling) until the device reports transmission complete.
 * Returns 0 on success, -1 on a MAC-reported transmit error. */
int enc424j600_send(const uint8_t *buf, int len);

/* Diagnostic counters for ether_wdt.c: frames sent OK / failed, frames
 * received, and the most ECON1 polls one send has waited for TXRTS to
 * clear (cleared by the reader). */
extern volatile uint32_t enc424j600_tx_ok;
extern volatile uint32_t enc424j600_tx_err;
extern volatile uint32_t enc424j600_rx_cnt;
extern volatile uint32_t enc424j600_tx_wait_max;

#endif /* ENC424J600_H */
