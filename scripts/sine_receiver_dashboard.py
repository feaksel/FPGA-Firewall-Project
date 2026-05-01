#!/usr/bin/env python3
import argparse
import json
import struct
import sys
import threading
import time
from collections import deque
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

try:
    from scapy.all import Raw, TCP, UDP, sniff
except ImportError:
    print("Scapy is required. Install it with: pip install scapy", file=sys.stderr)
    sys.exit(1)


MAGIC = b"FWSINE1\0"
HEADER_LEN = len(MAGIC) + 4 + 2 + 2 + 2
DEFAULT_FILE_PORT = 5001


def parse_sine_payload(payload):
    if len(payload) < HEADER_LEN or not payload.startswith(MAGIC):
        return None
    seq, sample_rate, sine_hz, sample_count = struct.unpack("!IHHH", payload[len(MAGIC):HEADER_LEN])
    expected_len = HEADER_LEN + sample_count * 2
    if len(payload) < expected_len:
        return None
    samples = struct.unpack("!" + "h" * sample_count, payload[HEADER_LEN:expected_len])
    return {
        "seq": seq,
        "sample_rate": sample_rate,
        "sine_hz": sine_hz,
        "samples": samples,
    }


class SineState:
    def __init__(self, file_port):
        self.file_port = file_port
        self.lock = threading.Lock()
        self.started_at = time.time()
        self.samples = deque(maxlen=1024)
        self.events = deque(maxlen=80)
        self.allowed_packets = 0
        self.decoy_leaks = 0
        self.other_packets = 0
        self.missing_packets = 0
        self.last_seq = None
        self.last_seen = None
        self.sample_rate = 0
        self.sine_hz = 0
        self.sniff_error = ""

    def record_packet(self, pkt):
        now = time.time()
        with self.lock:
            if UDP in pkt and pkt[UDP].dport == self.file_port and Raw in pkt:
                parsed = parse_sine_payload(bytes(pkt[Raw].load))
                if parsed is None:
                    self.other_packets += 1
                    return

                seq = parsed["seq"]
                if self.last_seq is not None and seq > self.last_seq + 1:
                    self.missing_packets += seq - self.last_seq - 1
                self.last_seq = seq
                self.allowed_packets += 1
                self.last_seen = now
                self.sample_rate = parsed["sample_rate"]
                self.sine_hz = parsed["sine_hz"]
                self.samples.extend(parsed["samples"])
                self.events.appendleft({"time": now, "kind": "ALLOW", "detail": f"seq {seq}"})
                return

            if TCP in pkt and pkt[TCP].dport == 23:
                self.decoy_leaks += 1
                self.events.appendleft({"time": now, "kind": "LEAK", "detail": "TCP/23 reached PC2"})
                return

            if UDP in pkt and pkt[UDP].dport != self.file_port and Raw in pkt:
                payload = bytes(pkt[Raw].load)
                if b"FW-SINE-DECOY-DROP" in payload:
                    self.decoy_leaks += 1
                    self.events.appendleft({"time": now, "kind": "LEAK", "detail": "UDP decoy reached PC2"})
                    return

            self.other_packets += 1

    def set_error(self, error):
        with self.lock:
            self.sniff_error = error

    def snapshot(self):
        with self.lock:
            elapsed = max(time.time() - self.started_at, 0.001)
            last_age = None if self.last_seen is None else time.time() - self.last_seen
            return {
                "allowed_packets": self.allowed_packets,
                "decoy_leaks": self.decoy_leaks,
                "other_packets": self.other_packets,
                "missing_packets": self.missing_packets,
                "last_seq": self.last_seq if self.last_seq is not None else "-",
                "last_age": last_age,
                "packets_per_second": self.allowed_packets / elapsed,
                "sample_rate": self.sample_rate,
                "sine_hz": self.sine_hz,
                "samples": list(self.samples),
                "events": [
                    {
                        "time": time.strftime("%H:%M:%S", time.localtime(event["time"])),
                        "kind": event["kind"],
                        "detail": event["detail"],
                    }
                    for event in list(self.events)
                ],
                "sniff_error": self.sniff_error,
            }


HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>FPGA Firewall Sine Demo</title>
<style>
:root {
  --bg: #f4f6f8;
  --panel: #ffffff;
  --ink: #18212c;
  --muted: #657386;
  --line: #d6dde7;
  --blue: #1769c2;
  --green: #16875d;
  --red: #bd3a32;
  --amber: #a66f00;
}
* { box-sizing: border-box; }
body { margin: 0; font-family: "Segoe UI", Arial, sans-serif; background: var(--bg); color: var(--ink); }
header { background: var(--panel); border-bottom: 1px solid var(--line); padding: 18px 22px; }
h1 { margin: 0 0 4px; font-size: 22px; letter-spacing: 0; }
.sub { color: var(--muted); font-size: 13px; }
main { padding: 18px 22px 28px; display: grid; gap: 14px; }
.metrics { display: grid; grid-template-columns: repeat(5, minmax(120px, 1fr)); gap: 12px; }
.metric, .panel { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; }
.metric { padding: 13px 15px; }
.metric .label { color: var(--muted); font-size: 12px; text-transform: uppercase; }
.metric .value { margin-top: 7px; font-size: 27px; font-weight: 750; }
.metric.good .value { color: var(--green); }
.metric.bad .value { color: var(--red); }
.grid { display: grid; grid-template-columns: minmax(0, 1fr) minmax(300px, 0.45fr); gap: 14px; }
.panel { padding: 15px; min-width: 0; }
.panel h2 { margin: 0 0 12px; font-size: 16px; }
canvas { width: 100%; height: 320px; display: block; border: 1px solid var(--line); border-radius: 8px; background: #08111f; }
.flow { display: grid; grid-template-columns: 1fr 48px 1fr 48px 1fr 48px 1fr 48px 1fr; align-items: center; gap: 8px; }
.node { min-height: 72px; border: 1px solid var(--line); border-radius: 8px; padding: 10px; background: #fbfcfe; }
.node .label { color: var(--muted); font-size: 11px; text-transform: uppercase; }
.node .value { margin-top: 6px; font-weight: 750; }
.link { height: 2px; background: #9eb3ca; position: relative; }
.link::after { content: ""; position: absolute; right: -1px; top: -4px; border-left: 8px solid #9eb3ca; border-top: 5px solid transparent; border-bottom: 5px solid transparent; }
.events { display: grid; gap: 8px; max-height: 360px; overflow: auto; }
.event { display: grid; grid-template-columns: 64px 58px minmax(0, 1fr); gap: 8px; padding: 9px; border: 1px solid var(--line); border-radius: 7px; align-items: center; }
.kind { font-weight: 750; font-size: 12px; }
.kind.allow { color: var(--green); }
.kind.leak { color: var(--red); }
.note { color: var(--muted); font-size: 13px; line-height: 1.45; }
.warn { color: var(--amber); font-weight: 650; }
@media (max-width: 900px) {
  .metrics, .grid, .flow { grid-template-columns: 1fr; }
  .link { height: 22px; width: 2px; justify-self: center; }
}
</style>
</head>
<body>
<header>
  <h1>FPGA Firewall Continuous Sine Demo</h1>
  <div class="sub">PC1 sends an allowed sine stream plus blocked decoys. PC2 should see a clean live waveform and zero decoy leaks.</div>
</header>
<main>
  <section class="flow">
    <div class="node"><div class="label">PC1</div><div class="value">Sine + decoys</div></div>
    <div class="link"></div>
    <div class="node"><div class="label">W5500 A</div><div class="value">Ingress</div></div>
    <div class="link"></div>
    <div class="node"><div class="label">FPGA</div><div class="value">Rules</div></div>
    <div class="link"></div>
    <div class="node"><div class="label">W5500 B</div><div class="value">Egress</div></div>
    <div class="link"></div>
    <div class="node"><div class="label">PC2</div><div class="value">Waveform</div></div>
  </section>
  <section class="metrics">
    <div class="metric good"><div class="label">Allowed packets</div><div class="value" id="allowed">0</div></div>
    <div class="metric bad"><div class="label">Decoy leaks</div><div class="value" id="leaks">0</div></div>
    <div class="metric"><div class="label">Missing seq</div><div class="value" id="missing">0</div></div>
    <div class="metric"><div class="label">Packets/sec</div><div class="value" id="pps">0</div></div>
    <div class="metric"><div class="label">Last seq</div><div class="value" id="lastSeq">-</div></div>
  </section>
  <section class="grid">
    <div class="panel">
      <h2>Received Sine Wave</h2>
      <canvas id="wave" width="1200" height="360"></canvas>
      <p class="note" id="statusLine">Waiting for packets...</p>
    </div>
    <div class="panel">
      <h2>Recent Events</h2>
      <div class="events" id="events"></div>
      <p class="note warn" id="error"></p>
    </div>
  </section>
</main>
<script>
const canvas = document.getElementById("wave");
const ctx = canvas.getContext("2d");
const fields = {
  allowed: document.getElementById("allowed"),
  leaks: document.getElementById("leaks"),
  missing: document.getElementById("missing"),
  pps: document.getElementById("pps"),
  lastSeq: document.getElementById("lastSeq"),
  events: document.getElementById("events"),
  status: document.getElementById("statusLine"),
  error: document.getElementById("error"),
};

function drawWave(samples) {
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = "#08111f";
  ctx.fillRect(0, 0, w, h);
  ctx.strokeStyle = "#1a2d46";
  ctx.lineWidth = 1;
  for (let y = 0; y <= h; y += h / 4) {
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(w, y);
    ctx.stroke();
  }
  ctx.strokeStyle = "#4fd1a5";
  ctx.lineWidth = 2;
  ctx.beginPath();
  if (!samples.length) {
    ctx.moveTo(0, h / 2);
    ctx.lineTo(w, h / 2);
  } else {
    samples.forEach((sample, i) => {
      const x = (i / Math.max(samples.length - 1, 1)) * w;
      const y = h / 2 - (sample / 32768) * (h * 0.42);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
  }
  ctx.stroke();
}

async function refresh() {
  const res = await fetch("/api/state", {cache: "no-store"});
  const data = await res.json();
  fields.allowed.textContent = data.allowed_packets;
  fields.leaks.textContent = data.decoy_leaks;
  fields.missing.textContent = data.missing_packets;
  fields.pps.textContent = data.packets_per_second.toFixed(1);
  fields.lastSeq.textContent = data.last_seq;
  fields.status.textContent = data.sample_rate ? `${data.sine_hz} Hz sine, sample rate ${data.sample_rate} Hz` : "Waiting for packets...";
  fields.error.textContent = data.sniff_error || "";
  fields.events.innerHTML = data.events.map(ev => {
    const cls = ev.kind === "LEAK" ? "leak" : "allow";
    return `<div class="event"><div class="note">${ev.time}</div><div class="kind ${cls}">${ev.kind}</div><div>${ev.detail}</div></div>`;
  }).join("") || `<p class="note">No packets yet.</p>`;
  drawWave(data.samples);
}

refresh();
setInterval(refresh, 250);
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    state = None

    def log_message(self, fmt, *args):
        return

    def send_text(self, status, body, content_type):
        payload = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/":
            self.send_text(HTTPStatus.OK, HTML, "text/html; charset=utf-8")
        elif parsed.path == "/api/state":
            self.send_text(HTTPStatus.OK, json.dumps(self.state.snapshot()), "application/json; charset=utf-8")
        else:
            self.send_text(HTTPStatus.NOT_FOUND, "not found", "text/plain; charset=utf-8")


def sniff_worker(state, iface):
    try:
        sniff(iface=iface, prn=state.record_packet, store=False)
    except Exception as exc:
        state.set_error(str(exc))


def main():
    parser = argparse.ArgumentParser(description="PC2 browser dashboard for the continuous sine-wave firewall demo.")
    parser.add_argument("--iface", required=True, help="Scapy interface connected to W5500 B / FPGA egress.")
    parser.add_argument("--file-port", type=int, default=DEFAULT_FILE_PORT)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8090)
    args = parser.parse_args()

    state = SineState(args.file_port)
    Handler.state = state
    thread = threading.Thread(target=sniff_worker, args=(state, args.iface), daemon=True)
    thread.start()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Sine receiver dashboard running at http://{args.host}:{args.port}")
    print("Stop with Ctrl+C.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
