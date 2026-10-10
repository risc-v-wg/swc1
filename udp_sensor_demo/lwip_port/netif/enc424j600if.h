#ifndef ENC424J600IF_H
#define ENC424J600IF_H

#include "lwip/netif.h"

/* netif->init callback: bring up the ENC424J600, read its factory MAC
 * address into netif->hwaddr, and wire up output/linkoutput. Pass this to
 * netif_add(). */
err_t enc424j600if_init(struct netif *netif);

/* Call this every iteration of the main loop. Tracks link up/down and hands
 * every received frame to netif->input() (ethernet_input). Never blocks. */
void enc424j600if_poll(struct netif *netif);

#endif /* ENC424J600IF_H */
