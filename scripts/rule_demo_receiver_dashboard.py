#!/usr/bin/env python3
import argparse
import json
import re
import sys
import threading
import time
from collections import deque
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

try:
    from scapy.all import PcapNgReader, Raw, UDP, get_if_list, sniff
except ImportError:
    print("Scapy is required. Install it with: pip install scapy", file=sys.stderr)
    sys.exit(1)


ALLOW80_MARKER = b"FW-DEMO-ALLOW80"
ALLOW5001_MARKERS = (b"FWFILE1\x00", b"FWSINE2\x00", b"FW-DEMO-ALLOW5001")
BLOCK_MARKERS = (b"FW-BLOCK", b"FW-DEMO-DROP")
SEQ_RE = re.compile(rb"seq=(\d+)")
TELEM_RE = re.compile(r"([A-Z0-9]+)=([0-9A-Fa-f]+|[0-9A-Fa-f][AD][E.])")
APP_VERSION = "udp-policy-gateway-2026-05-05"
RATE_SAMPLE_SEC = 0.5
RATE_WINDOW_SEC = 30.0


def parse_seq(payload):
    match = SEQ_RE.search(payload)
    return None if match is None else int(match.group(1))


def packet_bytes(pkt):
    try:
        return bytes(pkt)
    except Exception:
        return b""


def packet_payload(pkt):
    if Raw in pkt:
        return bytes(pkt[Raw].load)
    return packet_bytes(pkt)


def parse_telemetry_line(line):
    parsed = {}
    for key, value in TELEM_RE.findall(line.strip()):
        if key == "R" and len(value) >= 2:
            parsed["last_rule"] = value[0]
            parsed["last_action"] = value[1]
            parsed["tx_status"] = value[2] if len(value) > 2 else "."
        else:
            try:
                parsed[key] = int(value, 16)
            except ValueError:
                pass
    return parsed


class DemoState:
    def __init__(self):
        self.lock = threading.Lock()
        self.reset_unlocked()

    def reset_unlocked(self):
        self.started_at = time.time()
        self.allow80 = 0
        self.allow5001 = 0
        self.allowed_total = 0
        self.file_seen = 0
        self.sine_seen = 0
        self.leaks = 0
        self.block_leaks = 0
        self.drop5002_leaks = 0
        self.other = 0
        self.total_seen = 0
        self.demo_seen = 0
        self.last_seq = None
        self.last_seen = None
        self.last_rate_time = self.started_at
        self.last_rate_allowed = 0
        self.rate_history = deque(maxlen=int(RATE_WINDOW_SEC / RATE_SAMPLE_SEC) + 8)
        self.events = deque(maxlen=90)
        self.marks = deque(maxlen=140)
        self.sniff_error = ""
        self.sniff_target = ""
        self.telemetry_error = ""
        self.telemetry_target = ""
        self.fpga = {}
        self.fpga_last_line = ""
        self.fpga_last_seen = None

    def reset(self):
        with self.lock:
            self.reset_unlocked()

    def event(self, kind, detail, seq=None):
        now = time.time()
        self.events.appendleft({"time": now, "kind": kind, "detail": detail})
        self.marks.append({"time": now, "kind": kind.lower(), "seq": seq})

    def update_rate(self, now):
        if now - self.last_rate_time >= RATE_SAMPLE_SEC:
            delta = self.allowed_total - self.last_rate_allowed
            elapsed = max(now - self.last_rate_time, 0.001)
            self.rate_history.append({
                "t": now - self.started_at,
                "v": delta / elapsed,
            })
            self.last_rate_allowed = self.allowed_total
            self.last_rate_time = now

    def record_packet(self, pkt):
        now = time.time()
        with self.lock:
            self.total_seen += 1
            payload = packet_payload(pkt)
            searchable = payload + packet_bytes(pkt)
            seq = parse_seq(searchable)
            udp_dport = int(pkt[UDP].dport) if UDP in pkt else None

            if any(marker in searchable for marker in BLOCK_MARKERS):
                self.demo_seen += 1
                self.leaks += 1
                if udp_dport == 5002 or b"UDP5002" in searchable:
                    self.drop5002_leaks += 1
                    self.event("LEAK", f"UDP/5002 drop leaked seq {seq}", seq)
                else:
                    self.block_leaks += 1
                    self.event("LEAK", f"content-block leaked on UDP/{udp_dport} seq {seq}", seq)
                return

            if udp_dport == 80 or ALLOW80_MARKER in searchable:
                self.demo_seen += 1
                self.allow80 += 1
                self.allowed_total += 1
                self.last_seen = now
                if seq is not None:
                    self.last_seq = seq
                self.event("ALLOW", f"UDP/80 allow seq {seq}", seq)
                return

            if udp_dport == 5001 or any(marker in searchable for marker in ALLOW5001_MARKERS):
                self.demo_seen += 1
                self.allow5001 += 1
                self.allowed_total += 1
                if b"FWFILE1\x00" in searchable:
                    self.file_seen += 1
                if b"FWSINE2\x00" in searchable:
                    self.sine_seen += 1
                self.last_seen = now
                if seq is not None:
                    self.last_seq = seq
                self.event("ALLOW", f"UDP/5001 data seq {seq}", seq)
                return

            self.other += 1

    def record_telemetry(self, line):
        parsed = parse_telemetry_line(line)
        if not parsed:
            return
        with self.lock:
            self.fpga.update(parsed)
            self.fpga_last_line = line.strip()
            self.fpga_last_seen = time.time()

    def set_error(self, error):
        with self.lock:
            self.sniff_error = error

    def set_sniff_target(self, target):
        with self.lock:
            self.sniff_target = str(target)

    def set_telemetry_error(self, error):
        with self.lock:
            self.telemetry_error = error

    def set_telemetry_target(self, target):
        with self.lock:
            self.telemetry_target = str(target)

    def snapshot(self):
        with self.lock:
            now = time.time()
            self.update_rate(now)
            elapsed = max(now - self.started_at, 0.001)
            return {
                "allow80": self.allow80,
                "allow5001": self.allow5001,
                "allowed_total": self.allowed_total,
                "file_seen": self.file_seen,
                "sine_seen": self.sine_seen,
                "leaks": self.leaks,
                "block_leaks": self.block_leaks,
                "drop5002_leaks": self.drop5002_leaks,
                "other": self.other,
                "total_seen": self.total_seen,
                "demo_seen": self.demo_seen,
                "last_seq": "-" if self.last_seq is None else self.last_seq,
                "packets_per_second": self.allowed_total / elapsed,
                "last_age": None if self.last_seen is None else now - self.last_seen,
                "elapsed_sec": elapsed,
                "rate_history": list(self.rate_history),
                "rate_window_sec": RATE_WINDOW_SEC,
                "marks": list(self.marks),
                "events": [
                    {
                        "time": time.strftime("%H:%M:%S", time.localtime(event["time"])),
                        "kind": event["kind"],
                        "detail": event["detail"],
                    }
                    for event in list(self.events)
                ],
                "sniff_error": self.sniff_error,
                "sniff_target": self.sniff_target,
                "telemetry_error": self.telemetry_error,
                "telemetry_target": self.telemetry_target,
                "fpga": dict(self.fpga),
                "fpga_last_line": self.fpga_last_line,
                "fpga_age": None if self.fpga_last_seen is None else now - self.fpga_last_seen,
                "version": APP_VERSION,
            }


HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>FPGA UDP Policy Gateway</title>
<style>
:root { --bg:#f5f7fb; --panel:#fff; --ink:#15202b; --muted:#607086; --line:#d8e0ea; --green:#147a52; --red:#b73535; --blue:#1769c2; --amber:#a66f00; --violet:#6b4fb3; }
* { box-sizing:border-box; }
body { margin:0; font-family:"Segoe UI", Arial, sans-serif; background:var(--bg); color:var(--ink); }
header { background:var(--panel); border-bottom:1px solid var(--line); padding:18px 22px; display:flex; justify-content:space-between; gap:14px; align-items:center; flex-wrap:wrap; }
h1 { margin:0 0 4px; font-size:22px; letter-spacing:0; }
.sub, .note { color:var(--muted); font-size:13px; }
button { border:1px solid #b7c4d4; background:#fff; color:var(--ink); border-radius:7px; min-height:36px; padding:0 12px; font-weight:650; cursor:pointer; }
button:hover { border-color:var(--blue); color:var(--blue); }
main { padding:18px 22px 28px; display:grid; gap:14px; }
.flow { display:grid; grid-template-columns:1fr 42px 1fr 42px 1fr 42px 1fr 42px 1fr; gap:8px; align-items:center; }
.node, .panel, .metric { background:var(--panel); border:1px solid var(--line); border-radius:8px; }
.node { min-height:70px; padding:10px; }
.label { color:var(--muted); font-size:11px; text-transform:uppercase; }
.value { margin-top:6px; font-weight:750; }
.link { height:2px; background:#9eb3ca; position:relative; }
.link:after { content:""; position:absolute; right:-1px; top:-4px; border-left:8px solid #9eb3ca; border-top:5px solid transparent; border-bottom:5px solid transparent; }
.metrics { display:grid; grid-template-columns:repeat(6, minmax(120px, 1fr)); gap:12px; }
.metric { padding:13px 15px; }
.metric .value { font-size:28px; }
.good .value { color:var(--green); }
.bad .value { color:var(--red); }
.grid { display:grid; grid-template-columns:minmax(0, 1.1fr) minmax(320px, .9fr); gap:14px; }
.panel { padding:15px; min-width:0; }
h2 { margin:0 0 12px; font-size:16px; }
.strip { display:grid; grid-template-columns:repeat(70, minmax(7px,1fr)); gap:4px; margin:8px 0 14px; }
.mark { height:26px; border-radius:4px; background:#d8e0ea; }
.mark.allow { background:var(--green); }
.mark.leak { background:var(--red); }
.mark.info { background:var(--blue); }
canvas { width:100%; height:145px; display:block; border:1px solid var(--line); border-radius:8px; background:#08111f; }
.events { display:grid; gap:8px; max-height:430px; overflow:auto; }
.event { display:grid; grid-template-columns:64px 58px minmax(0,1fr); gap:8px; padding:9px; border:1px solid var(--line); border-radius:7px; align-items:center; }
.kind { font-weight:800; font-size:12px; }
.kind.ALLOW { color:var(--green); }
.kind.LEAK { color:var(--red); }
.kind.INFO { color:var(--blue); }
.ok { color:var(--green); font-weight:750; }
.fail { color:var(--red); font-weight:750; }
.hist { display:grid; gap:9px; }
.barrow { display:grid; grid-template-columns:86px minmax(0,1fr) 80px; gap:8px; align-items:center; }
.barbox { height:18px; border-radius:5px; background:#e6ebf2; overflow:hidden; }
.bar { height:100%; width:0%; background:var(--blue); }
.bar.allow { background:var(--green); }
.bar.drop { background:var(--red); }
.bar.sig { background:var(--violet); }
.mono { font-family:Consolas, "Courier New", monospace; }
@media (max-width:960px){ .flow,.metrics,.grid{grid-template-columns:1fr}.link{height:20px;width:2px;justify-self:center} }
</style>
</head>
<body>
<header>
  <div><h1>FPGA UDP Policy Gateway</h1><div class="sub">Allowed UDP services should arrive on PC2; blocked ports and payload signatures should only move FPGA counters.</div></div>
  <button id="reset">Restart dashboard</button>
</header>
<main>
  <section class="flow">
    <div class="node"><div class="label">PC1</div><div class="value">UDP profiles</div></div><div class="link"></div>
    <div class="node"><div class="label">W5500 A</div><div class="value">UDP sockets</div></div><div class="link"></div>
    <div class="node"><div class="label">FPGA</div><div class="value">Rules + signatures</div></div><div class="link"></div>
    <div class="node"><div class="label">W5500 B</div><div class="value">MACRAW TX</div></div><div class="link"></div>
    <div class="node"><div class="label">PC2</div><div class="value">Allowed only</div></div>
  </section>
  <section class="metrics">
    <div class="metric good"><div class="label">Allowed total</div><div class="value" id="allowedTotal">0</div></div>
    <div class="metric"><div class="label">UDP/80</div><div class="value" id="allow80">0</div></div>
    <div class="metric"><div class="label">UDP/5001</div><div class="value" id="allow5001">0</div></div>
    <div class="metric bad"><div class="label">Leaks</div><div class="value" id="leaks">0</div></div>
    <div class="metric"><div class="label">Allowed/sec</div><div class="value" id="pps">0.0</div></div>
    <div class="metric"><div class="label">FPGA RX</div><div class="value" id="fpgaRx">-</div></div>
  </section>
  <section class="grid">
    <div class="panel">
      <h2>Live Result</h2>
      <div id="verdict" class="note">Waiting for packets...</div>
      <div class="strip" id="strip"></div>
      <canvas id="rate" width="1100" height="180"></canvas>
      <p class="note" id="runtimeInfo"></p>
    </div>
    <div class="panel">
      <h2>FPGA Rule Histogram</h2>
      <div class="hist" id="hist"></div>
      <p class="note mono" id="fpgaLine"></p>
    </div>
  </section>
  <section class="grid">
    <div class="panel">
      <h2>Recent Events</h2>
      <div class="events" id="events"></div>
    </div>
    <div class="panel">
      <h2>Signal Sources</h2>
      <p class="note" id="sources"></p>
      <p class="note" id="error"></p>
    </div>
  </section>
</main>
<script>
const ids = ["allowedTotal","allow80","allow5001","leaks","pps","fpgaRx","strip","events","error","verdict","runtimeInfo","hist","fpgaLine","sources"];
const el = Object.fromEntries(ids.map(id => [id, document.getElementById(id)]));
const canvas = document.getElementById("rate");
const ctx = canvas.getContext("2d");
function drawRate(samples, elapsed, windowSec) {
  const w=canvas.width,h=canvas.height;
  ctx.clearRect(0,0,w,h); ctx.fillStyle="#08111f"; ctx.fillRect(0,0,w,h);
  ctx.strokeStyle="#1a2d46"; ctx.lineWidth=1;
  for(let y=0;y<=h;y+=h/4){ctx.beginPath();ctx.moveTo(0,y);ctx.lineTo(w,y);ctx.stroke();}
  const now = elapsed || 0;
  const span = windowSec || 30;
  const left = Math.max(0, now - span);
  const visible = (samples || []).filter(s => s.t >= left && s.t <= now);
  const max=Math.max(2,...visible.map(s => s.v));
  ctx.strokeStyle="#66a7ff"; ctx.lineWidth=2; ctx.beginPath();
  if(!visible.length){
    ctx.moveTo(0,h-10);ctx.lineTo(w,h-10);
  } else {
    visible.forEach((s,i)=>{
      const x=((s.t-left)/Math.max(span,0.001))*w;
      const y=h-10-(s.v/max)*(h-24);
      if(i===0)ctx.moveTo(x,y);else ctx.lineTo(x,y);
    });
  }
  ctx.stroke();
  ctx.fillStyle="#9eb3ca"; ctx.font="16px Segoe UI";
  ctx.fillText("allowed packets/sec over last " + Math.round(span) + " s",12,24);
  ctx.fillText("-" + Math.round(span) + "s",12,h-10);
  ctx.fillText("now",w-42,h-10);
}
function hexOrDash(value){ return value === undefined ? "-" : value.toString(); }
function drawHistogram(fpga){
  const rows = [
    ["U80", "UDP/80 allow", "allow"],
    ["U51", "UDP/5001 allow", "allow"],
    ["D52", "UDP/5002 drop", "drop"],
    ["SIG", "content block", "sig"],
    ["DEF", "default drop", "drop"],
    ["FIL", "file marker", "sig"],
    ["SIN", "sine marker", "sig"],
  ];
  const max = Math.max(1, ...rows.map(([key]) => fpga[key] || 0));
  el.hist.innerHTML = rows.map(([key,label,cls]) => {
    const value = fpga[key] || 0;
    const pct = Math.max(2, (value / max) * 100);
    return `<div class="barrow"><div class="label">${label}</div><div class="barbox"><div class="bar ${cls}" style="width:${pct}%"></div></div><div class="mono">${value}</div></div>`;
  }).join("");
}
async function refresh(){
  const r=await fetch("/api/state",{cache:"no-store"}); const d=await r.json();
  el.allowedTotal.textContent=d.allowed_total; el.allow80.textContent=d.allow80; el.allow5001.textContent=d.allow5001; el.leaks.textContent=d.leaks; el.pps.textContent=d.packets_per_second.toFixed(1);
  el.fpgaRx.textContent = hexOrDash(d.fpga.RX);
  el.verdict.innerHTML = d.allowed_total === 0 ? "Waiting for allowed UDP packets..." : (d.leaks === 0 ? '<span class="ok">PASS: allowed services arrive and blocked profiles have not leaked.</span>' : '<span class="fail">FAIL: blocked traffic reached PC2.</span>');
  el.runtimeInfo.textContent = `${d.version} | PC2 sniffing: ${d.sniff_target || "starting"}`;
  el.strip.innerHTML=d.marks.slice(-70).map(m=>`<div class="mark ${m.kind}" title="${m.kind} seq ${m.seq ?? "-"}"></div>`).join("");
  el.events.innerHTML=d.events.map(e=>`<div class="event"><div class="note">${e.time}</div><div class="kind ${e.kind}">${e.kind}</div><div>${e.detail}</div></div>`).join("") || '<p class="note">No packets yet.</p>';
  el.error.textContent=[d.sniff_error, d.telemetry_error].filter(Boolean).join(" | ");
  el.sources.textContent=`telemetry: ${d.telemetry_target || "not connected"}${d.fpga_age === null ? "" : `, last ${d.fpga_age.toFixed(1)}s ago`}`;
  el.fpgaLine.textContent=d.fpga_last_line || "No FPGA UART telemetry. Use HEX pages and SignalTap for FPGA-side proof when no TTL USB-UART adapter is connected.";
  drawHistogram(d.fpga); drawRate(d.rate_history, d.elapsed_sec, d.rate_window_sec);
}
async function reset(){ await fetch("/api/reset",{method:"POST"}); await refresh(); }
document.getElementById("reset").addEventListener("click", reset);
refresh(); setInterval(refresh,250);
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
        sniff_ifaces = iface if iface else get_if_list()
        state.event("INFO", f"sniffing {sniff_ifaces if iface else 'all interfaces'}")
        state.set_sniff_target(sniff_ifaces if iface else "all interfaces")
        sniff(iface=sniff_ifaces, prn=state.record_packet, store=False, promisc=True)
    except Exception as exc:
        state.set_error(str(exc))


def telemetry_worker(state, port, baud):
    if not port:
        return
    try:
        import serial
    except ImportError:
        state.set_telemetry_error("pyserial is required for --uart")
        return

    state.set_telemetry_target(f"{port}@{baud}")
    try:
        with serial.Serial(port, baudrate=baud, timeout=1) as ser:
            while True:
                raw = ser.readline()
                if raw:
                    state.record_telemetry(raw.decode("ascii", errors="ignore"))
    except Exception as exc:
        state.set_telemetry_error(str(exc))


def process_pcap(path):
    state = DemoState()
    for pkt in PcapNgReader(path):
        state.record_packet(pkt)
    snapshot = state.snapshot()
    print(f"pcap={path}")
    print(f"total_seen={snapshot['total_seen']}")
    print(f"demo_seen={snapshot['demo_seen']}")
    print(f"allowed_total={snapshot['allowed_total']}")
    print(f"allow80={snapshot['allow80']}")
    print(f"allow5001={snapshot['allow5001']}")
    print(f"drop_leaks={snapshot['leaks']}")
    print(f"file_seen={snapshot['file_seen']}")
    print(f"sine_seen={snapshot['sine_seen']}")
    print("recent_events:")
    for event in snapshot["events"][:12]:
        print(f"  {event['time']} {event['kind']} {event['detail']}")


def main():
    parser = argparse.ArgumentParser(description="PC2 browser dashboard for the FPGA UDP policy gateway demo.")
    parser.add_argument("--iface", help="Windows Ethernet interface connected to W5500 B. Omit to sniff all interfaces.")
    parser.add_argument("--uart", help="Optional FPGA UART COM port for rule histogram telemetry.")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--list-ifaces", action="store_true", help="List Scapy/Npcap interface names and exit.")
    parser.add_argument("--pcap", help="Parse a pcapng file with the same marker logic and exit.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8091)
    args = parser.parse_args()

    if args.list_ifaces:
        print("Scapy interfaces:")
        for iface in get_if_list():
            print(f"  {iface}")
        return

    if args.pcap:
        process_pcap(args.pcap)
        return

    state = DemoState()
    Handler.state = state
    threading.Thread(target=sniff_worker, args=(state, args.iface), daemon=True).start()
    threading.Thread(target=telemetry_worker, args=(state, args.uart, args.baud), daemon=True).start()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"UDP policy gateway dashboard running at http://{args.host}:{args.port}")
    print("Stop with Ctrl+C.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
