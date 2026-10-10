/*
 * Tiny printf() over the JASA1 UART, for drivers/enc424j600.c's debug
 * logging and ether_task.c's own status prints -- there is no libc under
 * micro T-Kernel's -nostdlib build to provide a real one.
 *
 * Supports exactly the conversions actually used by this codebase's calls:
 * %s %c %d %u %x (with an optional zero-padded width, e.g. %04x, %02x).
 * Anything else is not needed here and is not supported.
 */
#include <stdarg.h>
#include "swc1_io.h"		/* SWC1_UART_TX / SWC1_UART_TX_FULL, via -I to lwip_port/drivers */

static void out_char(char c)
{
    while (SWC1_UART_TX_FULL)
        ;
    SWC1_UART_TX = (unsigned int)(unsigned char)c;
}

static void out_str(const char *s)
{
    while (*s)
        out_char(*s++);
}

static void out_udec(unsigned int v)
{
    char buf[10];
    int n = 0;
    if (v == 0) {
        out_char('0');
        return;
    }
    while (v > 0) {
        buf[n++] = (char)('0' + v % 10);
        v /= 10;
    }
    while (n-- > 0)
        out_char(buf[n]);
}

static void out_hex(unsigned int v, int width, int zero_pad)
{
    static const char digits[] = "0123456789abcdef";
    char buf[8];
    int n = 0;
    do {
        buf[n++] = digits[v & 0xf];
        v >>= 4;
    } while (v > 0);
    while (n < width)
        buf[n++] = zero_pad ? '0' : ' ';
    while (n-- > 0)
        out_char(buf[n]);
}

int printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);

    for (; *fmt; fmt++) {
        if (*fmt != '%') {
            out_char(*fmt);
            continue;
        }
        fmt++;

        int zero_pad = 0;
        if (*fmt == '0') {
            zero_pad = 1;
            fmt++;
        }
        int width = 0;
        while (*fmt >= '0' && *fmt <= '9') {
            width = width * 10 + (*fmt - '0');
            fmt++;
        }

        switch (*fmt) {
        case 'd': {
            int v = va_arg(ap, int);
            if (v < 0) {
                out_char('-');
                v = -v;
            }
            out_udec((unsigned int)v);
            break;
        }
        case 'u':
            out_udec(va_arg(ap, unsigned int));
            break;
        case 'x':
            out_hex(va_arg(ap, unsigned int), width, zero_pad);
            break;
        case 's':
            out_str(va_arg(ap, const char *));
            break;
        case 'c':
            out_char((char)va_arg(ap, int));
            break;
        case '%':
            out_char('%');
            break;
        default:
            out_char('%');
            out_char(*fmt);
            break;
        }
    }

    va_end(ap);
    return 0;
}
