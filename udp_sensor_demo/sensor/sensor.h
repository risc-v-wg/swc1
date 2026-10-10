#ifndef _SENSOR_H
#define _SENSOR_H

#include <stdint.h>
#include <stdbool.h>

/* BME280 on the bit-banged I2C bus (GPIO[1]=SCL, GPIO[2]=SDA).
 * Call from ether_task only -- it shares the GPIO registers with the
 * ENC424J600 SPI CS, and every access busy-waits (see i2c_ctrl.h). */
bool sensor_init(void);
/* One reading in sensor_send.c's fixed-point units: temp [0.01 degC],
 * hum [0.01 %RH], press [Pa]. false if the sensor didn't answer. */
bool sensor_read(int32_t *temp, int32_t *hum, int32_t *press);

#endif /* _SENSOR_H */
