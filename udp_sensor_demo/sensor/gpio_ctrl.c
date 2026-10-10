/*
 * gpio_ctrl.c -- ported from pmodnic_test/sensor/gpio_ctrl.c.
 *
 * Register addresses now come from lwip_port/drivers/swc1_io.h instead of
 * pmodnic_test's reg_rw.h. All accesses are whole-word read-modify-write,
 * so they never disturb GPIO[0] (ENC424J600 CS, owned by swc1_spi.c). All
 * GPIO users (SPI CS, I2C, alive LED in sensor_send.c) run in ether_task,
 * so the RMWs can't interleave.
 */
#include "swc1_io.h"
#include "gpio_ctrl.h"

#define NUM_OF_GPIO     4

static void gpio_set_reg(volatile uint32_t *reg, int gpio, uint32_t val)
{
        uint32_t data = *reg;
        data &= ~(1U << gpio);
        data |= val << gpio;
        *reg = data;
}

/*
 * gpio_init -- The enable bits of the I2C GPIOs are set to zero.
 * GPIO[0] (ENC424J600 SPI chip select, lwip_port/drivers/swc1_spi.c) and
 * GPIO[3] (alive LED, lwip_port/app/sensor_send.c) are left alone.
 */
void gpio_init(void)
{
        gpio_set_reg(&SWC1_GPIO_ENABLE, GPIO_I2C_SCL, 0U);
        gpio_set_reg(&SWC1_GPIO_ENABLE, GPIO_I2C_SDA, 0U);
}

/*
 * gpio_set_output
 */
void gpio_set_output(int gpio, gpio_level_t level)
{
        // Check GPIO number
        if (gpio >= NUM_OF_GPIO || gpio < 0)
                return;

        // set GPIO_OUT and GPIO_EN
        switch (level) {
                case GPIO_LOW:
                        gpio_set_reg(&SWC1_GPIO_OUT, gpio, 0);
                        gpio_set_reg(&SWC1_GPIO_ENABLE, gpio, 1U);
                        break;
                case GPIO_HIGH:
                        gpio_set_reg(&SWC1_GPIO_OUT, gpio, 1);
                        gpio_set_reg(&SWC1_GPIO_ENABLE, gpio, 1U);
                        break;
                case GPIO_HIZ:
                default:
                        gpio_set_reg(&SWC1_GPIO_ENABLE, gpio, 0U);
                        break;
        }
}

uint32_t gpio_get_input(int gpio)
{
        // Check GPIO number
        if (gpio >= NUM_OF_GPIO || gpio < 0)
                return 0;

        uint32_t rdata = SWC1_GPIO_IN;
        uint32_t data = (rdata >> gpio) & 1U;

        return data;
}
