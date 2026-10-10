/*
 * ENC424J600/624J600 SPI opcodes and unbanked SFR addresses.
 * Source: Microchip DS39935B, Table 3-1 (SFR map) and Table 4-1 (SPI
 * instruction set).
 *
 * We exclusively use the *unbanked* opcodes (RCRU/WCRU/BFSU/BFCU), which
 * take a full 8-bit address that already selects the right bank -- no
 * B0SEL/B1SEL/... bank-select opcode is ever needed (confirmed: the
 * already-working spi_ether_test2.c reads EIDLED this way with no prior
 * bank select).
 */
#ifndef ENC424J600_REGS_H
#define ENC424J600_REGS_H

/* ---- single/two-byte opcodes ---- */
#define OP_B0SEL      0xC0
#define OP_B1SEL      0xC2
#define OP_B2SEL      0xC4
#define OP_B3SEL      0xC6
#define OP_SETETHRST  0xCA
#define OP_FCDISABLE  0xE0
#define OP_FCSINGLE   0xE2
#define OP_FCMULTIPLE 0xE4
#define OP_FCCLEAR    0xE6
#define OP_SETPKTDEC  0xCC
#define OP_DMASTOP    0xD2
#define OP_DMACKSUM   0xD8
#define OP_DMACKSUMS  0xDA
#define OP_DMACOPY    0xDC
#define OP_DMACOPYS   0xDE
#define OP_SETTXRTS   0xD4
#define OP_ENABLERX   0xE8
#define OP_DISABLERX  0xEA
#define OP_SETEIE     0xEC
#define OP_CLREIE     0xEE
#define OP_RBSEL      0xC8

/* ---- pointer read/write (3-byte) opcodes ---- */
#define OP_WGPRDPT    0x60
#define OP_RGPRDPT    0x62
#define OP_WRXRDPT    0x64
#define OP_RRXRDPT    0x66
#define OP_WUDARDPT   0x68
#define OP_RUDARDPT   0x6A
#define OP_WGPWRPT    0x6C
#define OP_RGPWRPT    0x6E
#define OP_WRXWRPT    0x70
#define OP_RRXWRPT    0x72
#define OP_WUDAWRPT   0x74
#define OP_RUDAWRPT   0x76

/* ---- unbanked control-register / bit-field opcodes ---- */
#define OP_RCRU       0x20  /* + addr byte, + 2 data bytes returned */
#define OP_WCRU       0x22  /* + addr byte, + 2 data bytes written  */
#define OP_BFSU       0x24  /* + addr byte, + 2 data bytes (set mask)   */
#define OP_BFCU       0x26  /* + addr byte, + 2 data bytes (clear mask) */

/* ---- SRAM buffer N-byte opcodes (stream via EGPRDPT/EGPWRPT/ERXRDPT/...) */
#define OP_RGPDATA    0x28
#define OP_WGPDATA    0x2A
#define OP_RRXDATA    0x2C
#define OP_WRXDATA    0x2E
#define OP_RUDADATA   0x30
#define OP_WUDADATA   0x32

/* ---- unbanked SFR addresses (low byte; high byte is addr+1) ---- */
#define REG_ETXST     0x00
#define REG_ETXLEN    0x02
#define REG_ERXST     0x04
#define REG_ERXTAIL   0x06
#define REG_ERXHEAD   0x08
#define REG_EDMAST    0x0A
#define REG_EDMALEN   0x0C
#define REG_EDMADST   0x0E
#define REG_EDMACS    0x10
#define REG_ETXSTAT   0x12
#define REG_ETXWIRE   0x14
#define REG_EUDAST    0x16
#define REG_EUDAND    0x18
#define REG_ESTAT     0x1A
#define REG_EIR       0x1C
#define REG_ECON1     0x1E

#define REG_EHT1      0x20
#define REG_EHT2      0x22
#define REG_EHT3      0x24
#define REG_EHT4      0x26
#define REG_EPMM1     0x28
#define REG_EPMM2     0x2A
#define REG_EPMM3     0x2C
#define REG_EPMM4     0x2E
#define REG_EPMCS     0x30
#define REG_EPMO      0x32
#define REG_ERXFCON   0x34

#define REG_MACON1    0x40
#define REG_MACON2    0x42
#define REG_MABBIPG   0x44
#define REG_MAIPG     0x46
#define REG_MACLCON   0x48
#define REG_MAMXFL    0x4A
#define REG_MICMD     0x52
#define REG_MIREGADR  0x54

#define REG_MAADR3    0x60
#define REG_MAADR2    0x62
#define REG_MAADR1    0x64
#define REG_MIWR      0x66
#define REG_MIRD      0x68
#define REG_MISTAT    0x6A
#define REG_EPAUS     0x6C
#define REG_ECON2     0x6E
#define REG_ERXWM     0x70
#define REG_EIE       0x72
#define REG_EIDLED    0x74

#define REG_EGPDATA   0x80
#define REG_ERXDATA   0x82
#define REG_EUDADATA  0x84
#define REG_EGPRDPT   0x86
#define REG_EGPWRPT   0x88
#define REG_ERXRDPT   0x8A
#define REG_ERXWRPT   0x8C
#define REG_EUDARDPT  0x8E
#define REG_EUDAWRPT  0x90

/* ---- ERXFCON bits (Register 10-1, DS39935B page 96) ---- */
#define ERXFCON_HTEN     (1u << 15)
#define ERXFCON_MPEN     (1u << 14)
#define ERXFCON_NOTPM    (1u << 12)
#define ERXFCON_CRCEEN   (1u << 7)
#define ERXFCON_CRCEN    (1u << 6)
#define ERXFCON_RUNTEEN  (1u << 5)
#define ERXFCON_RUNTEN   (1u << 4)
#define ERXFCON_UCEN     (1u << 3)
#define ERXFCON_NOTMEEN  (1u << 2)
#define ERXFCON_MCEN     (1u << 1)
#define ERXFCON_BCEN     (1u << 0)

/* ---- PHCON1 bits (Register 12-1, DS39935B page 110) ---- */
#define PHCON1_ANEN    (1u << 12)
#define PHCON1_RENEG   (1u << 9) /* restart auto-negotiation; self-clears in hardware */

/* ---- PHSTAT1 bits (Register 12-2, DS39935B page 111) ---- */
#define PHSTAT1_ANDONE   (1u << 5)
#define PHSTAT1_LRFAULT  (1u << 4)
#define PHSTAT1_LLSTAT   (1u << 2) /* latches low if link dropped even briefly since last read */

/* ---- PHSTAT3 bits (Register 12-4, DS39935B page 112) ---- */
#define PHSTAT3_SPDDPX_MASK (0x7u << 2)
#define PHSTAT3_SPDDPX_SHIFT 2
/* SPDDPX<2:0> values: 110=100Mbps full, 101=10Mbps full, 010=100Mbps half,
 * 001=10Mbps half (000/011/100/111 reserved) -- this is the PHY's own,
 * independently-latched view of what actually got negotiated, as opposed
 * to ESTAT_PHYDPX (used at link-up to set MACON2) which is a single bit
 * read once and could in principle be sampled mid-negotiation. */

/* ---- ESTAT bits ---- */
#define ESTAT_INT     (1u << 15)
#define ESTAT_FCIDLE  (1u << 14)
#define ESTAT_RXBUSY  (1u << 13)
#define ESTAT_CLKRDY  (1u << 12)
#define ESTAT_PHYDPX  (1u << 10)
#define ESTAT_PHYLNK  (1u << 8)
#define ESTAT_PKTCNT_MASK 0x00FFu

/* ---- EIR bits ---- */
#define EIR_LINKIF    (1u << 11)
#define EIR_PKTIF     (1u << 6)
#define EIR_TXIF      (1u << 3)
#define EIR_TXABTIF   (1u << 2)
#define EIR_RXABTIF   (1u << 1)
#define EIR_PCFULIF   (1u << 0)

/* ---- ECON1 bits ---- */
#define ECON1_PKTDEC  (1u << 8)
#define ECON1_TXRTS   (1u << 1)
#define ECON1_RXEN    (1u << 0)

/* ---- ECON2 bits ---- */
#define ECON2_ETHEN   (1u << 15)
#define ECON2_TXMAC   (1u << 13)
#define ECON2_TXRST   (1u << 6)
#define ECON2_RXRST   (1u << 5)
#define ECON2_ETHRST  (1u << 4)

/* ---- MACON2 bits ---- */
#define MACON2_FULDPX (1u << 0)

/* ---- MICMD bits ---- */
#define MICMD_MIISCAN (1u << 1)
#define MICMD_MIIRD   (1u << 0)

/* ---- MISTAT bits ---- */
#define MISTAT_BUSY   (1u << 0)

/* ---- PHY registers (accessed indirectly via MIREGADR/MICMD/MIRD/MIWR) ---- */
#define PHY_PHCON1    0x00
#define PHY_PHSTAT1   0x01
#define PHY_PHANA     0x04
#define PHY_PHANLPA   0x05
#define PHY_PHANE     0x06
#define PHY_PHCON2    0x11
#define PHY_PHSTAT2   0x1B
#define PHY_PHSTAT3   0x1F

#define MIREGADR_RESERVED_BIT8 (1u << 8) /* must always be set, per datasheet 3.3.1/3.3.2 */

#endif /* ENC424J600_REGS_H */
