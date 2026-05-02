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


MAGIC_V1 = b"FWSINE1\0"
MAGIC_V2 = b"FWSINE2\0"
HEADER_V1_LEN = len(MAGIC_V1) + 4 + 2 + 2 + 2
HEADER_V2_LEN = len(MAGIC_V2) + 4 + 4 + 2 + 2 + 2
DEFAULT_FILE_PORT = 5001


def parse_sine_payload(payload):
    if payload.startswith(MAGIC_V2):
        if len(payload) < HEADER_V2_LEN:
            return None
        run_id, seq, sample_rate, sine_hz, sample_count = struct.unpack(
            "!IIHHH", payload[len(MAGIC_V2):HEADER_V2_LEN]
        )
        header_len = HEADER_V2_LEN
    elif payload.startswith(MAGIC_V1):
        if len(payload) < HEADER_V1_LEN:
            return None
        seq, sample_rate, sine_hz, sample_count = struct.unpack("!IHHH", payload[len(MAGIC_V1):HEADER_V1_LEN])
        run_id = 0
        header_len = HEADER_V1_LEN
        legacy = True
    else:
        return None
    if payload.startswith(MAGIC_V2):
        legacy = False

    expected_len = header_len + sample_count * 2
    if len(payload) < expected_len:
        return None
    samples = struct.unpack("!" + "h" * sample_count, payload[header_len:expected_len])
    return {
        "run_id": run_id,
        "legacy": legacy,
        "seq": seq,
        "sample_rate": sample_rate,
        "sine_hz": sine_hz,
        "samples": samples,
    }


class SineState:
    def __init__(self, file_port, decoy_every, run_switch_idle_sec, accept_legacy):
        self.file_port = file_port
        self.decoy_every = decoy_every
        self.run_switch_idle_sec = run_switch_idle_sec
        self.accept_legacy = accept_legacy
        self.lock = threading.Lock()
        self.reset_unlocked()

    def reset_unlocked(self):
        self.started_at = time.time()
        self.samples = deque(maxlen=1024)
        self.events = deque(maxlen=80)
        self.packet_marks = deque(maxlen=120)
        self.rate_history = deque(maxlen=120)
        self.allowed_packets = 0
        self.expected_drops = 0
        self.decoy_leaks = 0
        self.other_packets = 0
        self.missing_packets = 0
        self.ignored_packets = 0
        self.run_id = None
        self.last_seq = None
        self.last_seen = None
        self.sample_rate = 0
        self.sine_hz = 0
        self.sniff_error = ""
        self.last_rate_time = time.time()
        self.last_rate_packets = 0

    def reset_stream_unlocked(self, now, run_id, reason):
        self.started_at = now
        self.samples.clear()
        self.packet_marks.clear()
        self.rate_history.clear()
        self.allowed_packets = 0
        self.expected_drops = 0
        self.missing_packets = 0
        self.last_seq = None
        self.last_seen = None
        self.last_rate_time = now
        self.last_rate_packets = 0
        self.run_id = run_id
        self.events.appendleft({"time": now, "kind": "SYNC", "detail": reason})

    def reset(self):
        with self.lock:
            self.reset_unlocked()

    def record_packet(self, pkt):
        now = time.time()
        with self.lock:
            if UDP in pkt and pkt[UDP].dport == self.file_port and Raw in pkt:
                parsed = parse_sine_payload(bytes(pkt[Raw].load))
                if parsed is None:
                    self.other_packets += 1
                    return
                if parsed["legacy"] and not self.accept_legacy:
                    self.ignored_packets += 1
                    self.packet_marks.append({"kind": "old", "seq": None, "time": now})
                    self.events.appendleft({"time": now, "kind": "OLD", "detail": "ignored legacy FWSINE1 packet"})
                    return

                seq = parsed["seq"]
                run_id = parsed["run_id"]
                if self.run_id is None:
                    self.run_id = run_id
                    self.events.appendleft({"time": now, "kind": "SYNC", "detail": f"run 0x{run_id:08x}"})
                elif run_id != self.run_id:
                    active_age = None if self.last_seen is None else now - self.last_seen
                    can_switch = self.run_switch_idle_sec > 0 and active_age is not None and active_age >= self.run_switch_idle_sec
                    if not can_switch:
                        self.ignored_packets += 1
                        self.packet_marks.append({"kind": "old", "seq": seq, "time": now})
                        self.events.appendleft({
                            "time": now,
                            "kind": "OLD",
                            "detail": f"ignored run 0x{run_id:08x} while 0x{self.run_id:08x} is active",
                        })
                        return
                    self.reset_stream_unlocked(now, run_id, f"new run 0x{run_id:08x}")

                if self.last_seq is not None and seq <= self.last_seq:
                    self.ignored_packets += 1
                    self.packet_marks.append({"kind": "old", "seq": seq, "time": now})
                    self.events.appendleft({"time": now, "kind": "OLD", "detail": f"ignored seq {seq} after {self.last_seq}"})
                    return

                if self.last_seq is not None and seq > self.last_seq + 1:
                    missing = seq - self.last_seq - 1
                    self.missing_packets += missing
                    self.packet_marks.append({"kind": "miss", "seq": seq, "time": now})
                    self.events.appendleft({"time": now, "kind": "MISS", "detail": f"{missing} sequence gap(s)"})
                self.last_seq = seq
                self.allowed_packets += 1
                self.last_seen = now
                self.sample_rate = parsed["sample_rate"]
                self.sine_hz = parsed["sine_hz"]
                self.samples.extend(parsed["samples"])
                self.packet_marks.append({"kind": "allow", "seq": seq, "time": now})
                self.events.appendleft({"time": now, "kind": "ALLOW", "detail": f"seq {seq}"})
                if self.decoy_every > 0 and seq % self.decoy_every == 0:
                    self.expected_drops += 1
                    self.packet_marks.append({"kind": "drop", "seq": seq, "time": now})
                    self.events.appendleft({"time": now, "kind": "DROP", "detail": f"decoy after seq {seq} should be blocked"})
                self.update_rate(now)
                return

            if TCP in pkt and pkt[TCP].dport == 23:
                self.decoy_leaks += 1
                self.packet_marks.append({"kind": "leak", "seq": self.last_seq, "time": now})
                self.events.appendleft({"time": now, "kind": "LEAK", "detail": "TCP/23 reached PC2"})
                return

            if UDP in pkt and pkt[UDP].dport != self.file_port and Raw in pkt:
                payload = bytes(pkt[Raw].load)
                if b"FW-SINE-DECOY-DROP" in payload:
                    self.decoy_leaks += 1
                    self.packet_marks.append({"kind": "leak", "seq": self.last_seq, "time": now})
                    self.events.appendleft({"time": now, "kind": "LEAK", "detail": "UDP decoy reached PC2"})
                    return

            self.other_packets += 1

    def update_rate(self, now):
        if now - self.last_rate_time >= 0.5:
            delta_packets = self.allowed_packets - self.last_rate_packets
            delta_time = now - self.last_rate_time
            self.rate_history.append(delta_packets / max(delta_time, 0.001))
            self.last_rate_packets = self.allowed_packets
            self.last_rate_time = now

    def set_error(self, error):
        with self.lock:
            self.sniff_error = error

    def snapshot(self):
        with self.lock:
            elapsed = max(time.time() - self.started_at, 0.001)
            last_age = None if self.last_seen is None else time.time() - self.last_seen
            return {
                "allowed_packets": self.allowed_packets,
                "expected_drops": self.expected_drops,
                "decoy_leaks": self.decoy_leaks,
                "other_packets": self.other_packets,
                "missing_packets": self.missing_packets,
                "ignored_packets": self.ignored_packets,
                "run_id": "-" if self.run_id is None else f"0x{self.run_id:08x}",
                "last_seq": self.last_seq if self.last_seq is not None else "-",
                "last_age": last_age,
                "packets_per_second": self.allowed_packets / elapsed,
                "sample_rate": self.sample_rate,
                "sine_hz": self.sine_hz,
                "samples": list(self.samples),
                "packet_marks": list(self.packet_marks),
                "rate_history": list(self.rate_history),
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
.head-row { display: flex; align-items: center; justify-content: space-between; gap: 14px; flex-wrap: wrap; }
button { border: 1px solid #b7c4d4; background: #fff; color: var(--ink); border-radius: 7px; min-height: 36px; padding: 0 12px; font-weight: 650; cursor: pointer; }
button:hover { border-color: var(--blue); color: var(--blue); }
main { padding: 18px 22px 28px; display: grid; gap: 14px; }
.metrics { display: grid; grid-template-columns: repeat(7, minmax(120px, 1fr)); gap: 12px; }
.metric, .panel { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; }
.metric { padding: 13px 15px; }
.metric .label { color: var(--muted); font-size: 12px; text-transform: uppercase; }
.metric .value { margin-top: 7px; font-size: 27px; font-weight: 750; }
.metric.good .value { color: var(--green); }
.metric.bad .value { color: var(--red); }
.grid { display: grid; grid-template-columns: minmax(0, 1fr) minmax(300px, 0.45fr); gap: 14px; }
.panel { padding: 15px; min-width: 0; }
.panel h2 { margin: 0 0 12px; font-size: 16px; }
canvas { width: 100%; display: block; border: 1px solid var(--line); border-radius: 8px; background: #08111f; }
#wave { height: 300px; }
#rate { height: 120px; margin-top: 12px; }
.packet-strip {
  display: grid;
  grid-template-columns: repeat(60, minmax(7px, 1fr));
  gap: 4px;
  margin: 12px 0;
}
.packet {
  height: 18px;
  border-radius: 4px;
  background: #d8e0ea;
  border: 1px solid transparent;
}
.packet.allow { background: var(--green); box-shadow: 0 0 0 2px rgba(22, 135, 93, 0.12); }
.packet.drop { background: var(--red); opacity: 0.35; border-color: var(--red); }
.packet.leak { background: var(--red); box-shadow: 0 0 0 2px rgba(189, 58, 50, 0.25); }
.packet.miss { background: var(--amber); }
.packet.old { background: #7f8da1; opacity: 0.55; }
.decision-legend { display: flex; flex-wrap: wrap; gap: 12px; color: var(--muted); font-size: 12px; }
.decision-legend span::before { content: ""; display: inline-block; width: 10px; height: 10px; border-radius: 3px; margin-right: 5px; background: #d8e0ea; }
.decision-legend .allow-key::before { background: var(--green); }
.decision-legend .drop-key::before { background: var(--red); opacity: 0.35; }
.decision-legend .leak-key::before { background: var(--red); }
.decision-legend .miss-key::before { background: var(--amber); }
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
  <div class="head-row">
    <div>
      <h1>FPGA Firewall Continuous Sine Demo</h1>
      <div class="sub">PC1 sends an allowed sine stream plus blocked decoys. PC2 should see a clean live waveform and zero decoy leaks.</div>
    </div>
    <button id="resetButton" type="button">Restart dashboard</button>
  </div>
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
    <div class="metric"><div class="label">Expected drops</div><div class="value" id="drops">0</div></div>
    <div class="metric bad"><div class="label">Leaks</div><div class="value" id="leaks">0</div></div>
    <div class="metric"><div class="label">Missing seq</div><div class="value" id="missing">0</div></div>
    <div class="metric"><div class="label">Packets/sec</div><div class="value" id="pps">0</div></div>
    <div class="metric"><div class="label">Last seq</div><div class="value" id="lastSeq">-</div></div>
    <div class="metric"><div class="label">Run ID</div><div class="value" id="runId">-</div></div>
    <div class="metric"><div class="label">Ignored old</div><div class="value" id="ignored">0</div></div>
  </section>
  <section class="grid">
    <div class="panel">
      <h2>Received Sine Wave</h2>
      <canvas id="wave" width="1200" height="360"></canvas>
      <div class="packet-strip" id="packetStrip"></div>
      <div class="decision-legend"><span class="allow-key">Allowed arrived</span><span class="drop-key">Expected decoy drop</span><span class="leak-key">Blocked traffic leaked</span><span class="miss-key">Sequence gap</span></div>
      <canvas id="rate" width="1200" height="160"></canvas>
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
const rateCanvas = document.getElementById("rate");
const rateCtx = rateCanvas.getContext("2d");
const fields = {
  allowed: document.getElementById("allowed"),
  drops: document.getElementById("drops"),
  leaks: document.getElementById("leaks"),
  missing: document.getElementById("missing"),
  pps: document.getElementById("pps"),
  lastSeq: document.getElementById("lastSeq"),
  runId: document.getElementById("runId"),
  ignored: document.getElementById("ignored"),
  events: document.getElementById("events"),
  status: document.getElementById("statusLine"),
  error: document.getElementById("error"),
  packetStrip: document.getElementById("packetStrip"),
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

function drawRate(history) {
  const w = rateCanvas.width;
  const h = rateCanvas.height;
  rateCtx.clearRect(0, 0, w, h);
  rateCtx.fillStyle = "#08111f";
  rateCtx.fillRect(0, 0, w, h);
  rateCtx.strokeStyle = "#1a2d46";
  rateCtx.lineWidth = 1;
  for (let y = 0; y <= h; y += h / 4) {
    rateCtx.beginPath();
    rateCtx.moveTo(0, y);
    rateCtx.lineTo(w, y);
    rateCtx.stroke();
  }
  const maxVal = Math.max(5, ...history);
  rateCtx.strokeStyle = "#66a7ff";
  rateCtx.lineWidth = 2;
  rateCtx.beginPath();
  if (!history.length) {
    rateCtx.moveTo(0, h - 8);
    rateCtx.lineTo(w, h - 8);
  } else {
    history.forEach((value, i) => {
      const x = (i / Math.max(history.length - 1, 1)) * w;
      const y = h - 10 - (value / maxVal) * (h - 24);
      if (i === 0) rateCtx.moveTo(x, y);
      else rateCtx.lineTo(x, y);
    });
  }
  rateCtx.stroke();
  rateCtx.fillStyle = "#9eb3ca";
  rateCtx.font = "16px Segoe UI";
  rateCtx.fillText("packets/sec", 12, 24);
}

function renderPacketStrip(marks) {
  const shown = marks.slice(-60);
  fields.packetStrip.innerHTML = shown.map(mark => {
    const title = `${mark.kind} seq ${mark.seq ?? "-"}`;
    return `<div class="packet ${mark.kind}" title="${title}"></div>`;
  }).join("");
}

async function refresh() {
  const res = await fetch("/api/state", {cache: "no-store"});
  const data = await res.json();
  fields.allowed.textContent = data.allowed_packets;
  fields.drops.textContent = data.expected_drops;
  fields.leaks.textContent = data.decoy_leaks;
  fields.missing.textContent = data.missing_packets;
  fields.pps.textContent = data.packets_per_second.toFixed(1);
  fields.lastSeq.textContent = data.last_seq;
  fields.runId.textContent = data.run_id;
  fields.ignored.textContent = data.ignored_packets;
  fields.status.textContent = data.sample_rate ? `${data.sine_hz} Hz sine, sample rate ${data.sample_rate} Hz` : "Waiting for packets...";
  fields.error.textContent = data.sniff_error || "";
  fields.events.innerHTML = data.events.map(ev => {
    const cls = ev.kind === "LEAK" ? "leak" : "allow";
    return `<div class="event"><div class="note">${ev.time}</div><div class="kind ${cls}">${ev.kind}</div><div>${ev.detail}</div></div>`;
  }).join("") || `<p class="note">No packets yet.</p>`;
  drawWave(data.samples);
  drawRate(data.rate_history);
  renderPacketStrip(data.packet_marks);
}

async function resetDashboard() {
  await fetch("/api/reset", {method: "POST"});
  await refresh();
}

document.getElementById("resetButton").addEventListener("click", resetDashboard);
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

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path == "/api/reset":
            self.state.reset()
            self.send_text(HTTPStatus.OK, json.dumps({"ok": True}), "application/json; charset=utf-8")
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
    parser.add_argument("--decoy-every", type=int, default=4, help="Sender decoy cadence used to draw expected drop markers.")
    parser.add_argument("--run-switch-idle-sec", type=float, default=0.0, help="Switch to a different run ID only after this many idle seconds; 0 disables auto-switch.")
    parser.add_argument("--accept-legacy", action="store_true", help="Accept older FWSINE1 packets that do not carry a run ID.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8090)
    args = parser.parse_args()

    state = SineState(args.file_port, args.decoy_every, args.run_switch_idle_sec, args.accept_legacy)
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
