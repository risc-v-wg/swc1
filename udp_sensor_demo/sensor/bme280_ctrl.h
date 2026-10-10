#ifndef _BME280_CTRL_H
#define _BME280_CTRL_H

#include <stdint.h>
#include <stdbool.h>

bool bme280_setup();
bool bme280_get_calib_data();
bool bme280_get_temperature(int32_t *temperature);
int32_t bme280_get_humidity();
int32_t bme280_get_pressure();

#endif /* _BME280_CTRL_H */