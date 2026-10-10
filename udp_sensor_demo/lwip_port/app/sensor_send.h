#ifndef SENSOR_SEND_H
#define SENSOR_SEND_H

/* BME280 UDP sender: the board-side equivalent of the PC's sensor_sim.py,
 * with real readings. Once every SENSOR_SEND_INTERVAL_MS it reads the
 * BME280 (sensor/sensor.c) and sends one datagram of temperature /
 * humidity / pressure to
 * SENSOR_DEST_IP:SENSOR_DEST_PORT, in the same payload formats
 * sensor_sim.py produces (and sensor_monitor.py accepts):
 *
 *   SENSOR_FORMAT 0 (json, default)  {"temp": 25.20, "hum": 45.10, "press": 1012.80}
 *   SENSOR_FORMAT 1 (kv)             T=25.20,H=45.10,P=1012.80
 *   SENSOR_FORMAT 2 (csv)            25.20,45.10,1012.80
 *   SENSOR_FORMAT 3 (bin)            12 bytes, 3 x int32 LE:
 *                                    temp [0.01 degC], hum [0.01 %RH], press [Pa]
 *
 * Send-only: nothing is received. Call sensor_send_init() once after
 * netif_set_up(), then sensor_send_poll() from the main loop; poll checks
 * the free-running cycle counter and sends when the interval has elapsed. */
void sensor_send_init(void);
void sensor_send_poll(void);

#endif /* SENSOR_SEND_H */
