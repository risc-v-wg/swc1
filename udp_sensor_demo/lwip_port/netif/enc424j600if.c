/*
 * lwIP netif glue for the ENC424J600 driver -- the JASA1-specific
 * equivalent of the classic contrib/ports/.../ethernetif.c template.
 * Purely in-memory: frames pass through plain stack buffers and pbufs,
 * there is no filesystem or block-device notion anywhere in this path.
 */
#include <string.h>

#include "lwip/opt.h"
#include "lwip/def.h"
#include "lwip/pbuf.h"
#include "lwip/stats.h"
#include "lwip/etharp.h"
#include "netif/ethernet.h"

#include "enc424j600if.h"
#include "../drivers/enc424j600.h"

int printf(const char *fmt, ...);

#define IFNAME0 'e'
#define IFNAME1 'n'

/*
 * WORKAROUND (both functions below): JASA1's QSPI PSRAM corrupts
 * single-byte (`sb`) writes landing 3 bytes before a 1024-byte page
 * boundary (confirmed on real hardware, see cfile/qspi_mem_stress_test.c
 * and project notes). `frame` and pbuf payloads are equally
 * QSPI-PSRAM-resident, so both directions of the plain-array<->pbuf copy
 * need the same treatment: accumulate 4 bytes purely in registers, one
 * aligned uint32_t store per 4 bytes, instead of lwIP's stock
 * pbuf_take()/pbuf_copy_partial() (byte-at-a-time memcpy).
 */

/* plain array -> pbuf (single non-chained pbuf, true for pbuf_alloc(...,
 * PBUF_RAM)); replaces pbuf_take(). */
static void copy_to_pbuf_words(struct pbuf *p, const uint8_t *src, u16_t len)
{
    uint8_t *dst = (uint8_t *)p->payload;
    uint32_t word = 0;
    int shift = 0;
    u16_t dst_idx = 0;

    for (u16_t i = 0; i < len; i++) {
        word |= (uint32_t)src[i] << shift;
        shift += 8;
        if (shift == 32) {
            *(uint32_t *)(dst + dst_idx) = word; /* one aligned sw */
            dst_idx += 4;
            word = 0;
            shift = 0;
        }
    }
    while (shift > 0) {
        dst[dst_idx++] = (uint8_t)word; /* 0-3 byte tail: unavoidable sb */
        word >>= 8;
        shift -= 8;
    }
}

/* pbuf (possibly chained) -> plain array; replaces pbuf_copy_partial(). */
static void copy_from_pbuf_words(struct pbuf *p, uint8_t *dst, u16_t total_len)
{
    uint32_t word = 0;
    int shift = 0;
    u16_t dst_idx = 0;
    u16_t remaining = total_len;

    for (struct pbuf *q = p; q != NULL && remaining > 0; q = q->next) {
        const uint8_t *src = (const uint8_t *)q->payload;
        u16_t chunk = q->len;
        if (chunk > remaining)
            chunk = remaining;
        for (u16_t i = 0; i < chunk; i++) {
            word |= (uint32_t)src[i] << shift;
            shift += 8;
            if (shift == 32) {
                *(uint32_t *)(dst + dst_idx) = word; /* one aligned sw */
                dst_idx += 4;
                word = 0;
                shift = 0;
            }
        }
        remaining -= chunk;
    }
    while (shift > 0) {
        dst[dst_idx++] = (uint8_t)word; /* 0-3 byte tail: unavoidable sb */
        word >>= 8;
        shift -= 8;
    }
}

static err_t low_level_output(struct netif *netif, struct pbuf *p)
{
    /* aligned(4): copy_from_pbuf_words() below does aligned uint32_t
     * writes into this buffer (QSPI-PSRAM page-boundary workaround). */
    uint8_t frame[ENC424J600_MAX_FRAME] __attribute__((aligned(4)));

    if (p->tot_len > sizeof(frame))
        return ERR_BUF;

    copy_from_pbuf_words(p, frame, p->tot_len);

    if (enc424j600_send(frame, (int)p->tot_len) != 0)
        return ERR_IF;

    return ERR_OK;
}

static struct pbuf *low_level_input(void)
{
    /* aligned(4): enc424j600_recv() -> swc1_spi_xfer() does aligned
     * uint32_t writes into this buffer (QSPI-PSRAM page-boundary
     * workaround, see swc1_spi.c). */
    uint8_t frame[ENC424J600_MAX_FRAME] __attribute__((aligned(4)));

    int len = enc424j600_recv(frame, sizeof(frame));
    if (len <= 0)
        return NULL;

    struct pbuf *p = pbuf_alloc(PBUF_RAW, (u16_t)len, PBUF_RAM);
    if (p == NULL) {
        printf("enc424j600if: RX pbuf_alloc(%d) FAILED -- out of MEM_SIZE heap, dropping\n", len);
        return NULL; /* out of memory: drop the frame */
    }

    copy_to_pbuf_words(p, frame, (u16_t)len);
    return p;
}

err_t enc424j600if_init(struct netif *netif)
{
    netif->linkoutput = low_level_output;
    netif->output = etharp_output;
    netif->mtu = 1500;
    netif->flags = NETIF_FLAG_BROADCAST | NETIF_FLAG_ETHARP | NETIF_FLAG_ETHERNET;
    netif->name[0] = IFNAME0;
    netif->name[1] = IFNAME1;
    netif->hwaddr_len = ETH_HWADDR_LEN;

    if (enc424j600_init() != 0)
        return ERR_IF;

    enc424j600_get_hwaddr(netif->hwaddr);

    return ERR_OK;
}

void enc424j600if_poll(struct netif *netif)
{
    if (enc424j600_link_up()) {
        if (!netif_is_link_up(netif))
            netif_set_link_up(netif);
    } else {
        if (netif_is_link_up(netif))
            netif_set_link_down(netif);
    }

    struct pbuf *p;
    while ((p = low_level_input()) != NULL) {
        if (netif->input(p, netif) != ERR_OK)
            pbuf_free(p);
    }
}
