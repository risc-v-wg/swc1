# JASA-1 環境モニタ (PC side)

Receives indoor sensor data (temperature, humidity, pressure) from the JASA-1 board over UDP.
Fetches outdoor weather from the Internet and shows indoor, outdoor and the difference on a web page.
See `doc/Sensor-Demo.png` for the overall demo design.

Requires Python 3.8 or later. Only the standard library is used.

## Run

```sh
python3 sensor_monitor.py            # UDP 5005, web page on http://localhost:8000/
python3 sensor_sim.py                # optional: fake sensor for testing
```

Allow UDP port 5005 in the PC firewall so the board can reach it, for example `sudo ufw allow 5005/udp`.

## Options

| Option | Default | Meaning |
|---|---|---|
| `--udp-port` | 5005 | UDP port for sensor packets |
| `--http-port` | 8000 | Web page port |
| `--weather` | `jma` | `jma` (気象庁 AMeDAS + forecast) or `open-meteo` |
| `--jma-station` | 44132 | AMeDAS station id (Tokyo) |
| `--jma-area` | 130000 | Forecast office code for the weather text (Tokyo) |
| `--lat`, `--lon` | 35.69, 139.75 | Location for Open-Meteo |
| `--location` | auto | Location name shown on the page |
| `--pressure` | `station` | Outdoor pressure to compare: `station` (現地気圧) or `sea` (海面気圧) |
| `--weather-interval` | 600 | Weather refresh interval in seconds |
| `--stale` | 10 | Seconds without UDP data before indoor values are shown as stale |

AMeDAS station ids are listed at https://www.jma.go.jp/bosai/amedas/const/amedastable.json.
Only some stations measure humidity and pressure, so pick one that has them.

The default compares against station pressure, because an indoor sensor such as a BME280 measures absolute pressure.

## UDP packet format

Send one measurement per datagram. Units are degC, %RH and hPa. Any of these formats is accepted:

```text
JSON       {"temp": 25.2, "hum": 45.1, "press": 1012.8}
key=value  T=25.2,H=45.1,P=1012.8
CSV        25.2,45.1,1012.8                 (temperature, humidity, pressure)
binary     12 bytes = 3 x int32 little-endian
           temperature [0.01 degC], humidity [0.01 %RH], pressure [Pa]
```

The binary format matches the integer output of the BME280 compensation code, so firmware can send it without floating point.
Out-of-range readings are rejected and counted as bad packets on the page.

## HTTP API

`GET /api/data` returns the latest indoor and outdoor values as JSON. The page polls it every second.
