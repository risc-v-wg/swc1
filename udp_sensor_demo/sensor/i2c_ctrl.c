/*
 * i2c_ctrl.c -- ported from pmodnic_test/sensor/i2c_ctrl.c.
 *
 * wait_ms() (timer.c) is replaced by swc1_delay_us(): timer.c's
 * frc_start() wrote FRC_CNTRL, which micro T-Kernel owns for its tick
 * (writing it also clears the pending tick interrupt); swc1_delay_us()
 * only reads the free-running counter.
 */
#include <stdbool.h>
#include "gpio_ctrl.h"
#include "i2c_ctrl.h"

int printf(const char *fmt, ...);
#include "swc1_time.h"

static void i2c_wait(void)
{
        swc1_delay_us(I2C_DELAY_US);
}

static void i2c_set_signal(int pin, uint32_t value)
{
        if (value == 0)
                gpio_set_output(pin, GPIO_LOW);
        else
                gpio_set_output(pin, GPIO_HIZ);
}

static void i2c_stop();

void i2c_init()
{
        gpio_set_output(GPIO_I2C_SCL, GPIO_HIZ);
        gpio_set_output(GPIO_I2C_SDA, GPIO_HIZ);

        /* Bus recovery: if ether_task was killed by the watchdog in the
         * middle of a read, the BME280 may still be driving SDA low.
         * Clock SCL (up to 9 pulses) until it lets go, then send STOP. */
        i2c_wait();
        for (int i = 0; i < 9 && gpio_get_input(GPIO_I2C_SDA) == 0; i++) {
                gpio_set_output(GPIO_I2C_SCL, GPIO_LOW);
                i2c_wait();
                gpio_set_output(GPIO_I2C_SCL, GPIO_HIZ);
                i2c_wait();
        }
        i2c_stop();
}

static void i2c_start()
{
        gpio_set_output(GPIO_I2C_SCL, GPIO_HIZ);
        gpio_set_output(GPIO_I2C_SDA, GPIO_HIZ);
        i2c_wait();
        gpio_set_output(GPIO_I2C_SDA, GPIO_LOW);
        i2c_wait();
        gpio_set_output(GPIO_I2C_SCL, GPIO_LOW);
        i2c_wait();
}

static void i2c_stop()
{
        gpio_set_output(GPIO_I2C_SCL, GPIO_LOW);
        gpio_set_output(GPIO_I2C_SDA, GPIO_LOW);
        i2c_wait();
        gpio_set_output(GPIO_I2C_SCL, GPIO_HIZ);
        i2c_wait();
        gpio_set_output(GPIO_I2C_SDA, GPIO_HIZ);
}


static void i2c_send_bit(uint8_t bitdata)
{
        i2c_set_signal(GPIO_I2C_SDA, bitdata & 1U);
        i2c_wait();
        gpio_set_output(GPIO_I2C_SCL, GPIO_HIZ);
        i2c_wait();
        gpio_set_output(GPIO_I2C_SCL, GPIO_LOW);
        gpio_set_output(GPIO_I2C_SDA, GPIO_HIZ);
}

static uint8_t i2c_recv_bit()
{
        i2c_wait();
        gpio_set_output(GPIO_I2C_SCL, GPIO_HIZ);
        uint8_t bitdata = gpio_get_input(GPIO_I2C_SDA);
        i2c_wait();
        gpio_set_output(GPIO_I2C_SCL, GPIO_LOW);
      
        return bitdata;
}

static bool i2c_recv_ack()
{
        uint8_t bitdata = i2c_recv_bit();
        bool ack = (bitdata == 0) ? true : false;
        
        return ack;
}

static void i2c_send_ack()
{
        // always send acknowledge 
        i2c_send_bit(0);
}

static void i2c_send_byte(uint8_t bytedata)
{
        int shift = 7;
        for (int i = 0; i < 8; i++) {
                i2c_send_bit((bytedata >> shift) & 1U);
                shift--;
        }

}
static uint8_t i2c_recv_byte()
{
        uint8_t bytedata = 0;
        for (int i = 0; i < 8; i++) {
                uint8_t bitdata = i2c_recv_bit();
                bytedata <<= 1;
                bytedata |= bitdata;
        }
        return bytedata;
}

int i2c_write(uint8_t slave_address, const uint8_t * wbuf, int count)
{
        int write_count = 0;
        bool ack = false;

        // start condition
        i2c_start();

        // send slave address and write
        uint8_t bytedata = slave_address << 1;
        i2c_send_byte(bytedata);
        ack = i2c_recv_ack();
#ifdef SENSOR_TRACE
        printf("i2c_write: addr %x %s\n", slave_address, ack ? "ACK" : "NACK");
#endif
        if (!ack) {
                i2c_stop();
                return -1; //TODO: define error
        }

        //send data
        for (int i = 0; i < count; i++) {
                i2c_send_byte(wbuf[i]);
                write_count++;
                ack = i2c_recv_ack();
                if (!ack) {
                        i2c_stop();
                        return -write_count; //TODO: define error
                }              
        }

        // stop
        i2c_stop();
        return write_count;
}

int i2c_read(uint8_t slave_address, uint8_t * rbuf, int count)
{
        int read_count = 0;
        bool ack = false;

        // start condition
        i2c_start();

        // send slave address and read flag
        uint8_t bytedata = (slave_address << 1) | 1U;
        i2c_send_byte(bytedata);
        ack = i2c_recv_ack();
        if (!ack) {
                i2c_stop();
                return -1; //TODO: define error
        }

        //Receuve data
        for (int i = 0; i < count; i++) {
                rbuf[i] = i2c_recv_byte();
                read_count++;
                i2c_send_ack();             
        }

        // stop
        i2c_stop();
        return read_count;
}
