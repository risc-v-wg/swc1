/*
 * sensor.c -- ported from pmodnic_test/sensor/sensor.c.
 *
 * frc_start() is gone: micro T-Kernel already runs the FRC for its tick
 * (sys_timer.h), and rewriting FRC_CNTRL would clear a pending tick
 * interrupt. set_led() is gone as well (the LED register isn't used here).
 */
#include "sensor.h"

#include "gpio_ctrl.h"
#include "i2c_ctrl.h"
#include "bme280_ctrl.h"
#include "swc1_time.h"

int printf(const char *fmt, ...);

bool sensor_init(void)
{
    printf("--- Initialise driver\n");
    gpio_init();
    i2c_init();

#ifdef SENSOR_TRACE
    /* Bring-up check: one I2C half-period should be ~I2C_DELAY_US*50 cycles */
    printf("sensor_init: GPIO_OUT=%x EN=%x IN=%x\n", (unsigned)SWC1_GPIO_OUT,
           (unsigned)SWC1_GPIO_ENABLE, (unsigned)SWC1_GPIO_IN);
    uint32_t t0 = swc1_cycles();
    swc1_delay_us(I2C_DELAY_US);
    uint32_t t1 = swc1_cycles();
    printf("sensor_init: swc1_delay_us(%u) took %u cycles\n",
           (unsigned)I2C_DELAY_US, (unsigned)(t1 - t0));
#endif

    printf("setup BME280 sensor\n");
    if (!bme280_setup())
        return false;
    return bme280_get_calib_data();
}

bool sensor_read(int32_t *temp, int32_t *hum, int32_t *press)
{
    if (!bme280_get_temperature(temp)) {
        printf("temperature: read failed\n");
        return false;
    }
    /* 1/1024 %RH -> 0.01 %RH, rounded */
    *hum = (bme280_get_humidity() * 100 + 512) / 1024;
    *press = bme280_get_pressure();
    return true;
}
