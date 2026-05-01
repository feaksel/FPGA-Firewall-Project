#!/usr/bin/env python3
import argparse
import json
import sys
import threading
import time
from collections import OrderedDict, deque
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

try:
    from scapy.all import Ether, Raw, sendp, sniff
except ImportError:
    print("Scapy is required. Install it with: pip install scapy", file=sys.stderr)
    sys.exit(1)

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from send_test_packets import build_packet  # noqa: E402


TEST_SRC_MAC = "00:11:22:33:44:55"

PROFILES = OrderedDict(
    (
        ("udp_allow", {"label": "UDP allow", "expected": "ALLOW", "marker": b"FW-UDP-ALLOW"}),
        ("tcp_drop", {"label": "TCP drop", "expected": "DROP", "marker": b"FW-TCP-DROP"}),
        (
            "tcp_allow_ssh",
            {"label": "TCP SSH allow", "expected": "ALLOW", "marker": b"FW-TCP-ALLOW-SSH"},
        ),
    )
)


class DashboardState:
    def __init__(self, iface):
        self.iface = iface
        self.started_at = datetime.now()
        self.lock = threading.Lock()
        self.sent = {name: 0 for name in PROFILES}
        self.captured = {name: 0 for name in PROFILES}
        self.last_seen = {name: "" for name in PROFILES}
        self.timeline = deque(maxlen=80)
        self.background_count = 0
        self.status = "Starting sniffer"
        self.sniff_error = ""

    def record_sent(self, profile, count):
        now = datetime.now().strftime("%H:%M:%S")
        with self.lock:
            self.sent[profile] += count
            self.timeline.appendleft(
                {
                    "time": now,
                    "direction": "TX",
                    "profile": profile,
                    "expected": PROFILES[profile]["expected"],
                    "detail": f"sent {count}",
                }
            )

    def record_packet(self, pkt):
        now = datetime.now().strftime("%H:%M:%S")
        match = self.classify_packet(pkt)
        with self.lock:
            if match is None:
                self.background_count += 1
                return

            profile = match
            self.captured[profile] += 1
            self.last_seen[profile] = now
            self.timeline.appendleft(
                {
                    "time": now,
                    "direction": "CAP",
                    "profile": profile,
                    "expected": PROFILES[profile]["expected"],
                    "detail": "captured",
                }
            )

    def classify_packet(self, pkt):
        if Ether not in pkt or pkt[Ether].src.lower() != TEST_SRC_MAC:
            return None

        payload = bytes(pkt[Raw].load) if Raw in pkt else b""
        for profile, spec in PROFILES.items():
            if spec["marker"] in payload:
                return profile
        return None

    def snapshot(self):
        with self.lock:
            rows = []
            total_sent = 0
            total_captured = 0
            for profile, spec in PROFILES.items():
                sent = self.sent[profile]
                captured = self.captured[profile]
                total_sent += sent
                total_captured += captured
                rows.append(
                    {
                        "profile": profile,
                        "label": spec["label"],
                        "expected": spec["expected"],
                        "sent": sent,
                        "captured": captured,
                        "missing": max(sent - captured, 0),
                        "last_seen": self.last_seen[profile] or "-",
                    }
                )

            return {
                "iface": self.iface,
                "source_mac": TEST_SRC_MAC,
                "status": self.status,
                "sniff_error": self.sniff_error,
                "started_at": self.started_at.strftime("%H:%M:%S"),
                "total_sent": total_sent,
                "total_captured": total_captured,
                "total_missing": max(total_sent - total_captured, 0),
                "background_count": self.background_count,
                "rows": rows,
                "timeline": list(self.timeline),
            }

    def set_status(self, status, error=""):
        with self.lock:
            self.status = status
            self.sniff_error = error


HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>FPGA Firewall Traffic Dashboard</title>
<style>
:root {
  color-scheme: light;
  --bg: #f5f7fa;
  --panel: #ffffff;
  --ink: #17202a;
  --muted: #687385;
  --line: #d8dee8;
  --accent: #1663b7;
  --allow: #16875d;
  --drop: #bd3a32;
  --warn: #986a13;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  font-family: "Segoe UI", Arial, sans-serif;
  background: var(--bg);
  color: var(--ink);
}
header {
  padding: 18px 22px 12px;
  border-bottom: 1px solid var(--line);
  background: var(--panel);
}
h1 { margin: 0 0 6px; font-size: 22px; font-weight: 650; letter-spacing: 0; }
.sub { color: var(--muted); font-size: 13px; display: flex; gap: 16px; flex-wrap: wrap; }
main { padding: 18px 22px 26px; display: grid; gap: 16px; }
.summary { display: grid; grid-template-columns: repeat(4, minmax(120px, 1fr)); gap: 12px; }
.metric, .panel {
  background: var(--panel);
  border: 1px solid var(--line);
  border-radius: 8px;
}
.metric { padding: 14px 16px; }
.metric .label { color: var(--muted); font-size: 12px; text-transform: uppercase; }
.metric .value { margin-top: 8px; font-size: 30px; font-weight: 700; }
.grid { display: grid; grid-template-columns: minmax(0, 1.5fr) minmax(300px, 0.85fr); gap: 16px; }
.panel { padding: 16px; min-width: 0; }
.panel h2 { margin: 0 0 12px; font-size: 16px; font-weight: 650; }
.panel-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 12px; }
.panel-head h2 { margin: 0; }
.controls { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 12px; align-items: center; }
button {
  border: 1px solid #b7c4d4;
  background: #fff;
  color: var(--ink);
  border-radius: 7px;
  min-height: 36px;
  padding: 0 12px;
  font-weight: 600;
  cursor: pointer;
}
button:hover { border-color: var(--accent); color: var(--accent); }
.ghost-button {
  min-height: 32px;
  padding: 0 10px;
  color: var(--accent);
  border-color: #c8d8ea;
}
input {
  width: 74px;
  height: 36px;
  border: 1px solid #b7c4d4;
  border-radius: 7px;
  padding: 0 9px;
}
table { width: 100%; border-collapse: collapse; font-size: 14px; }
th, td { text-align: left; padding: 10px 8px; border-bottom: 1px solid var(--line); }
th { color: var(--muted); font-size: 12px; text-transform: uppercase; }
.badge { display: inline-block; min-width: 58px; padding: 4px 7px; border-radius: 6px; font-size: 12px; font-weight: 700; }
.allow { color: var(--allow); background: #e6f5ee; }
.drop { color: var(--drop); background: #f8e8e6; }
.timeline { display: grid; gap: 8px; max-height: 430px; overflow: auto; padding-right: 4px; }
.event { display: grid; grid-template-columns: 64px 44px minmax(0, 1fr); gap: 8px; align-items: center; padding: 9px; border: 1px solid var(--line); border-radius: 7px; }
.event .time, .event .dir { color: var(--muted); font-size: 12px; font-weight: 650; }
.event .name { font-weight: 650; overflow-wrap: anywhere; }
.flow-panel { display: grid; grid-template-columns: 1fr; gap: 14px; }
.flow-strip {
  display: grid;
  grid-template-columns: 1fr 64px 1fr 64px 1fr;
  gap: 10px;
  align-items: center;
}
.flow-node {
  border: 1px solid var(--line);
  border-radius: 8px;
  padding: 12px;
  background: #fbfcfe;
  min-height: 76px;
}
.flow-node .node-label { color: var(--muted); font-size: 12px; text-transform: uppercase; }
.flow-node .node-value { margin-top: 7px; font-size: 22px; font-weight: 750; }
.flow-link {
  height: 3px;
  background: linear-gradient(90deg, #cbd7e5, var(--accent));
  position: relative;
}
.flow-link::after {
  content: "";
  position: absolute;
  right: -1px;
  top: -5px;
  border-left: 9px solid var(--accent);
  border-top: 6px solid transparent;
  border-bottom: 6px solid transparent;
}
.bar-chart {
  display: grid;
  grid-template-columns: repeat(24, minmax(5px, 1fr));
  align-items: end;
  gap: 5px;
  height: 120px;
  padding: 12px 10px 8px;
  border: 1px solid var(--line);
  border-radius: 8px;
  background: #fbfcfe;
}
.bar {
  min-height: 3px;
  border-radius: 4px 4px 0 0;
  background: var(--accent);
}
.bar.drop-bar { background: var(--drop); }
.bar.allow-bar { background: var(--allow); }
.legend { display: flex; flex-wrap: wrap; gap: 12px; color: var(--muted); font-size: 12px; }
.legend span::before {
  content: "";
  display: inline-block;
  width: 9px;
  height: 9px;
  border-radius: 3px;
  margin-right: 5px;
  background: var(--accent);
}
.legend .allow-key::before { background: var(--allow); }
.legend .drop-key::before { background: var(--drop); }
.real-demo { display: grid; gap: 14px; }
.inline-strip { display: grid; grid-template-columns: 1fr 46px 1fr 46px 1fr 46px 1fr 46px 1fr; gap: 8px; align-items: center; }
.inline-node {
  border: 1px solid var(--line);
  border-radius: 8px;
  min-height: 82px;
  padding: 11px;
  background: #fbfcfe;
}
.inline-node .label { color: var(--muted); font-size: 11px; text-transform: uppercase; }
.inline-node .value { font-size: 20px; font-weight: 750; margin-top: 8px; }
.inline-link { height: 2px; background: #9eb3ca; position: relative; }
.inline-link::after {
  content: "";
  position: absolute;
  right: -1px;
  top: -4px;
  border-left: 8px solid #9eb3ca;
  border-top: 5px solid transparent;
  border-bottom: 5px solid transparent;
}
.chunk-map { display: grid; grid-template-columns: repeat(32, minmax(7px, 1fr)); gap: 3px; }
.chunk { height: 14px; border-radius: 3px; background: #dbe3ee; }
.chunk.good { background: var(--allow); }
.chunk.drop { background: var(--drop); }
.chunk.wait { background: #c8d2df; }
.demo-grid { display: grid; grid-template-columns: minmax(0, 1fr) minmax(260px, 0.55fr); gap: 12px; }
.command-box { font-family: Consolas, "Courier New", monospace; font-size: 12px; background: #101820; color: #e9f0f7; border-radius: 7px; padding: 10px; overflow-wrap: anywhere; }
.manual-grid { display: grid; grid-template-columns: minmax(0, 1.2fr) minmax(320px, 0.8fr); gap: 16px; }
.manual-shell { display: none; }
.manual-shell.open { display: block; }
.mini-grid { display: grid; grid-template-columns: repeat(3, minmax(160px, 1fr)); gap: 10px; margin-top: 12px; }
.mini {
  border: 1px solid var(--line);
  border-radius: 7px;
  padding: 11px;
  background: #fbfcfe;
}
.mini .title { font-weight: 700; margin-bottom: 5px; }
.switch-code {
  display: inline-block;
  font-family: Consolas, "Courier New", monospace;
  font-weight: 700;
  background: #eef3f9;
  border: 1px solid #d1dce9;
  border-radius: 5px;
  padding: 2px 6px;
}
.hex-readout {
  font-family: Consolas, "Courier New", monospace;
  font-weight: 700;
  letter-spacing: 0;
}
.steps { margin: 0; padding-left: 19px; color: var(--muted); line-height: 1.5; }
.steps li { margin: 5px 0; }
.note { color: var(--muted); font-size: 13px; line-height: 1.45; }
.warning { color: var(--warn); font-weight: 650; }
@media (max-width: 860px) {
  .summary { grid-template-columns: repeat(2, minmax(120px, 1fr)); }
  .grid, .manual-grid, .flow-strip, .inline-strip, .demo-grid { grid-template-columns: 1fr; }
  .flow-link { height: 28px; width: 3px; justify-self: center; background: linear-gradient(180deg, #cbd7e5, var(--accent)); }
  .flow-link::after { right: -5px; top: auto; bottom: -1px; border-top: 9px solid var(--accent); border-left: 6px solid transparent; border-right: 6px solid transparent; border-bottom: 0; }
  .inline-link { height: 22px; width: 2px; justify-self: center; }
  .mini-grid { grid-template-columns: 1fr; }
}
</style>
</head>
<body>
<header>
  <h1>FPGA Firewall Traffic Dashboard</h1>
  <div class="sub">
    <span>Interface: <strong id="iface">-</strong></span>
    <span>Source MAC: <strong id="mac">-</strong></span>
    <span>Status: <strong id="status">connecting</strong></span>
  </div>
</header>
<main>
  <section class="summary">
    <div class="metric"><div class="label">Sent by dashboard</div><div class="value" id="totalSent">0</div></div>
    <div class="metric"><div class="label">Captured on PC</div><div class="value" id="totalCaptured">0</div></div>
    <div class="metric"><div class="label">Not captured yet</div><div class="value" id="totalMissing">0</div></div>
    <div class="metric"><div class="label">Background frames</div><div class="value" id="background">0</div></div>
  </section>
  <section class="grid">
    <div class="panel">
      <h2>Deterministic Test Packets</h2>
      <div class="controls">
        <label class="note">Count <input id="sendCount" type="number" min="1" max="100" value="3"></label>
        <button data-profile="udp_allow">Send UDP allow</button>
        <button data-profile="tcp_drop">Send TCP drop</button>
        <button data-profile="tcp_allow_ssh">Send TCP SSH allow</button>
      </div>
      <table>
        <thead><tr><th>Profile</th><th>Expected</th><th>Sent</th><th>Captured</th><th>Missing</th><th>Last seen</th></tr></thead>
        <tbody id="profileRows"></tbody>
      </table>
      <p class="note">This page shows PC-side send/capture evidence. The FPGA decision truth is still on the board LEDs and HEX pages until we add telemetry from the FPGA.</p>
      <p class="note warning" id="error"></p>
    </div>
    <div class="panel">
      <h2>Recent Events</h2>
      <div class="timeline" id="timeline"></div>
    </div>
  </section>
  <section class="panel flow-panel">
    <div class="panel-head">
      <h2>Packet Flow</h2>
      <button class="ghost-button" id="toggleManual" type="button">Show manual</button>
    </div>
    <div class="flow-strip">
      <div class="flow-node"><div class="node-label">Dashboard TX</div><div class="node-value" id="flowSent">0</div><div class="note">packets sent</div></div>
      <div class="flow-link"></div>
      <div class="flow-node"><div class="node-label">PC capture</div><div class="node-value" id="flowCaptured">0</div><div class="note">test packets seen</div></div>
      <div class="flow-link"></div>
      <div class="flow-node"><div class="node-label">Needs board check</div><div class="node-value" id="flowMissing">0</div><div class="note">not captured yet</div></div>
    </div>
    <div class="bar-chart" id="packetChart"></div>
    <div class="legend"><span class="allow-key">Allow-profile events</span><span class="drop-key">Drop-profile events</span><span>Other test events</span></div>
  </section>
  <section class="panel real-demo">
    <div class="panel-head">
      <h2>Two-Port File Demo Preview</h2>
      <span class="note">Live after W5500 B TX and UART telemetry are connected</span>
    </div>
    <div class="inline-strip">
      <div class="inline-node"><div class="label">PC1 sender</div><div class="value">Chunks</div><div class="note">UDP dst 5001</div></div>
      <div class="inline-link"></div>
      <div class="inline-node"><div class="label">W5500 A</div><div class="value">Ingress</div><div class="note">MACRAW RX</div></div>
      <div class="inline-link"></div>
      <div class="inline-node"><div class="label">FPGA rules</div><div class="value">Allow/drop</div><div class="note">rule hits + counters</div></div>
      <div class="inline-link"></div>
      <div class="inline-node"><div class="label">W5500 B</div><div class="value">Egress</div><div class="note">MACRAW TX</div></div>
      <div class="inline-link"></div>
      <div class="inline-node"><div class="label">PC2 receiver</div><div class="value">SHA-256</div><div class="note">file pass/fail</div></div>
    </div>
    <div class="demo-grid">
      <div>
        <div class="chunk-map" id="chunkMap"></div>
        <p class="note">The final dashboard fills this from receiver/UART telemetry: green means received allowed chunk, red means blocked decoy/error frame, gray means waiting.</p>
      </div>
      <div class="command-box">PC1: py -3.9 .\scripts\file_sender.py --iface "Ethernet" --file demo.mp4<br>PC2: py -3.9 .\scripts\file_receiver.py --iface "Ethernet" --output received_demo.mp4</div>
    </div>
  </section>
  <section class="manual-shell" id="manualShell">
    <div class="manual-grid">
      <div class="panel">
      <h2>Board Display Manual</h2>
      <table>
        <thead><tr><th>SW[3:1]</th><th>HEX3</th><th>HEX2</th><th>HEX1</th><th>HEX0</th><th>Use this for</th></tr></thead>
        <tbody>
          <tr><td><span class="switch-code">000</span></td><td>Adapter state</td><td>Last rule</td><td><span class="hex-readout">A</span> allow / <span class="hex-readout">D</span> drop</td><td>Status bits</td><td>Quick health and last decision</td></tr>
          <tr><td><span class="switch-code">001</span></td><td colspan="4"><span class="hex-readout">HEX3..HEX0 = rx_count[15:0]</span></td><td>Total packets received by FPGA</td></tr>
          <tr><td><span class="switch-code">010</span></td><td colspan="4"><span class="hex-readout">HEX3..HEX0 = allow_count[15:0]</span></td><td>Packets allowed by firewall rules</td></tr>
          <tr><td><span class="switch-code">011</span></td><td colspan="4"><span class="hex-readout">HEX3..HEX0 = drop_count[15:0]</span></td><td>Packets dropped by firewall rules</td></tr>
          <tr><td><span class="switch-code">100</span></td><td>Last rule</td><td><span class="hex-readout">A</span> / <span class="hex-readout">D</span></td><td><span class="hex-readout">F</span> if FIFO overflow</td><td><span class="hex-readout">E</span> error, <span class="hex-readout">1</span> packet seen, <span class="hex-readout">0</span> no packet</td><td>Last packet result summary</td></tr>
        </tbody>
      </table>
      <div class="mini-grid">
        <div class="mini"><div class="title">Known rule IDs</div><div class="note"><span class="hex-readout">0</span> = UDP allow, <span class="hex-readout">1</span> = TCP drop, <span class="hex-readout">2</span> = SSH allow, <span class="hex-readout">E/F</span> = parser/reset marker.</div></div>
        <div class="mini"><div class="title">Page 000 status nibble</div><div class="note"><span class="hex-readout">{overflow, init_error, init_done, rx_seen}</span>. Common values: <span class="hex-readout">2</span> initialized, <span class="hex-readout">3</span> initialized plus packet seen.</div></div>
        <div class="mini"><div class="title">LED quick check</div><div class="note">LEDR0 init done, LEDR1 init error, LEDR2 packet seen, LEDR6..3 adapter state, LEDR7/8/9 low bits of RX/allow/drop.</div></div>
      </div>
      </div>
      <div class="panel">
      <h2>Testing Flow</h2>
      <ol class="steps">
        <li>Keep <span class="switch-code">SW0</span> as the init/start control.</li>
        <li>Set <span class="switch-code">SW[3:1]=001</span> and send packets. RX count should increase.</li>
        <li>Set <span class="switch-code">010</span> and send allow profiles. Allow count should increase.</li>
        <li>Set <span class="switch-code">011</span> and send <span class="hex-readout">tcp_drop</span>. Drop count should increase.</li>
        <li>Set <span class="switch-code">100</span> after each profile to inspect last rule and last action.</li>
      </ol>
      <p class="note">Dashboard counters are PC-side evidence. HEX and LEDs are FPGA-side evidence. If the dashboard says captured but HEX does not move, the packet reached the PC interface but the FPGA path did not observe or classify it as expected.</p>
      </div>
    </div>
  </section>
</main>
<script>
const rowsEl = document.getElementById("profileRows");
const timelineEl = document.getElementById("timeline");
const chartEl = document.getElementById("packetChart");
const manualShell = document.getElementById("manualShell");
const toggleManual = document.getElementById("toggleManual");
const chunkMap = document.getElementById("chunkMap");
const fields = {
  iface: document.getElementById("iface"),
  mac: document.getElementById("mac"),
  status: document.getElementById("status"),
  totalSent: document.getElementById("totalSent"),
  totalCaptured: document.getElementById("totalCaptured"),
  totalMissing: document.getElementById("totalMissing"),
  flowSent: document.getElementById("flowSent"),
  flowCaptured: document.getElementById("flowCaptured"),
  flowMissing: document.getElementById("flowMissing"),
  background: document.getElementById("background"),
  error: document.getElementById("error"),
};

function badge(expected) {
  const cls = expected === "DROP" ? "drop" : "allow";
  return `<span class="badge ${cls}">${expected}</span>`;
}

function render(data) {
  fields.iface.textContent = data.iface;
  fields.mac.textContent = data.source_mac;
  fields.status.textContent = data.status;
  fields.totalSent.textContent = data.total_sent;
  fields.totalCaptured.textContent = data.total_captured;
  fields.totalMissing.textContent = data.total_missing;
  fields.flowSent.textContent = data.total_sent;
  fields.flowCaptured.textContent = data.total_captured;
  fields.flowMissing.textContent = data.total_missing;
  fields.background.textContent = data.background_count;
  fields.error.textContent = data.sniff_error || "";
  rowsEl.innerHTML = data.rows.map(row => `
    <tr>
      <td>${row.label}</td>
      <td>${badge(row.expected)}</td>
      <td>${row.sent}</td>
      <td>${row.captured}</td>
      <td>${row.missing}</td>
      <td>${row.last_seen}</td>
    </tr>
  `).join("");
  timelineEl.innerHTML = data.timeline.map(event => `
    <div class="event">
      <div class="time">${event.time}</div>
      <div class="dir">${event.direction}</div>
      <div><div class="name">${event.profile}</div><div class="note">${event.expected} &middot; ${event.detail}</div></div>
    </div>
  `).join("") || `<p class="note">No test packets yet.</p>`;
  renderChart(data.timeline);
}

function renderChart(timeline) {
  const buckets = Array.from({length: 24}, () => ({total: 0, allow: 0, drop: 0}));
  timeline.slice(0, 48).forEach((event, index) => {
    const bucket = 23 - Math.floor(index / 2);
    if (bucket < 0) return;
    buckets[bucket].total += 1;
    if (event.expected === "ALLOW") buckets[bucket].allow += 1;
    if (event.expected === "DROP") buckets[bucket].drop += 1;
  });
  const maxTotal = Math.max(1, ...buckets.map(bucket => bucket.total));
  chartEl.innerHTML = buckets.map(bucket => {
    const height = Math.max(3, Math.round((bucket.total / maxTotal) * 96));
    const cls = bucket.drop > bucket.allow ? "drop-bar" : (bucket.allow > 0 ? "allow-bar" : "");
    return `<div class="bar ${cls}" title="${bucket.total} recent event(s)" style="height:${height}px"></div>`;
  }).join("");
}

async function refresh() {
  const response = await fetch("/api/state", {cache: "no-store"});
  render(await response.json());
}

async function sendProfile(profile) {
  const count = Number(document.getElementById("sendCount").value || 1);
  await fetch("/api/send", {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({profile, count})
  });
  await refresh();
}

document.querySelectorAll("button[data-profile]").forEach(button => {
  button.addEventListener("click", () => sendProfile(button.dataset.profile));
});

toggleManual.addEventListener("click", () => {
  manualShell.classList.toggle("open");
  toggleManual.textContent = manualShell.classList.contains("open") ? "Hide manual" : "Show manual";
});

chunkMap.innerHTML = Array.from({length: 96}, (_, index) => {
  const cls = index % 17 === 0 ? "drop" : (index < 36 ? "good" : "wait");
  return `<div class="chunk ${cls}" title="demo chunk ${index}"></div>`;
}).join("");
refresh();
setInterval(refresh, 500);
</script>
</body>
</html>
"""


class DashboardHandler(BaseHTTPRequestHandler):
    state = None

    def log_message(self, fmt, *args):
        return

    def send_text(self, status, body, content_type="text/plain; charset=utf-8"):
        payload = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def send_json(self, status, data):
        self.send_text(status, json.dumps(data), "application/json; charset=utf-8")

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/":
            self.send_text(HTTPStatus.OK, HTML, "text/html; charset=utf-8")
        elif parsed.path == "/api/state":
            self.send_json(HTTPStatus.OK, self.state.snapshot())
        else:
            self.send_text(HTTPStatus.NOT_FOUND, "not found")

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/api/send":
            self.send_text(HTTPStatus.NOT_FOUND, "not found")
            return

        length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(length).decode("utf-8") if length else "{}"
        content_type = self.headers.get("Content-Type", "")
        if "application/json" in content_type:
            data = json.loads(raw_body or "{}")
        else:
            data = {k: v[0] for k, v in parse_qs(raw_body).items()}

        profile = data.get("profile", "")
        count = int(data.get("count", 1))
        if profile not in PROFILES:
            self.send_json(HTTPStatus.BAD_REQUEST, {"error": "unknown profile"})
            return
        if count < 1 or count > 100:
            self.send_json(HTTPStatus.BAD_REQUEST, {"error": "count must be 1..100"})
            return

        packet = build_packet(profile)
        for _ in range(count):
            sendp(packet, iface=self.state.iface, verbose=False)
            time.sleep(0.05)
        self.state.record_sent(profile, count)
        self.send_json(HTTPStatus.OK, self.state.snapshot())


def sniff_worker(state):
    try:
        state.set_status("Sniffing")
        sniff(iface=state.iface, prn=state.record_packet, store=False)
    except Exception as exc:
        state.set_status("Sniffer stopped", str(exc))


def main():
    parser = argparse.ArgumentParser(description="Browser dashboard for FPGA firewall traffic tests.")
    parser.add_argument("--iface", default="Ethernet", help="Scapy interface name.")
    parser.add_argument("--host", default="127.0.0.1", help="HTTP bind host.")
    parser.add_argument("--port", type=int, default=8080, help="HTTP port.")
    args = parser.parse_args()

    state = DashboardState(args.iface)
    DashboardHandler.state = state

    thread = threading.Thread(target=sniff_worker, args=(state,), daemon=True)
    thread.start()

    server = ThreadingHTTPServer((args.host, args.port), DashboardHandler)
    url = f"http://{args.host}:{args.port}"
    print(f"Traffic dashboard running at {url}")
    print("Stop with Ctrl+C.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
