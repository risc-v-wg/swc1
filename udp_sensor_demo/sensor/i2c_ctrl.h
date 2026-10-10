#ifndef _I2C_CTRL_H
#define _I2C_CTRL_H

#include <stdint.h>


/* I2C_DELAY_US is the busy-wait between SCL/SDA edges (half an SCL
 * period). pmodnic_test used 1 ms, which is known to work with the Pmod
 * wiring; override with -DI2C_DELAY_US=<us> to go faster. */
#ifndef I2C_DELAY_US
#define I2C_DELAY_US    1000
#endif


/* function */
void i2c_init();
int i2c_write(uint8_t slave_address, const uint8_t * wbuf, int count);
int i2c_read(uint8_t slave_address, uint8_t * rbuf, int count);

#endif /* _I2C_CTRL_H */
