#!/usr/bin/env python3
"""Send fake sensor packets over UDP, to test sensor_monitor.py without the board.

  python3 sensor_sim.py                       # JSON to 127.0.0.1:5005 every 1 s
  python3 sensor_sim.py --format kv           # T=25.20,H=45.10,P=1012.80
  python3 sensor_sim.py --format csv          # 25.20,45.10,1012.80
  python3 sensor_sim.py --format bin          # 12-byte binary (3 x int32 LE)
  python3 sensor_sim.py --host 192.168.1.10   # send to another PC
"""

import argparse
import json
import math
import random
import socket
import struct
import time


def encode(fmt, t, h, p):
    if fmt == "json":
        return json.dumps({"temp": round(t, 2), "hum": round(h, 2),
                           "press": round(p, 2)}).encode()
    if fmt == "kv":
        return ("T=%.2f,H=%.2f,P=%.2f" % (t, h, p)).encode()
    if fmt == "csv":
        return ("%.2f,%.2f,%.2f" % (t, h, p)).encode()
    # bin: temperature 0.01 degC, humidity 0.01 %RH, pressure Pa
    return struct.pack("<iii", round(t * 100), round(h * 100), round(p * 100))


def main():
    ap = argparse.ArgumentParser(description="UDP sensor simulator")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=5005)
    ap.add_argument("--interval", type=float, default=1.0)
    ap.add_argument("--format", choices=["json", "kv", "csv", "bin"], default="json")
    args = ap.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    t0 = time.time()
    print("sending %s to %s:%d (Ctrl+C to stop)" % (args.format, args.host, args.port))
    try:
        while True:
            x = (time.time() - t0) / 60.0
            t = 25.0 + 0.8 * math.sin(x) + random.uniform(-0.05, 0.05)
            h = 45.0 + 3.0 * math.cos(x) + random.uniform(-0.2, 0.2)
            p = 1012.8 + 0.5 * math.sin(x / 3) + random.uniform(-0.05, 0.05)
            pkt = encode(args.format, t, h, p)
            sock.sendto(pkt, (args.host, args.port))
            print(pkt if args.format != "bin" else pkt.hex())
            time.sleep(args.interval)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
