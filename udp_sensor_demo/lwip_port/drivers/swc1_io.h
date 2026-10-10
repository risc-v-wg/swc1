/*
 * JASA1 (SWC1) memory-mapped I/O register addresses.
 *
 * Taken from the JASA1 detailed spec (JASA1_contents_v2/Jasa1web全部.html,
 * section 2.4) and cross-checked against swc1/io/io_spi_lite.v,
 * swc1/io/io_frc.v and swc1/fpga/fpga_top.v.
 */
#ifndef SWC1_IO_H
#define SWC1_IO_H

#include <stdint.h>

#define SWC1_REG(addr) (*(volatile uint32_t *)(addr))

/* ---- SPI (0xF200) ---- */
#define SWC1_SPI_MODE    SWC1_REG(0xc000f200)
#define SWC1_SPI_SCKDIV  SWC1_REG(0xc000f204)
#define SWC1_SPI_MOSI    SWC1_REG(0xc000f208) /* write: push TX byte. read: {empty,full,8'd0} */
#define SWC1_SPI_MISO    SWC1_REG(0xc000f20c) /* write bit10=1: reset RX FIFO. read: {empty,full,data[7:0]} */

#define SWC1_SPI_MISO_EMPTY   (1u << 9)
#define SWC1_SPI_MISO_FULL    (1u << 8)
#define SWC1_SPI_MISO_RESET   (1u << 10)

/*
 * NOTE: the SPI block's own spi_csn output only stays asserted while the
 * MOSI FIFO is non-empty (see io_spi_lite.v: cs_all_status = (state !=
 * IDLE)). It de-asserts CS as soon as the FIFO drains, which happens
 * between every software-paced *_MOSI write. That is fine for something
 * like a simple flash read but the ENC424J600 requires CS held low for an
 * entire multi-phase instruction (opcode + address + N data bytes spread
 * across many separate writes). So CS to the ENC424J600 must be a plain
 * GPIO pin toggled manually in software -- see SWC1_GPIO_* below. This is
 * the same trick already used by the working spi_ether_test2.c /
 * spi_sdcard*_test2.c SPI tests in this codebase.
 */

/* ---- GPIO (0xFE00 / 0xFE10) ---- */
#define SWC1_GPO         SWC1_REG(0xc000fe00) /* 3-bit LED outputs; shared with SPI sck/csn/mosi when SPI enabled */
#define SWC1_GPIO_IN     SWC1_REG(0xc000fe14) /* [3:0] read: actual pin value */
#define SWC1_GPIO_OUT    SWC1_REG(0xc000fe10) /* [3:0] output value */
#define SWC1_GPIO_ENABLE SWC1_REG(0xc000fe18) /* [3:0] 1 = output enable */

/* ---- Free Run Counter / timer (0xF800) ---- */
#define SWC1_FRC_LOW      SWC1_REG(0xc000f800)
#define SWC1_FRC_HIGH     SWC1_REG(0xc000f804)
#define SWC1_FRC_CMP_LOW  SWC1_REG(0xc000f808)
#define SWC1_FRC_CMP_HIGH SWC1_REG(0xc000f80c)
#define SWC1_FRC_CTRL     SWC1_REG(0xc000f810)
#define SWC1_FRC_CTRL_ENABLE (1u << 0)
#define SWC1_FRC_CTRL_RESET  (1u << 1) /* write-only, self clearing */
#define SWC1_FRC_CTRL_IRQ    (1u << 2)

/* ---- UART monitor / stdio (0xFC00) ---- */
#define SWC1_UART_TX       SWC1_REG(0xc000fc00)
#define SWC1_UART_TX_FULL  SWC1_REG(0xc000fc04)
#define SWC1_UART_BAUDDIV  SWC1_REG(0xc000fc08)
#define SWC1_UART_RX       SWC1_REG(0xc000fc0c)

#endif /* SWC1_IO_H */
