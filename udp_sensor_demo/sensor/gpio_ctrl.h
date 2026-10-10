#ifndef _GPIO_CTRL_H
#define _GPIO_CTRL_H

#include <stdint.h>

/* GPIO -- GPIO[0] is the ENC424J600 SPI chip select (swc1_spi.c) */
#define GPIO_I2C_SCL      1
#define GPIO_I2C_SDA      2
#define GPIO_LED          3     /* alive LED (sensor_send.c); was GPIO_DUMMY */

/* type */
typedef enum gpio_level { GPIO_LOW = 0, GPIO_HIGH, GPIO_HIZ } gpio_level_t;


/* function */
void gpio_init(void);
void gpio_set_output(int gpio, gpio_level_t level);
uint32_t gpio_get_input(int gpio);

#endif /* _GPIO_CTRL_H */
