/*
 * BME280 UDP sender -- see sensor_send.h.
 *
 * Readings are kept as integers in the same fixed-point units as
 * sensor_sim.py's binary format (temp 0.01 degC, hum 0.01 %RH, press Pa =
 * 0.01 hPa), so there is no floating point anywhere: the text formats just
 * print value/100 "." value%100. The values come from the BME280 via
 * sensor/sensor.c (driver ported from pmodnic_test/sensor).
 */
#include <stdint.h>

#include "lwip/udp.h"
#include "lwip/pbuf.h"
#include "lwip/ip_addr.h"

#include "swc1_time.h"
#include "sensor_send.h"
#include "sensor.h"
#include "gpio_ctrl.h"
#include "ether_task.h"

int printf(const char *fmt, ...);

/* Destination: the PC running sensor_monitor.py. Defaults to the subnet
 * broadcast address, so the PC's IP doesn't need to be known in advance
 * (sensor_monitor.py binds 0.0.0.0 and receives broadcasts). Override at
 * build time, e.g. make SENSOR_DEST_IP=192.168.0.10 (see the Makefile). */
#ifndef SENSOR_DEST_IP
#define SENSOR_DEST_IP "192.168.0.255"
#endif
#ifndef SENSOR_DEST_PORT
#define SENSOR_DEST_PORT 5005
#endif
#ifndef SENSOR_SEND_INTERVAL_MS
#define SENSOR_SEND_INTERVAL_MS 1000
#endif

#define SENSOR_FORMAT_JSON 0
#define SENSOR_FORMAT_KV   1
#define SENSOR_FORMAT_CSV  2
#define SENSOR_FORMAT_BIN  3
#ifndef SENSOR_FORMAT
#define SENSOR_FORMAT SENSOR_FORMAT_JSON
#endif

/* Longest payload is json: {"temp": -xxxxx.xx, ...} -- well under 96. */
#define SENSOR_MAX_LEN 96

static struct udp_pcb *s_pcb;
static ip_addr_t s_dest;
static uint32_t s_last_cycles;
static u32_t s_seq;

/* Latest readings, fixed point (see top of file). */
static int32_t s_temp;
static int32_t s_hum;
static int32_t s_press;

/* BME280 set up and calibration read; retried from sensor_send_poll()
 * until it succeeds, so a sensor plugged in late still gets picked up. */
static int s_sensor_ok;

/* Alive LED on GPIO[3] (Arty H4, high = on), toggled once per send period:
 * it blinks while ether_task runs and freezes when it hangs. rgb_led[]
 * can't be used -- while SPI is enabled the FPGA routes {MOSI, spi_csn[0],
 * SCK} onto it, so rgb_led[1] flickers with every ENC424J600 access. */
static int s_led_on;

/*
 * Payload is built in a word array and written ONLY with aligned 4-byte
 * (`sw`) stores -- never `sb` -- because JASA1's QSPI PSRAM corrupts
 * single-byte writes that land 3 bytes before a 1024-byte page boundary
 * (see copy_pbuf_to_buf_words() in udp_echo.c for the full story). Each
 * byte is merged into its word read-modify-write, and the finished words
 * are copied into the pbuf whole (pbuf_alloc rounds the payload up to
 * MEM_ALIGNMENT=4, so the last partial word fits).
 */
static uint32_t s_buf[SENSOR_MAX_LEN / 4];
static u16_t s_len;

static void put_byte(uint8_t c)
{
    if (s_len >= SENSOR_MAX_LEN)
        return;
    u16_t w = s_len >> 2;
    int shift = (s_len & 3) * 8;
    uint32_t word = s_buf[w];
    word &= ~((uint32_t)0xff << shift);
    word |= (uint32_t)c << shift;
    s_buf[w] = word; /* one aligned sw */
    s_len++;
}

static __attribute__((unused)) void put_str(const char *s)
{
    while (*s)
        put_byte((uint8_t)*s++);
}

/* Most-significant digit first via a divisor, rather than a local digit
 * array -- the stack is PSRAM too, so a char tmp[] would mean `sb`s. */
static void put_udec(uint32_t v)
{
    uint32_t d = 1;
    while (v / d >= 10)
        d *= 10;
    do {
        put_byte((uint8_t)('0' + (v / d) % 10));
        d /= 10;
    } while (d > 0);
}

/* v in hundredths -> "[-]I.FF", like Python's "%.2f" % (v / 100). */
static __attribute__((unused)) void put_fixed2(int32_t v)
{
    uint32_t a;
    if (v < 0) {
        put_byte('-');
        a = (uint32_t)(-v);
    } else {
        a = (uint32_t)v;
    }
    put_udec(a / 100);
    put_byte('.');
    put_byte((uint8_t)('0' + (a / 10) % 10));
    put_byte((uint8_t)('0' + a % 10));
}

static __attribute__((unused)) void put_le32(int32_t v)
{
    uint32_t u = (uint32_t)v;
    put_byte((uint8_t)u);
    put_byte((uint8_t)(u >> 8));
    put_byte((uint8_t)(u >> 16));
    put_byte((uint8_t)(u >> 24));
}

static void encode(void)
{
    s_len = 0;
#if SENSOR_FORMAT == SENSOR_FORMAT_JSON
    put_str("{\"temp\": ");
    put_fixed2(s_temp);
    put_str(", \"hum\": ");
    put_fixed2(s_hum);
    put_str(", \"press\": ");
    put_fixed2(s_press);
    put_str("}");
#elif SENSOR_FORMAT == SENSOR_FORMAT_KV
    put_str("T=");
    put_fixed2(s_temp);
    put_str(",H=");
    put_fixed2(s_hum);
    put_str(",P=");
    put_fixed2(s_press);
#elif SENSOR_FORMAT == SENSOR_FORMAT_CSV
    put_fixed2(s_temp);
    put_byte(',');
    put_fixed2(s_hum);
    put_byte(',');
    put_fixed2(s_press);
#elif SENSOR_FORMAT == SENSOR_FORMAT_BIN
    put_le32(s_temp);
    put_le32(s_hum);
    put_le32(s_press);
#else
#error "SENSOR_FORMAT must be 0 (json), 1 (kv), 2 (csv) or 3 (bin)"
#endif
}

static int update_readings(void)
{
    if (!s_sensor_ok) {
        s_sensor_ok = sensor_init();
        if (!s_sensor_ok) {
            printf("sensor_send: BME280 init FAILED, retrying next interval\n");
            return 0;
        }
    }
    if (!sensor_read(&s_temp, &s_hum, &s_press)) {
        printf("sensor_send: BME280 read FAILED, skipping\n");
        return 0;
    }
    return 1;
}

static void send_one(void)
{
    if (!update_readings())
        return;
    encode();

    struct pbuf *p = pbuf_alloc(PBUF_TRANSPORT, s_len, PBUF_RAM);
    if (p == NULL) {
        printf("sensor_send: pbuf_alloc(%u) FAILED -- out of MEM_SIZE heap, skipping\n",
               (unsigned)s_len);
        return;
    }
    uint32_t *dst = (uint32_t *)p->payload;
    for (u16_t i = 0; i < (u16_t)((s_len + 3) >> 2); i++)
        dst[i] = s_buf[i]; /* aligned sw, see s_buf */

    err_t err = udp_sendto(s_pcb, p, &s_dest, SENSOR_DEST_PORT);
    pbuf_free(p);

    s_seq++;
    if (err != ERR_OK) {
        printf("sensor_send: #%u udp_sendto() FAILED, err=%d\n",
               (unsigned)s_seq, (int)err);
        return;
    }
    ether_task_progress++;
    /* Same console echo as sensor_sim.py: the payload itself, as hex for bin. */
    printf("sensor_send: #%u ", (unsigned)s_seq);
    for (u16_t i = 0; i < s_len; i++) {
        uint8_t c = (uint8_t)(s_buf[i >> 2] >> ((i & 3) * 8));
#if SENSOR_FORMAT == SENSOR_FORMAT_BIN
        printf("%02x", c);
#else
        printf("%c", c);
#endif
    }
    printf("\n");
}

void sensor_send_init(void)
{
    if (!ipaddr_aton(SENSOR_DEST_IP, &s_dest)) {
        printf("sensor_send_init: bad SENSOR_DEST_IP \"%s\"\n", SENSOR_DEST_IP);
        return;
    }
    s_pcb = udp_new();
    if (s_pcb == NULL) {
        printf("sensor_send_init: udp_new() returned NULL -- out of UDP PCBs/memory\n");
        return;
    }

    s_sensor_ok = sensor_init();
    if (!s_sensor_ok)
        printf("sensor_send_init: BME280 init FAILED -- check I2C wiring (GPIO1=SCL, GPIO2=SDA)\n");

    s_last_cycles = swc1_cycles();
    printf("sensor_send: sending to %s:%u every %u ms\n",
           SENSOR_DEST_IP, (unsigned)SENSOR_DEST_PORT,
           (unsigned)SENSOR_SEND_INTERVAL_MS);
}

void sensor_send_poll(void)
{
    if (s_pcb == NULL)
        return;
    /* Timed on the raw cycle counter rather than sys_now(): sys_now()
     * derives from the same 32-bit counter but jumps back to 0 each time
     * it wraps (~86 s at 50 MHz), whereas an unsigned cycle delta stays
     * correct across the wrap as long as we poll more often than that. */
    const uint32_t interval = SENSOR_SEND_INTERVAL_MS * (SWC1_CLK_HZ / 1000u);
    uint32_t now = swc1_cycles();
    if ((uint32_t)(now - s_last_cycles) < interval)
        return;
    /* Advance by whole intervals so the period doesn't drift with the
     * main loop's 50 ms tick; resync if we've fallen far behind. */
    s_last_cycles += interval;
    if ((uint32_t)(now - s_last_cycles) >= interval)
        s_last_cycles = now;
    s_led_on ^= 1;
    gpio_set_output(GPIO_LED, s_led_on ? GPIO_HIGH : GPIO_LOW);
    send_one();
}
