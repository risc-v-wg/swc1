#include <stddef.h>
#include <stdio.h>
#include "enc424j600.h"
#include "enc424j600_regs.h"
#include "swc1_spi.h"
#include "swc1_time.h"

/*
 * SRAM buffer layout inside the ENC424J600's 24KB packet buffer (addresses
 * 0x0000-0x5FFF). We always stage outgoing frames at a fixed address and
 * wait for transmission to finish before reusing it (enc424j600_send() is
 * synchronous), so no wrap handling is needed for TX.
 */
#define TX_BUF_START 0x0000u
#define RX_BUF_START 0x0800u
//#define RX_BUF_END   0x5FFEu /* last even address of physical SRAM */
#define RX_BUF_END   0x5FFEu /* last even address of physical SRAM */

/* Set to 1 to re-enable the per-packet RX/TX hex dumps and the TX
 * write-verify SPI readback below (see enc424j600_recv()/enc424j600_send()).
 * They run unconditionally on every single packet -- a full UART hex dump
 * each way plus, for TX, an extra full-frame SPI readback -- which made UDP
 * loopback round trips unusably slow. Kept behind this flag rather than
 * deleted since they're genuinely useful when bringing up new hardware. */
#ifndef ENC424J600_DEBUG_DUMP
#define ENC424J600_DEBUG_DUMP 0
#endif

/* SCK period = 2*(div+1) system clocks. At div=200, SCK was 124kHz -- not
 * fast, but JASA1 takes ~70 clocks per instruction, so software overhead
 * already dominates and slowing SCK further costs nothing measurable.
 * Lowered further (200 -> 400) as a straightforward margin increase on top
 * of the swc1_spi_xfer() burst-size/FIFO-depth fix (see swc1_spi.c). */
//#define SPI_SCKDIV_INITIAL 400u
#define SPI_SCKDIV_INITIAL 10u

static uint16_t s_next_pkt_ptr;
static int s_link_was_up;

static uint16_t rcru(uint8_t addr)
{
    uint8_t tx[4] = { OP_RCRU, addr, 0xFF, 0xFF };
    uint8_t rx[4] __attribute__((aligned(4)));
    swc1_spi_select(1);
    swc1_spi_xfer(tx, rx, 4);
    swc1_spi_select(0);
    return (uint16_t)rx[2] | ((uint16_t)rx[3] << 8);
}

static void wcru(uint8_t addr, uint16_t val)
{
    uint8_t tx[4] = { OP_WCRU, addr, (uint8_t)(val & 0xFF), (uint8_t)(val >> 8) };
    swc1_spi_select(1);
    swc1_spi_xfer(tx, NULL, 4);
    swc1_spi_select(0);
}

static void bfsu(uint8_t addr, uint16_t mask)
{
    uint8_t tx[4] = { OP_BFSU, addr, (uint8_t)(mask & 0xFF), (uint8_t)(mask >> 8) };
    swc1_spi_select(1);
    swc1_spi_xfer(tx, NULL, 4);
    swc1_spi_select(0);
}

static void bfcu(uint8_t addr, uint16_t mask)
{
    uint8_t tx[4] = { OP_BFCU, addr, (uint8_t)(mask & 0xFF), (uint8_t)(mask >> 8) };
    swc1_spi_select(1);
    swc1_spi_xfer(tx, NULL, 4);
    swc1_spi_select(0);
}

static void single_cmd(uint8_t opcode)
{
    swc1_spi_select(1);
    swc1_spi_xfer(&opcode, NULL, 1);
    swc1_spi_select(0);
}

/* Not currently called (only phy_write() is, to set PHANA at init) -- kept
 * available for future PHY status introspection (e.g. reading back
 * PHSTAT1/PHANLPA for diagnostics). */
static uint16_t __attribute__((unused)) phy_read(uint8_t phyaddr)
{
    wcru(REG_MIREGADR, phyaddr | MIREGADR_RESERVED_BIT8);
    wcru(REG_MICMD, MICMD_MIIRD);
    swc1_delay_us(30); /* datasheet: wait 25.6us before polling BUSY */
    int guard = 1000;
    while ((rcru(REG_MISTAT) & MISTAT_BUSY) && guard-- > 0) {
        /* MISTAT.BUSY is a real ENC424J600 register bit (not one of
         * JASA1's buggy local FIFO flags), safe to poll. */
    }
    wcru(REG_MICMD, 0);
    return rcru(REG_MIRD);
}

static void phy_write(uint8_t phyaddr, uint16_t val)
{
    wcru(REG_MIREGADR, phyaddr | MIREGADR_RESERVED_BIT8);
    wcru(REG_MIWR, val); /* WCRU writes low byte then high byte, as required */
    swc1_delay_us(30);
    int guard = 1000;
    while ((rcru(REG_MISTAT) & MISTAT_BUSY) && guard-- > 0) {
    }
}

int enc424j600_init(void)
{
    swc1_spi_init(SPI_SCKDIV_INITIAL);

    /* --- 8.1 Reset (write-verify-reset-reverify) --- */
    int ok = 0;
    for (int tries = 0; tries < 8 && !ok; tries++) {
        wcru(REG_EUDAST, 0x1234);
        if (rcru(REG_EUDAST) == 0x1234)
            ok = 1;
    }
    if (!ok)
        return -1; /* SPI wiring/clocking problem -- chip never answered */

    ok = 0;
    for (int tries = 0; tries < 10000 && !ok; tries++) {
        if (rcru(REG_ESTAT) & ESTAT_CLKRDY)
            ok = 1;
    }
    if (!ok)
        return -1;

    single_cmd(OP_SETETHRST);
    swc1_delay_us(30); /* >= 25us */

    ok = 0;
    for (int tries = 0; tries < 10 && !ok; tries++) {
        if (rcru(REG_EUDAST) == 0x0000)
            ok = 1;
    }
    if (!ok)
        return -1;

    swc1_delay_us(300); /* >= 256us for PHY registers/status to come up */

    /* --- 8.3 Receive buffer --- */
    wcru(REG_ERXST, RX_BUF_START);
    s_next_pkt_ptr = RX_BUF_START;
    wcru(REG_ERXTAIL, RX_BUF_END);

    /* --- 8.5 Receive filters --- */
    /* Leave ERXFCON at its power-on default (unicast + broadcast + CRC/runt
     * checks enabled) -- exactly what a normal IP host wants. */

    /* --- 8.6 MAC initialization --- */
    /* Do NOT set ECON2.TXMAC: lwIP already writes a complete, standard
     * Ethernet frame (destination + OUR source MAC + ethertype + payload)
     * into the TX buffer for every packet. TXMAC would make the chip insert
     * a *second* 6-byte source address right after the destination and then
     * keep reading "the remaining bytes" from memory starting right where
     * lwIP's own source MAC sits -- corrupting/misaligning every frame on
     * the wire. (Confirmed on real hardware: TX reported 42 bytes -- a
     * completely normal ARP-reply size from lwIP's side -- yet the Pi never
     * saw a valid reply and reported "Destination Host Unreachable".) */
    wcru(REG_MAMXFL, ENC424J600_MAX_FRAME);

    /* --- 8.7 PHY initialization --- */
    phy_write(PHY_PHANA, 0x05E1); /* advertise flow control + 10/100 half/full, per datasheet 8.7 */

    bfsu(REG_ECON1, ECON1_RXEN);

    s_link_was_up = 0;
    return 0;
}

void enc424j600_get_hwaddr(uint8_t hwaddr[6])
{
    /* Per datasheet Table 3-7 (verified against the actual typeset table,
     * not just the reflowed text extraction, after this exact swap caused
     * a real-hardware bug): each MAADRn register's HIGH byte holds the
     * *lower*-numbered MAC byte and the LOW byte holds the *higher*-numbered
     * one -- MAADR1 high=byte2/low=byte1, MAADR2 high=byte4/low=byte3,
     * MAADR3 high=byte6/low=byte5. Getting this backwards silently produces
     * a MAC address with the multicast/group bit set in byte1 whenever the
     * real byte2 happens to be odd, which is an IEEE 802.3 violation as a
     * source address -- frames transmitted with it are physically clean
     * (valid CRC, no collisions) but get silently dropped by any compliant
     * receiver (confirmed: matched a real Raspberry Pi's rx_dropped counter
     * incrementing with zero rx_crc_errors/rx_frame_errors). */
    uint16_t a1 = rcru(REG_MAADR1); /* high=byte2, low=byte1 */
    uint16_t a2 = rcru(REG_MAADR2); /* high=byte4, low=byte3 */
    uint16_t a3 = rcru(REG_MAADR3); /* high=byte6, low=byte5 */

    hwaddr[0] = (uint8_t)(a1 & 0xFF);
    hwaddr[1] = (uint8_t)(a1 >> 8);
    hwaddr[2] = (uint8_t)(a2 & 0xFF);
    hwaddr[3] = (uint8_t)(a2 >> 8);
    hwaddr[4] = (uint8_t)(a3 & 0xFF);
    hwaddr[5] = (uint8_t)(a3 >> 8);
}

int enc424j600_link_up(void)
{
    uint16_t estat = rcru(REG_ESTAT);
    int up = (estat & ESTAT_PHYLNK) != 0;

    if (up && !s_link_was_up) {
        /* 8.9 "After Link Establishment": MAC duplex must be resynced to
         * whatever the PHY actually negotiated. */
        int full_duplex = (estat & ESTAT_PHYDPX) != 0;
        if (full_duplex) {
            bfsu(REG_MACON2, MACON2_FULDPX);
            wcru(REG_MABBIPG, 0x15);
        } else {
            bfcu(REG_MACON2, MACON2_FULDPX);
            wcru(REG_MABBIPG, 0x12);
        }
        printf("enc424j600: link up, duplex=%s MACON2=0x%04x MABBIPG=0x%04x\n",
               full_duplex ? "FULL" : "HALF",
               (unsigned)rcru(REG_MACON2), (unsigned)rcru(REG_MABBIPG));
    }
    s_link_was_up = up;
    return up;
}

/*
 * DIAGNOSTIC: the ENC424J600 itself flags RX overrun/abort conditions in
 * EIR -- distinct from (and upstream of) JASA1's own SPI-level issues.
 * RXABTIF means the chip's own 24KB packet buffer didn't have room to
 * store an incoming frame (shrinking RX_BUF_START/RX_BUF_END makes this
 * more likely); PCFULIF means ESTAT.PKTCNT (max 255 queued packets)
 * overflowed. If either fires, that's the *chip* silently dropping frames
 * before software ever sees them -- separate from any JASA1 SPI-level
 * corruption. Bits are cleared (BFCU) after being reported so each event
 * is logged exactly once. */
static void check_eir_errors(void)
{
    uint16_t eir = rcru(REG_EIR);
    uint16_t bad = eir & (EIR_RXABTIF | EIR_PCFULIF);
    if (bad) {
        printf("enc424j600: EIR=0x%04x%s%s\n", (unsigned)eir,
               (bad & EIR_RXABTIF) ? " RXABTIF(RX overrun -- chip's own RX buffer full)" : "",
               (bad & EIR_PCFULIF) ? " PCFULIF(packet counter full)" : "");
        bfcu(REG_EIR, bad);
    }
}

int enc424j600_recv(uint8_t *buf, int buflen)
{
    check_eir_errors();

    uint16_t estat = rcru(REG_ESTAT);
    if ((estat & ESTAT_PKTCNT_MASK) == 0)
        return 0;

    wcru(REG_ERXRDPT, s_next_pkt_ptr);

    uint8_t cmd = OP_RRXDATA;
    /* aligned(4): swc1_spi_xfer() now does aligned uint32_t writes into
     * its rx buffer (QSPI-PSRAM page-boundary workaround, see swc1_spi.c) */
    uint8_t hdr[8] __attribute__((aligned(4))); /* [0:1]=next-packet ptr, [2:3]=byte count, [4:7]=status flags */

    swc1_spi_select(1);
    swc1_spi_xfer(&cmd, NULL, 1);
    swc1_spi_xfer(NULL, hdr, 8);

    uint16_t new_next_ptr = (uint16_t)hdr[0] | ((uint16_t)hdr[1] << 8);
    uint16_t byte_count = (uint16_t)hdr[2] | ((uint16_t)hdr[3] << 8);
    int received_ok = (hdr[4] & 0x80) != 0; /* RSV bit 23 */

    int ret;
    if (!received_ok || byte_count <= 4) {
        ret = 0; /* malformed/filtered frame: drop silently */
        printf("enc424j600: RX drop (received_ok=%d byte_count=%u)\n",
               received_ok, (unsigned)byte_count);
    } else if (byte_count > (uint16_t)buflen) {
        ret = -1; /* caller's buffer too small: drop */
        printf("enc424j600: RX drop, too big (byte_count=%u buflen=%d)\n",
               (unsigned)byte_count, buflen);
    } else {
        swc1_spi_xfer(NULL, buf, byte_count);
        ret = (int)byte_count - 4; /* strip the 4-byte hardware CRC/FCS */
#if ENC424J600_DEBUG_DUMP
        printf("enc424j600: RX raw frame (%d bytes):", ret);
        for (int i = 0; i < ret; i++) {
            if (i % 16 == 0)
                printf("\n  %04x:", i);
            printf(" %02x", buf[i]);
        }
        printf("\n");
#endif
    }
    swc1_spi_select(0);

    s_next_pkt_ptr = new_next_ptr;
    uint16_t new_tail = (s_next_pkt_ptr == RX_BUF_START) ? RX_BUF_END : (uint16_t)(s_next_pkt_ptr - 2);
    wcru(REG_ERXTAIL, new_tail);
    bfsu(REG_ECON1, ECON1_PKTDEC);

    return ret;
}

int enc424j600_send(const uint8_t *buf, int len)
{
    if (len <= 0 || len > ENC424J600_MAX_FRAME)
        return -1;

#if ENC424J600_DEBUG_DUMP
    /* TEMPORARY DIAGNOSTIC: dump the frame lwIP handed us, so we can
     * confirm by eye that it's really a sane ARP/Ethernet frame (right
     * dest/src MAC, right ethertype) and not, say, garbage or a frame
     * addressed to the wrong place. */
    printf("enc424j600: TX raw frame (%d bytes):", len);
    for (int i = 0; i < len; i++) {
        if (i % 16 == 0)
            printf("\n  %04x:", i);
        printf(" %02x", buf[i]);
    }
    printf("\n");
#endif

    wcru(REG_EGPWRPT, TX_BUF_START);

    uint8_t cmd = OP_WGPDATA;
    swc1_spi_select(1);
    swc1_spi_xfer(&cmd, NULL, 1);
    swc1_spi_xfer(buf, NULL, len);
    swc1_spi_select(0);

#if ENC424J600_DEBUG_DUMP
    /* TEMPORARY DIAGNOSTIC: read back what we just wrote and compare, to
     * check whether the SPI write itself is corrupting data (the chip will
     * report a "clean" transmit either way, since it just CRCs whatever
     * ended up in its buffer -- this check is independent of that). */
    {
        uint8_t verify_cmd = OP_RGPDATA;
        uint8_t verify_buf[ENC424J600_MAX_FRAME];
        wcru(REG_EGPRDPT, TX_BUF_START);
        swc1_spi_select(1);
        swc1_spi_xfer(&verify_cmd, NULL, 1);
        swc1_spi_xfer(NULL, verify_buf, len);
        swc1_spi_select(0);

        int mismatch = -1;
        for (int i = 0; i < len; i++) {
            if (verify_buf[i] != buf[i]) {
                mismatch = i;
                break;
            }
        }
        if (mismatch >= 0) {
            printf("enc424j600: TX WRITE VERIFY MISMATCH at byte %d: wrote 0x%02x read 0x%02x\n",
                   mismatch, buf[mismatch], verify_buf[mismatch]);
        } else {
            printf("enc424j600: TX write verify OK (%d bytes match)\n", len);
        }
    }
#endif

    wcru(REG_ETXST, TX_BUF_START);
    wcru(REG_ETXLEN, (uint16_t)len);
    bfsu(REG_ECON1, ECON1_TXRTS);

    int guard = 200000;
    int start_guard = guard;
    while ((rcru(REG_ECON1) & ECON1_TXRTS) && guard-- > 0) {
        /* ECON1.TXRTS is a real ENC424J600 register bit; hardware clears
         * it when the transmit completes (or aborts). */
    }
    int waited = start_guard - guard;
    if (guard <= 0) {
        printf("enc424j600: TX %d bytes -- TXRTS never cleared (SPI/PHY stuck?)\n", len);
        return -1;
    }

    uint16_t txstat = rcru(REG_ETXSTAT);
    /* ETXSTAT<10>=LATECOL, <9>=MAXCOL, <8>=EXDEFER, <7>=DEFER, <3:0>=COLCNT */
#if ENC424J600_DEBUG_DUMP
    printf("enc424j600: TX %d bytes, waited %d polls, ETXSTAT=0x%04x (DEFER=%d COLCNT=%d)\n",
           len, waited, (unsigned)txstat,
           (txstat >> 7) & 1, txstat & 0xF);
#else
    (void)waited;
#endif
    if (txstat & 0x0700u) { /* LATECOL | MAXCOL | EXDEFER (half-duplex only) */
        printf("enc424j600: TX %d bytes -- ETXSTAT error 0x%04x\n", len, (unsigned)txstat);
        return -1;
    }

    return 0;
}
