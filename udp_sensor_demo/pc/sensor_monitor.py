#!/usr/bin/env python3
"""JASA-1 environment monitor (PC side).

* Receives indoor sensor data (temperature / humidity / pressure) from the
  JASA-1 board over UDP.
* Periodically fetches outdoor weather from the Internet
  (JMA / 気象庁 AMeDAS + forecast, or Open-Meteo).
* Serves a web page that shows indoor, outdoor and the difference.

Python 3.8+ standard library only. No extra packages are required.

Accepted UDP payload formats (one measurement per datagram):

  JSON       {"temp": 25.2, "hum": 45.1, "press": 1012.8}
             (also accepted keys: temperature/t, humidity/h, pressure/p)
  key=value  T=25.2,H=45.1,P=1012.8      (separator: comma, space or ';')
  CSV        25.2,45.1,1012.8            (order: temperature, humidity, pressure)
  binary     12 bytes, 3 x int32 little-endian:
             temperature [0.01 degC], humidity [0.01 %RH], pressure [Pa]

Units: temperature degC, humidity %RH, pressure hPa.
"""

import argparse
import datetime as dt
import json
import logging
import os
import re
import socket
import struct
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

JST = dt.timezone(dt.timedelta(hours=9))
HERE = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(HERE, "static")

log = logging.getLogger("sensor_monitor")


# --------------------------------------------------------------------------
# Shared state
# --------------------------------------------------------------------------
class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.indoor = None          # dict: temp, hum, press, time, source
        self.indoor_count = 0
        self.indoor_errors = 0
        self.last_error = None
        self.outdoor = None         # dict: temp, hum, press, weather, ...
        self.outdoor_error = None

    def set_indoor(self, values, source):
        now = time.time()
        with self.lock:
            self.indoor = dict(values, time=now, source=source)
            self.indoor_count += 1

    def snapshot(self):
        with self.lock:
            return {
                "now": time.time(),
                "indoor": self.indoor,
                "indoor_count": self.indoor_count,
                "indoor_errors": self.indoor_errors,
                "last_error": self.last_error,
                "outdoor": self.outdoor,
                "outdoor_error": self.outdoor_error,
            }


STATE = State()


# --------------------------------------------------------------------------
# UDP packet parsing
# --------------------------------------------------------------------------
KEY_ALIASES = {
    "temp": "temp", "temperature": "temp", "t": "temp", "tmp": "temp",
    "hum": "hum", "humidity": "hum", "h": "hum", "rh": "hum",
    "press": "press", "pressure": "press", "p": "press", "pres": "press",
    "prs": "press",
}


def _normalize(d):
    out = {}
    for k, v in d.items():
        key = KEY_ALIASES.get(str(k).strip().lower())
        if key is None:
            continue
        out[key] = float(v)
    if not out:
        raise ValueError("no temperature/humidity/pressure field found")
    return out


def parse_packet(data: bytes):
    """Return dict with any of temp/hum/press. Raises ValueError."""
    # Binary format: exactly 12 bytes, not printable text.
    if len(data) == 12 and not all(32 <= b < 127 for b in data):
        t, h, p = struct.unpack("<iii", data)
        return {"temp": t / 100.0, "hum": h / 100.0, "press": p / 100.0}

    text = data.decode("ascii", errors="strict").strip().strip("\x00").strip()
    if not text:
        raise ValueError("empty packet")

    if text.startswith("{"):
        return _normalize(json.loads(text))

    if "=" in text or ":" in text:
        pairs = re.findall(r"([A-Za-z_]+)\s*[=:]\s*([-+]?\d+(?:\.\d+)?)", text)
        if pairs:
            return _normalize(dict(pairs))

    nums = re.split(r"[,\s;]+", text)
    if len(nums) >= 3:
        t, h, p = (float(x) for x in nums[:3])
        return {"temp": t, "hum": h, "press": p}

    raise ValueError("unrecognized packet format")


def validate(v):
    """Reject obviously broken readings (e.g. sensor not initialised)."""
    if "temp" in v and not -50 <= v["temp"] <= 100:
        raise ValueError("temperature out of range: %r" % v["temp"])
    if "hum" in v and not 0 <= v["hum"] <= 100:
        raise ValueError("humidity out of range: %r" % v["hum"])
    if "press" in v and not 300 <= v["press"] <= 1100:
        raise ValueError("pressure out of range: %r" % v["press"])
    return v


def udp_loop(sock):
    log.info("UDP: listening on %s:%d", *sock.getsockname())
    while True:
        data, addr = sock.recvfrom(2048)
        src = "%s:%d" % addr
        try:
            values = validate(parse_packet(data))
        except (ValueError, UnicodeDecodeError, struct.error) as e:
            with STATE.lock:
                STATE.indoor_errors += 1
                STATE.last_error = "%s from %s: %r" % (e, src, data[:64])
            log.warning("UDP: bad packet from %s: %s (%r)", src, e, data[:64])
            continue
        STATE.set_indoor(values, src)
        log.debug("UDP: %s %s", src, values)


# --------------------------------------------------------------------------
# Outdoor weather
# --------------------------------------------------------------------------
def http_json(url, timeout=10):
    req = urllib.request.Request(url, headers={"User-Agent": "jasa1-demo/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def http_text(url, timeout=10):
    req = urllib.request.Request(url, headers={"User-Agent": "jasa1-demo/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8").strip()


# JMA forecast weather code (first digit) -> icon
def jma_icon(code):
    c = str(code or "")[:1]
    return {"1": "sunny", "2": "cloudy", "3": "rain", "4": "snow"}.get(c, "unknown")


def fetch_jma(args):
    base = "https://www.jma.go.jp/bosai"
    latest = http_text(base + "/amedas/data/latest_time.txt")
    ts = dt.datetime.fromisoformat(latest)
    amedas = http_json("%s/amedas/data/map/%s.json"
                       % (base, ts.strftime("%Y%m%d%H%M%S")))
    st = amedas.get(args.jma_station)
    if st is None:
        raise RuntimeError("AMeDAS station %s not found" % args.jma_station)

    def val(key):
        v = st.get(key)
        return v[0] if v and v[1] == 0 else None  # v[1] is a quality flag

    press = val("pressure") if args.pressure == "station" else val("normalPressure")
    out = {
        "provider": "気象庁 (JMA)",
        "location": args.location or "AMeDAS %s" % args.jma_station,
        "obs_time": ts.timestamp(),
        "temp": val("temp"),
        "hum": val("humidity"),
        "press": press,
        "weather": None,
        "icon": "unknown",
    }
    try:
        fc = http_json("%s/forecast/data/forecast/%s.json" % (base, args.jma_area))
        area = fc[0]["timeSeries"][0]["areas"][0]
        out["weather"] = re.sub(r"\s+", " ", area["weathers"][0])
        out["icon"] = jma_icon(area.get("weatherCodes", [None])[0])
        if not args.location:
            out["location"] = area["area"]["name"]
    except Exception as e:  # forecast is optional
        log.warning("JMA forecast failed: %s", e)
    return out


WMO = {
    0: ("快晴", "sunny"), 1: ("晴れ", "sunny"), 2: ("晴れ時々くもり", "partly"),
    3: ("くもり", "cloudy"), 45: ("霧", "cloudy"), 48: ("霧", "cloudy"),
    51: ("霧雨", "rain"), 53: ("霧雨", "rain"), 55: ("霧雨", "rain"),
    61: ("雨", "rain"), 63: ("雨", "rain"), 65: ("大雨", "rain"),
    71: ("雪", "snow"), 73: ("雪", "snow"), 75: ("大雪", "snow"),
    80: ("にわか雨", "rain"), 81: ("にわか雨", "rain"), 82: ("激しいにわか雨", "rain"),
    95: ("雷雨", "thunder"), 96: ("雷雨", "thunder"), 99: ("雷雨", "thunder"),
}


def fetch_open_meteo(args):
    q = urllib.parse.urlencode({
        "latitude": args.lat, "longitude": args.lon, "timezone": "Asia/Tokyo",
        "current": "temperature_2m,relative_humidity_2m,surface_pressure,"
                   "pressure_msl,weather_code",
    })
    d = http_json("https://api.open-meteo.com/v1/forecast?" + q)["current"]
    text, icon = WMO.get(d.get("weather_code"), ("不明", "unknown"))
    obs = dt.datetime.fromisoformat(d["time"]).replace(tzinfo=JST)
    return {
        "provider": "Open-Meteo",
        "location": args.location or "%.2f, %.2f" % (args.lat, args.lon),
        "obs_time": obs.timestamp(),
        "temp": d.get("temperature_2m"),
        "hum": d.get("relative_humidity_2m"),
        "press": d.get("surface_pressure") if args.pressure == "station"
        else d.get("pressure_msl"),
        "weather": text,
        "icon": icon,
    }


def weather_loop(args):
    fetch = fetch_jma if args.weather == "jma" else fetch_open_meteo
    while True:
        try:
            w = fetch(args)
            w["fetched"] = time.time()
            with STATE.lock:
                STATE.outdoor = w
                STATE.outdoor_error = None
            log.info("Weather: %s %s/%s/%s %s", w["location"], w["temp"],
                     w["hum"], w["press"], w["weather"])
            wait = args.weather_interval
        except Exception as e:
            with STATE.lock:
                STATE.outdoor_error = str(e)
            log.warning("Weather fetch failed: %s", e)
            wait = 60  # retry sooner after an error
        time.sleep(wait)


# --------------------------------------------------------------------------
# HTTP server
# --------------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    page_config = {}

    def log_message(self, fmt, *a):
        log.debug("HTTP: " + fmt, *a)

    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/api/data":
            snap = STATE.snapshot()
            snap["config"] = self.page_config
            body = json.dumps(snap, ensure_ascii=False).encode("utf-8")
            return self._send(200, body, "application/json; charset=utf-8")
        if path in ("/", "/index.html"):
            with open(os.path.join(STATIC_DIR, "index.html"), "rb") as f:
                return self._send(200, f.read(), "text/html; charset=utf-8")
        self._send(404, b"not found", "text/plain")


def main():
    p = argparse.ArgumentParser(description="JASA-1 environment monitor")
    p.add_argument("--udp-port", type=int, default=5005,
                   help="UDP port for sensor packets (default 5005)")
    p.add_argument("--udp-bind", default="", help="UDP bind address (default all)")
    p.add_argument("--http-port", type=int, default=8000,
                   help="web page port (default 8000)")
    p.add_argument("--http-bind", default="", help="HTTP bind address (default all)")
    p.add_argument("--weather", choices=["jma", "open-meteo"], default="jma",
                   help="outdoor weather source (default jma)")
    p.add_argument("--jma-station", default="44132",
                   help="JMA AMeDAS station id (default 44132 = Tokyo)")
    p.add_argument("--jma-area", default="130000",
                   help="JMA forecast office code (default 130000 = Tokyo)")
    p.add_argument("--lat", type=float, default=35.69, help="Open-Meteo latitude")
    p.add_argument("--lon", type=float, default=139.75, help="Open-Meteo longitude")
    p.add_argument("--location", default="", help="location name shown on the page")
    p.add_argument("--pressure", choices=["station", "sea"], default="station",
                   help="outdoor pressure to compare: station (現地気圧, default; "
                        "matches an indoor absolute sensor) or sea (海面気圧)")
    p.add_argument("--weather-interval", type=int, default=600,
                   help="weather refresh interval in seconds (default 600)")
    p.add_argument("--stale", type=int, default=5,
                   help="seconds without UDP data before indoor shows as stale")
    p.add_argument("-v", "--verbose", action="store_true", help="debug log")
    args = p.parse_args()

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")

    Handler.page_config = {"stale": args.stale, "pressure": args.pressure,
                           "udp_port": args.udp_port}

    # Bind both ports first, so a busy port is reported clearly at startup.
    try:
        udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        udp_sock.bind((args.udp_bind, args.udp_port))
    except OSError as e:
        raise SystemExit("ERROR: cannot use UDP port %d (%s).\n"
                         "Another program is using it. Try --udp-port <other port>."
                         % (args.udp_port, e.strerror))
    try:
        httpd = ThreadingHTTPServer((args.http_bind, args.http_port), Handler)
    except OSError as e:
        raise SystemExit("ERROR: cannot use HTTP port %d (%s).\n"
                         "Another program is using it. Try --http-port <other port>, "
                         "e.g. --http-port 8888." % (args.http_port, e.strerror))

    threading.Thread(target=udp_loop, args=(udp_sock,), daemon=True).start()
    threading.Thread(target=weather_loop, args=(args,), daemon=True).start()

    log.info("HTTP: open http://localhost:%d/", args.http_port)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
