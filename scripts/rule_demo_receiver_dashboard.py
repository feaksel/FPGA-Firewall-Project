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
    from scapy.all import Raw, TCP, UDP, sniff
except ImportError:
    print("Scapy is required. Install it with: pip install scapy", file=sys.stderr)
    sys.exit(1)


ALLOW_MARKER = b"FW-DEMO-ALLOW"
ALLOW_SSH_MARKER = b"FW-DEMO-ALLOW-SSH"
DROP_TCP_MARKER = b"FW-DEMO-DROP-TCP23"
SEQ_RE = re.compile(rb"seq=(\d+)")


def parse_seq(payload):
    match = SEQ_RE.search(payload)
    return None if match is None else int(match.group(1))


class DemoState:
    def __init__(self):
        self.lock = threading.Lock()
        self.reset_unlocked()

    def reset_unlocked(self):
        self.started_at = time.time()
        self.allowed = 0
        self.allowed_ssh = 0
        self.allowed_total = 0
        self.leaks = 0
        self.other = 0
        self.missing = 0
        self.last_seq = None
        self.last_seen = None
        self.last_rate_time = time.time()
        self.last_rate_allowed = 0
        self.rate_history = deque(maxlen=80)
        self.events = deque(maxlen=80)
        self.marks = deque(maxlen=120)
        self.sniff_error = ""

    def reset(self):
        with self.lock:
            self.reset_unlocked()

    def event(self, kind, detail, seq=None):
        now = time.time()
        self.events.appendleft({"time": now, "kind": kind, "detail": detail})
        self.marks.append({"time": now, "kind": kind.lower(), "seq": seq})

    def update_rate(self, now):
        if now - self.last_rate_time >= 0.5:
            delta = self.allowed_total - self.last_rate_allowed
            elapsed = max(now - self.last_rate_time, 0.001)
            self.rate_history.append(delta / elapsed)
            self.last_rate_allowed = self.allowed_total
            self.last_rate_time = now

    def record_packet(self, pkt):
        now = time.time()
        with self.lock:
            payload = bytes(pkt[Raw].load) if Raw in pkt else b""
            if UDP in pkt and pkt[UDP].dport == 80 and ALLOW_MARKER in payload:
                seq = parse_seq(payload)
                if seq is not None and self.last_seq is not None and seq > self.last_seq + 1:
                    gap = seq - self.last_seq - 1
                    self.missing += gap
                    self.event("MISS", f"{gap} missing allow seq", seq)
                if seq is not None:
                    self.last_seq = seq
                self.allowed += 1
                self.allowed_total += 1
                self.last_seen = now
                self.event("ALLOW", f"UDP/80 seq {seq}", seq)
                self.update_rate(now)
                return

            if TCP in pkt and pkt[TCP].dport == 22 and ALLOW_SSH_MARKER in payload:
                seq = parse_seq(payload)
                self.allowed_ssh += 1
                self.allowed_total += 1
                self.last_seen = now
                if seq is not None:
                    self.last_seq = seq
                self.event("ALLOW", f"TCP/22 SSH seq {seq}", seq)
                self.update_rate(now)
                return

            if TCP in pkt and pkt[TCP].dport == 23 and DROP_TCP_MARKER in payload:
                self.leaks += 1
                self.event("LEAK", "TCP/23 drop packet reached PC2", parse_seq(payload))
                return

            self.other += 1

    def set_error(self, error):
        with self.lock:
            self.sniff_error = error

    def snapshot(self):
        with self.lock:
            elapsed = max(time.time() - self.started_at, 0.001)
            return {
                "allowed": self.allowed,
                "allowed_ssh": self.allowed_ssh,
                "allowed_total": self.allowed_total,
                "expected_drops": max(self.allowed, self.allowed_ssh),
                "leaks": self.leaks,
                "missing": self.missing,
                "other": self.other,
                "last_seq": "-" if self.last_seq is None else self.last_seq,
                "packets_per_second": self.allowed_total / elapsed,
                "last_age": None if self.last_seen is None else time.time() - self.last_seen,
                "rate_history": list(self.rate_history),
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
            }


HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>FPGA Firewall Rule Demo</title>
<style>
:root { --bg:#f4f6f8; --panel:#fff; --ink:#17202b; --muted:#657386; --line:#d6dde7; --green:#15825a; --red:#bd3a32; --blue:#1769c2; --amber:#a66f00; }
* { box-sizing:border-box; }
body { margin:0; font-family:"Segoe UI", Arial, sans-serif; background:var(--bg); color:var(--ink); }
header { background:var(--panel); border-bottom:1px solid var(--line); padding:18px 22px; display:flex; justify-content:space-between; gap:14px; align-items:center; flex-wrap:wrap; }
h1 { margin:0 0 4px; font-size:22px; }
.sub, .note { color:var(--muted); font-size:13px; }
button { border:1px solid #b7c4d4; background:#fff; color:var(--ink); border-radius:7px; min-height:36px; padding:0 12px; font-weight:650; cursor:pointer; }
button:hover { border-color:var(--blue); color:var(--blue); }
main { padding:18px 22px 28px; display:grid; gap:14px; }
.flow { display:grid; grid-template-columns:1fr 46px 1fr 46px 1fr 46px 1fr 46px 1fr; gap:8px; align-items:center; }
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
.grid { display:grid; grid-template-columns:minmax(0, 1fr) minmax(300px, .45fr); gap:14px; }
.panel { padding:15px; min-width:0; }
h2 { margin:0 0 12px; font-size:16px; }
.strip { display:grid; grid-template-columns:repeat(60, minmax(7px,1fr)); gap:4px; margin:8px 0 14px; }
.mark { height:28px; border-radius:4px; background:#d8e0ea; }
.mark.allow { background:var(--green); }
.mark.leak { background:var(--red); }
.mark.miss { background:var(--amber); }
canvas { width:100%; height:145px; display:block; border:1px solid var(--line); border-radius:8px; background:#08111f; }
.events { display:grid; gap:8px; max-height:430px; overflow:auto; }
.event { display:grid; grid-template-columns:64px 58px minmax(0,1fr); gap:8px; padding:9px; border:1px solid var(--line); border-radius:7px; align-items:center; }
.kind { font-weight:800; font-size:12px; }
.kind.ALLOW { color:var(--green); }
.kind.LEAK { color:var(--red); }
.kind.MISS { color:var(--amber); }
.ok { color:var(--green); font-weight:750; }
.fail { color:var(--red); font-weight:750; }
@media (max-width:900px){ .flow,.metrics,.grid{grid-template-columns:1fr}.link{height:20px;width:2px;justify-self:center} }
</style>
</head>
<body>
<header>
  <div><h1>FPGA Firewall Rule Demo</h1><div class="sub">PC1 sends known rule packets. PC2 should receive SSH allow packets, with zero TCP/23 leaks.</div></div>
  <button id="reset">Restart dashboard</button>
</header>
<main>
  <section class="flow">
    <div class="node"><div class="label">PC1</div><div class="value">Rule packets</div></div><div class="link"></div>
    <div class="node"><div class="label">W5500 A</div><div class="value">Ingress RX</div></div><div class="link"></div>
    <div class="node"><div class="label">FPGA</div><div class="value">Allow/drop rules</div></div><div class="link"></div>
    <div class="node"><div class="label">W5500 B</div><div class="value">Egress TX</div></div><div class="link"></div>
    <div class="node"><div class="label">PC2</div><div class="value">Allowed only</div></div>
  </section>
  <section class="metrics">
    <div class="metric good"><div class="label">Total allowed</div><div class="value" id="totalAllowed">0</div></div>
    <div class="metric good"><div class="label">SSH allow received</div><div class="value" id="sshAllowed">0</div></div>
    <div class="metric"><div class="label">UDP allow received</div><div class="value" id="allowed">0</div></div>
    <div class="metric"><div class="label">Expected drops</div><div class="value" id="drops">0</div></div>
    <div class="metric bad"><div class="label">Drop leaks</div><div class="value" id="leaks">0</div></div>
    <div class="metric"><div class="label">Missing allow seq</div><div class="value" id="missing">0</div></div>
    <div class="metric"><div class="label">Allowed/sec</div><div class="value" id="pps">0.0</div></div>
    <div class="metric"><div class="label">Last seq</div><div class="value" id="lastSeq">-</div></div>
  </section>
  <section class="grid">
    <div class="panel">
      <h2>Live Rule Result</h2>
      <div id="verdict" class="note">Waiting for allowed packets...</div>
      <div class="strip" id="strip"></div>
      <canvas id="rate" width="1100" height="180"></canvas>
      <p class="note">Green = allowed packet arrived. Red = blocked packet leaked. Amber = missing allowed sequence.</p>
    </div>
    <div class="panel">
      <h2>Recent Events</h2>
      <div class="events" id="events"></div>
      <p class="note" id="error"></p>
    </div>
  </section>
</main>
<script>
const ids = ["totalAllowed","allowed","sshAllowed","drops","leaks","missing","pps","lastSeq","strip","events","error","verdict"];
const el = Object.fromEntries(ids.map(id => [id, document.getElementById(id)]));
const canvas = document.getElementById("rate");
const ctx = canvas.getContext("2d");
function drawRate(values) {
  const w=canvas.width,h=canvas.height;
  ctx.clearRect(0,0,w,h); ctx.fillStyle="#08111f"; ctx.fillRect(0,0,w,h);
  ctx.strokeStyle="#1a2d46"; ctx.lineWidth=1;
  for(let y=0;y<=h;y+=h/4){ctx.beginPath();ctx.moveTo(0,y);ctx.lineTo(w,y);ctx.stroke();}
  const max=Math.max(2,...values); ctx.strokeStyle="#66a7ff"; ctx.lineWidth=2; ctx.beginPath();
  if(!values.length){ctx.moveTo(0,h-10);ctx.lineTo(w,h-10);} else values.forEach((v,i)=>{const x=i/Math.max(values.length-1,1)*w; const y=h-10-(v/max)*(h-24); if(i===0)ctx.moveTo(x,y);else ctx.lineTo(x,y);});
  ctx.stroke(); ctx.fillStyle="#9eb3ca"; ctx.font="16px Segoe UI"; ctx.fillText("allowed packets/sec",12,24);
}
async function refresh(){
  const r=await fetch("/api/state",{cache:"no-store"}); const d=await r.json();
  el.totalAllowed.textContent=d.allowed_total; el.allowed.textContent=d.allowed; el.sshAllowed.textContent=d.allowed_ssh; el.drops.textContent=d.expected_drops; el.leaks.textContent=d.leaks; el.missing.textContent=d.missing; el.pps.textContent=d.packets_per_second.toFixed(1); el.lastSeq.textContent=d.last_seq;
  el.verdict.innerHTML = d.allowed_total === 0 ? "Waiting for allowed packets..." : (d.leaks === 0 ? '<span class="ok">PASS: allowed packets are arriving and blocked profiles are absent.</span>' : '<span class="fail">FAIL: a blocked packet reached PC2.</span>');
  el.strip.innerHTML=d.marks.slice(-60).map(m=>`<div class="mark ${m.kind}" title="${m.kind} seq ${m.seq ?? "-"}"></div>`).join("");
  el.events.innerHTML=d.events.map(e=>`<div class="event"><div class="note">${e.time}</div><div class="kind ${e.kind}">${e.kind}</div><div>${e.detail}</div></div>`).join("") || '<p class="note">No packets yet.</p>';
  el.error.textContent=d.sniff_error || ""; drawRate(d.rate_history);
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
        sniff(iface=iface, prn=state.record_packet, store=False)
    except Exception as exc:
        state.set_error(str(exc))


def main():
    parser = argparse.ArgumentParser(description="PC2 browser dashboard for the simple FPGA firewall rule demo.")
    parser.add_argument("--iface", required=True, help="Windows Ethernet interface connected to W5500 B.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8091)
    args = parser.parse_args()

    state = DemoState()
    Handler.state = state
    thread = threading.Thread(target=sniff_worker, args=(state, args.iface), daemon=True)
    thread.start()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Rule demo dashboard running at http://{args.host}:{args.port}")
    print("Stop with Ctrl+C.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
