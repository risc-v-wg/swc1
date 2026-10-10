/*
 * bme280_ctrl.c -- ported from pmodnic_test/sensor/bme280_ctrl.c.
 *
 * Changes from the bare-metal original:
 *  - bme280_setup() returns whether the sensor ACKed, so the caller can
 *    retry when it isn't connected.
 *  - dig_h4 / dig_h6 are sign-extended as in Bosch's reference driver
 *    (the original treated them as unsigned).
 *  - Per-read "start"/"done" console messages removed (the sender prints
 *    each reading anyway); only errors are printed. ether_printf.c has no
 *    %ld / %02x, so debug output uses %d / %x.
 */
#include "bme280_ctrl.h"
#include "i2c_ctrl.h"

int printf(const char *fmt, ...);

//#define BME280_DEBUG


static int32_t compensate_humidity();

/* constant */
static const uint8_t BME280_SLAVE_ADDR = 0x76u;

/* calibration parameters (4.2.2 Trimming parameter readout) */
static uint16_t dig_t1;
static int16_t dig_t2, dig_t3;

static uint16_t dig_p1;
static int16_t dig_p2, dig_p3, dig_p4, dig_p5, dig_p6, dig_p7, dig_p8, dig_p9;

static uint16_t dig_h1;
static int16_t dig_h2;
static uint16_t dig_h3;
static int16_t dig_h4, dig_h5, dig_h6;

/* temperature */
static uint32_t uncomp_temperature;
int32_t calib_t_fine;

/* Humidity support case */
static uint32_t uncomp_humidity;
static int32_t comp_humidity;

/* pressure */
static uint32_t uncomp_pressure;
static int32_t comp_pressure;

/*
 bme280_write
 */
bool bme280_write(uint8_t reg_addr, uint8_t reg_val)
{
        uint8_t buf[2] = {reg_addr, reg_val};
        int wr_ret = i2c_write(BME280_SLAVE_ADDR, buf, 2);
        if (wr_ret != 2)
                return false;

  return true;
}

/*
 bme280_read
 */
#if defined(CONFIG_BME280_SINGLE_READ) || defined(BME280_DEBUG)
static bool bme280_read(uint8_t reg_addr, uint8_t *reg_val)
{

        int wr_ret = i2c_write(BME280_SLAVE_ADDR, &reg_addr, 1);
        if (wr_ret != 1)
                return false;

        int rd_ret = i2c_read(BME280_SLAVE_ADDR, reg_val, 1);
        if (rd_ret != 1)
                return false;

        return true;
}
#endif /* CONFIG_BME280_SINGLE_READ */

/*
 bme280_read_bulk
 */
static bool bme280_read_bulk(uint8_t reg_addr, uint8_t *reg_val_list, int len)
{
        int wr_ret = i2c_write(BME280_SLAVE_ADDR, &reg_addr, 1);
        if (wr_ret != 1) {
                printf("bme280_read_bulk: failed in i2c_write: %d\n", wr_ret);
                return false;
        }

        int rd_ret = i2c_read(BME280_SLAVE_ADDR, reg_val_list, len);
        if (rd_ret != len){
                printf("bme280_read_bulk: failed in i2c_read:%d\n", rd_ret);
                return false;
        }

        return true;
}

/*
 bme280_setup
 */
bool bme280_setup()
{
        printf("bme280_setup: start\n");

#ifdef SENSOR_TRACE
        printf("bme280_setup: write f2\n");
        if (!bme280_write(0xf2, 1)) goto fail;
        printf("bme280_setup: write f4\n");
        if (!bme280_write(0xf4, 0x27)) goto fail;
        printf("bme280_setup: write f5\n");
        if (!bme280_write(0xf5, 0xa0)) goto fail;
#else
        if (!bme280_write(0xf2, 1) ||
            !bme280_write(0xf4, 0x27) ||
            !bme280_write(0xf5, 0xa0))
                goto fail;
#endif

#ifdef BME280_DEBUG
        uint8_t data;
        bme280_read(0xf2, &data);
        printf("f2:%x\n", data);
        bme280_read(0xf4, &data);
        printf("f4:%x\n", data);
        bme280_read(0xf5, &data);
        printf("f5:%x\n", data);
#endif /* BME280_DEBUG */

        printf("bme280_setup: done\n");
        return true;

fail:
        printf("bme280_setup: failed (no ACK from 0x76?)\n");
        return false;
}

/* 4.2.2 Trimming parameter readout */
static void parse_calib_data(const uint8_t *reg_data)
{
        dig_t1 = reg_data[0] | (reg_data[1] << 8);
        dig_t2 = (int16_t)(reg_data[2] | (reg_data[3] << 8));
        dig_t3 = (int16_t)(reg_data[4] | (reg_data[5] << 8));

        dig_p1 = reg_data[6] | (reg_data[7] << 8);
        dig_p2 = (int16_t)(reg_data[8] | (reg_data[9] << 8));
        dig_p3 = (int16_t)(reg_data[10] | (reg_data[11] << 8));
        dig_p4 = (int16_t)(reg_data[12] | (reg_data[13] << 8));
        dig_p5 = (int16_t)(reg_data[14] | (reg_data[15] << 8));
        dig_p6 = (int16_t)(reg_data[16] | (reg_data[17] << 8));
        dig_p7 = (int16_t)(reg_data[18] | (reg_data[19] << 8));
        dig_p8 = (int16_t)(reg_data[20] | (reg_data[21] << 8));
        dig_p9 = (int16_t)(reg_data[22] | (reg_data[23] << 8));

        dig_h1 = reg_data[25];
        dig_h2 = (int16_t)(reg_data[26] | (reg_data[27] << 8));
        dig_h3 = reg_data[28];
        dig_h4 = (int16_t)(((int16_t)(int8_t)reg_data[29] * 16) | (reg_data[30] & 0xfu));
        dig_h5 = (int16_t)(((int16_t)(int8_t)reg_data[31] * 16) | (reg_data[30] >> 4));
        dig_h6 = (int16_t)(int8_t)reg_data[32];
}


/*
 bme280_get_calib_data
 */
bool bme280_get_calib_data()
{
        printf("bme280_get_calib_data: start\n");

        uint8_t reg_data[33] = { 0 };
        uint8_t reg_addr = 0x88u;

        /* first 26 bytes */
        bool rd_result = bme280_read_bulk(reg_addr, reg_data, 26);
        if (!rd_result) {
                printf("bme280_get_calib_data: read failed in bme280_read_bulk\n");
                return false;
        }

        /* next 7 bytes */
        reg_addr = 0xe1u;
        rd_result = bme280_read_bulk(reg_addr, &reg_data[26], 7);
        if (!rd_result) {
                printf("bme280_get_calib_data: read failed\n");
                return false;
        }

#ifdef BME280_DEBUG
        printf("reg_data:");
        for (int i = 0; i < 33; i++) {
                printf(" %x", reg_data[i]);
        }
        printf("\n");
#endif /* BME280_DEBUG */

        /* parse calibration data */
        parse_calib_data(reg_data);

        printf("bme280_get_calib_data: end\n");
        return true;
}

/*
 get_sensor_data
 */
static bool get_sensor_data()
{
#ifdef BME280_DEBUG
        printf("bme280_get_sensor_data\n");
#endif /* BME280_DEBUG */

        uint8_t reg_addr = 0xf7u;
        uint8_t reg_data[8] = {0};

        bool rd_result = bme280_read_bulk(reg_addr, reg_data, 8);
        if (!rd_result) {
                printf("read failed in bme280_get_sensor_data\n");
                return false;
        }

        uncomp_temperature = (reg_data[3] << 12) | (reg_data[4] << 4) | (reg_data[5] >> 4);

#ifdef BME280_DEBUG
        printf("bme280_get_sensor_data:%d\n", (int)uncomp_temperature);
#endif /* BME280_DEBUG */

        uncomp_humidity = (reg_data[6] << 8) | reg_data[7];

        uncomp_pressure = (reg_data[0] << 12) | (reg_data[1] << 4) | (reg_data[2] >> 4);

        return true;
}


/*
 compensate temperature
 */
static int32_t compensate_temperature()
{
        int32_t var1 = (int32_t)((uncomp_temperature / 8) - ((int32_t)dig_t1 * 2));
        var1 = (var1 * ((int32_t)dig_t2)) / 2048;
        int32_t var2 = (int32_t)((uncomp_temperature / 16) - ((int32_t)dig_t1));
        var2 = (((var2 * var2) / 4096) * ((int32_t)dig_t3)) / 16384;
        calib_t_fine = var1 + var2;
        int32_t temperature = (calib_t_fine * 5 + 128) / 256;

        return temperature;
}

static int32_t compensate_humidity()
{
        int32_t var1 = calib_t_fine - ((int32_t)76800);
        int32_t var2 = (int32_t)(uncomp_humidity * 16384);
        int32_t var3 = (int32_t)(((int32_t)dig_h4) * 1048576);
        int32_t var4 = ((int32_t)dig_h5) * var1;
        int32_t var5 = (((var2 - var3) - var4) + (int32_t)16384) / 32768;
        var2 = (var1 * ((int32_t)dig_h6)) / 1024;
        var3 = (var1 * ((int32_t)dig_h3)) / 2048;
        var4 = ((var2 * (var3 + (int32_t)32768)) / 1024) + (int32_t)2097152;
        var2 = ((var4 * ((int32_t)dig_h2)) + 8192) / 16384;
        var3 = var5 * var2;
        var4 = ((var3 / 32768) * (var3 / 32768)) / 128;
        var5 = var3 - ((var4 * ((int32_t)dig_h1)) / 16);
        var5 = (var5 < 0 ? 0 : var5);
        var5 = (var5 > 419430400 ? 419430400 : var5);
        int32_t humidity = (uint32_t)(var5 / 4096);

        return humidity;
}

/*
 compensate pressure [Pa] -- Bosch's 32-bit integer formula (datasheet
 8.2, "BME280_U32_t bmp280_compensate_P_int32"), in place of the original
 64-bit one: int64_t multiply/divide go through libgcc's __muldi3/__divdi3,
 which in this rv32im toolchain contain mul/div instructions the RV32I
 core doesn't execute correctly. Resolution is 1 Pa instead of 1/256 Pa,
 which the original threw away anyway (p /= 256).
 */
static int32_t compensate_pressure()
{
        int32_t var1 = (calib_t_fine >> 1) - (int32_t)64000;
        int32_t var2 = (((var1 >> 2) * (var1 >> 2)) >> 11) * ((int32_t)dig_p6);
        var2 = var2 + ((var1 * ((int32_t)dig_p5)) << 1);
        var2 = (var2 >> 2) + (((int32_t)dig_p4) << 16);
        var1 = (((dig_p3 * (((var1 >> 2) * (var1 >> 2)) >> 13)) >> 3) +
                ((((int32_t)dig_p2) * var1) >> 1)) >> 18;
        var1 = ((32768 + var1) * ((int32_t)dig_p1)) >> 15;
        if (var1 == 0)
                return 0;       /* avoid division by zero */

        uint32_t p = (((uint32_t)(((int32_t)1048576) - (int32_t)uncomp_pressure) -
                       (var2 >> 12))) * 3125;
        if (p < 0x80000000u)
                p = (p << 1) / ((uint32_t)var1);
        else
                p = (p / (uint32_t)var1) * 2;
        var1 = (((int32_t)dig_p9) * ((int32_t)(((p >> 3) * (p >> 3)) >> 13))) >> 12;
        var2 = (((int32_t)(p >> 2)) * ((int32_t)dig_p8)) >> 13;
        p = (uint32_t)((int32_t)p + ((var1 + var2 + dig_p7) >> 4));

        return (int32_t)p;
}

/*
 bme280_get_temperature -- Read the sensor and return the temperature
 [0.01 degC] in *temperature. Returns false if the sensor could not be
 read; *temperature and the humidity value are not updated then.
 */
bool bme280_get_temperature(int32_t *temperature)
{
        bool result = get_sensor_data();
        if (!result) {
                result = get_sensor_data();
                if (!result) {
                        printf("bme280_get_temperature: failed\n");
                        return false;
                }
        }

        *temperature = compensate_temperature();

        comp_humidity = compensate_humidity();

        comp_pressure = compensate_pressure();

        return true;
}

/*
 * bme280_get_humidity
 */
int32_t bme280_get_humidity()
{
        return comp_humidity;
}

/*
 * bme280_get_pressure
 */
int32_t bme280_get_pressure()
{
        return comp_pressure;
}