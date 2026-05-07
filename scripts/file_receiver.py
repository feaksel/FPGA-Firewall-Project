#!/usr/bin/env python3
import argparse
import hashlib
import json
import mimetypes
import struct
import sys
import threading
import time
from collections import deque
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

try:
    from scapy.all import Raw, UDP, sniff
except ImportError:
    print("Scapy is required. Install it with: pip install scapy", file=sys.stderr)
    sys.exit(1)


MAGIC = b"FWFILE1\0"
HEADER_LEN = len(MAGIC) + 2 + 2 + 2 + 4 + 32
FILE_UDP_PORT = 5001
BLOCK_MARKERS = (b"FW-BLOCK", b"FW-DEMO-DROP")
APP_VERSION = "udp-file-dashboard-2026-05-07"
AUTO_EXTENSION_SUFFIXES = {"", ".bin", ".dat", ".payload", ".octet-stream"}
MIME_EXTENSIONS = {
    "video/mp4": ".mp4",
    "image/png": ".png",
    "image/jpeg": ".jpg",
    "image/gif": ".gif",
    "audio/mpeg": ".mp3",
}


def mime_from_header(head: bytes) -> str:
    if len(head) >= 12 and head[4:8] == b"ftyp":
        return "video/mp4"
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if head.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if head.startswith(b"GIF87a") or head.startswith(b"GIF89a"):
        return "image/gif"
    if head.startswith(b"ID3") or head[:2] == b"\xff\xfb":
        return "audio/mpeg"
    return ""


def detect_mime(path: Path, complete: bool) -> str:
    if complete and path.exists():
        try:
            detected = mime_from_header(path.read_bytes()[:64])
        except OSError:
            detected = ""
        if detected:
            return detected

    guessed = mimetypes.guess_type(str(path))[0]
    if guessed and guessed != "application/octet-stream":
        return guessed
    return guessed or "application/octet-stream"


def auto_output_path(requested_path: Path, data: bytes, enabled: bool) -> Path:
    if not enabled:
        return requested_path
    mime_type = mime_from_header(data[:64])
    suffix = MIME_EXTENSIONS.get(mime_type)
    if not suffix:
        return requested_path
    if requested_path.suffix.lower() not in AUTO_EXTENSION_SUFFIXES:
        return requested_path
    return requested_path.with_suffix(suffix)


def parse_payload(payload: bytes):
    if len(payload) < HEADER_LEN or not payload.startswith(MAGIC):
        return None
    offset = len(MAGIC)
    file_id, chunk_index, total_chunks, file_size = struct.unpack("!HHHI", payload[offset : offset + 10])
    offset += 10
    sha256_hex = payload[offset : offset + 32].hex()
    offset += 32
    return {
        "file_id": file_id,
        "chunk_index": chunk_index,
        "total_chunks": total_chunks,
        "file_size": file_size,
        "sha256": sha256_hex,
        "data": payload[offset:],
    }


def packet_payload(pkt):
    if Raw in pkt:
        return bytes(pkt[Raw].load)
    try:
        return bytes(pkt)
    except Exception:
        return b""


class FileReceiverState:
    def __init__(self, output_path, file_port, auto_extension=True, auto_next=True):
        self.requested_output_path = Path(output_path)
        self.output_path = self.requested_output_path
        self.file_port = file_port
        self.auto_extension = auto_extension
        self.auto_next = auto_next
        self.lock = threading.Lock()
        self.reset_unlocked()

    def reset_unlocked(self, clear_events=True):
        self.started_at = time.time()
        self.output_path = self.requested_output_path
        self.file_id = None
        self.total_chunks = None
        self.file_size = None
        self.expected_sha = None
        self.actual_sha = None
        self.completed_at = None
        self.chunks = {}
        self.chunk_times = {}
        self.allowed_packets = 0
        self.duplicate_chunks = 0
        self.leak_packets = 0
        self.other_packets = 0
        self.bytes_received = 0
        self.sniff_error = ""
        if clear_events or not hasattr(self, "events"):
            self.events = deque(maxlen=90)

    def reset(self):
        with self.lock:
            self.reset_unlocked()

    def event(self, kind, detail):
        self.events.appendleft({"time": time.time(), "kind": kind, "detail": detail})

    def handle_packet(self, pkt):
        payload = packet_payload(pkt)
        udp_dport = int(pkt[UDP].dport) if UDP in pkt else None
        now = time.time()

        with self.lock:
            if any(marker in payload for marker in BLOCK_MARKERS):
                self.leak_packets += 1
                self.event("LEAK", f"blocked marker reached PC2 on UDP/{udp_dport}")
                return

            if UDP not in pkt or udp_dport != self.file_port or Raw not in pkt:
                self.other_packets += 1
                return

            parsed = parse_payload(payload)
            if parsed is None:
                self.other_packets += 1
                return

            if self.file_id is not None and parsed["file_id"] != self.file_id:
                if self.completed_at is not None and self.auto_next:
                    previous = self.output_path
                    self.reset_unlocked(clear_events=False)
                    self.event("NEXT", f"new file_id={parsed['file_id']} after {previous.name}")
                else:
                    self.other_packets += 1
                    self.event("OLD", f"ignored file_id={parsed['file_id']} while receiving {self.file_id}")
                    return

            if self.file_id is None:
                self.file_id = parsed["file_id"]
                self.total_chunks = parsed["total_chunks"]
                self.file_size = parsed["file_size"]
                self.expected_sha = parsed["sha256"]
                self.event(
                    "START",
                    f"file_id={self.file_id} chunks={self.total_chunks} bytes={self.file_size}",
                )

            chunk_index = parsed["chunk_index"]
            if chunk_index in self.chunks:
                self.duplicate_chunks += 1
            else:
                self.bytes_received += len(parsed["data"])
            self.chunks[chunk_index] = parsed["data"]
            self.chunk_times[chunk_index] = now
            self.allowed_packets += 1

            if self.total_chunks and len(self.chunks) == self.total_chunks and self.completed_at is None:
                self.finish_unlocked()

    def finish_unlocked(self):
        data = b"".join(self.chunks[idx] for idx in range(self.total_chunks))[: self.file_size]
        self.output_path = auto_output_path(self.requested_output_path, data, self.auto_extension)
        self.output_path.parent.mkdir(parents=True, exist_ok=True)
        self.output_path.write_bytes(data)
        self.actual_sha = hashlib.sha256(data).hexdigest()
        self.completed_at = time.time()
        if self.actual_sha == self.expected_sha:
            self.event("PASS", f"wrote {self.output_path} with matching SHA-256")
        else:
            self.event("FAIL", f"checksum mismatch for {self.output_path}")

    def missing_chunks_unlocked(self):
        if self.total_chunks is None:
            return []
        return [idx for idx in range(self.total_chunks) if idx not in self.chunks]

    def snapshot(self):
        with self.lock:
            now = time.time()
            total_chunks = self.total_chunks or 0
            received_chunks = sorted(self.chunks)
            missing_chunks = self.missing_chunks_unlocked()
            elapsed = max(now - self.started_at, 0.001)
            complete = self.completed_at is not None
            mime_type = detect_mime(self.output_path, complete)
            return {
                "version": APP_VERSION,
                "file_id": "-" if self.file_id is None else self.file_id,
                "total_chunks": total_chunks,
                "received_count": len(self.chunks),
                "missing_count": len(missing_chunks),
                "missing_preview": missing_chunks[:50],
                "received_chunks": received_chunks,
                "file_size": self.file_size or 0,
                "bytes_received": min(self.bytes_received, self.file_size or self.bytes_received),
                "expected_sha": self.expected_sha or "",
                "actual_sha": self.actual_sha or "",
                "sha_ok": complete and self.actual_sha == self.expected_sha,
                "complete": complete,
                "output_path": str(self.output_path),
                "output_url": f"/file?sha={self.actual_sha}" if complete else "",
                "mime_type": mime_type,
                "allowed_packets": self.allowed_packets,
                "duplicate_chunks": self.duplicate_chunks,
                "leak_packets": self.leak_packets,
                "other_packets": self.other_packets,
                "elapsed": elapsed,
                "chunks_per_second": len(self.chunks) / elapsed,
                "sniff_error": self.sniff_error,
                "events": [
                    {
                        "time": time.strftime("%H:%M:%S", time.localtime(event["time"])),
                        "kind": event["kind"],
                        "detail": event["detail"],
                    }
                    for event in list(self.events)
                ],
            }

    def set_error(self, error):
        with self.lock:
            self.sniff_error = error


HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>FPGA UDP File Transfer</title>
<style>
:root { --bg:#f5f7fb; --panel:#fff; --ink:#17212f; --muted:#617087; --line:#d8e0eb; --green:#147a52; --red:#b73535; --blue:#1769c2; --amber:#a66f00; }
* { box-sizing:border-box; }
body { margin:0; font-family:"Segoe UI", Arial, sans-serif; background:var(--bg); color:var(--ink); }
header { background:var(--panel); border-bottom:1px solid var(--line); padding:18px 22px; display:flex; justify-content:space-between; gap:12px; flex-wrap:wrap; align-items:center; }
h1 { margin:0 0 4px; font-size:22px; letter-spacing:0; }
.sub,.note { color:var(--muted); font-size:13px; line-height:1.45; }
button { border:1px solid #b7c4d4; background:#fff; color:var(--ink); border-radius:7px; min-height:36px; padding:0 12px; font-weight:650; cursor:pointer; }
main { padding:18px 22px 30px; display:grid; gap:14px; }
.metrics { display:grid; grid-template-columns:repeat(6,minmax(120px,1fr)); gap:12px; }
.metric,.panel { background:var(--panel); border:1px solid var(--line); border-radius:8px; }
.metric { padding:13px 15px; }
.label { color:var(--muted); font-size:11px; text-transform:uppercase; }
.value { margin-top:7px; font-size:26px; font-weight:760; }
.good .value { color:var(--green); } .bad .value { color:var(--red); }
.grid { display:grid; grid-template-columns:minmax(0,1.1fr) minmax(320px,.9fr); gap:14px; }
.panel { padding:15px; min-width:0; }
h2 { margin:0 0 12px; font-size:16px; }
.progress { height:24px; border-radius:7px; background:#e7edf5; overflow:hidden; border:1px solid var(--line); }
.bar { height:100%; width:0%; background:linear-gradient(90deg,#147a52,#2ba66f); transition:width .2s; }
.chunk-map { display:grid; grid-template-columns:repeat(60, minmax(5px,1fr)); gap:3px; margin-top:12px; }
.chunk { height:13px; border-radius:3px; background:#dbe3ee; border:1px solid transparent; }
.chunk.full { background:var(--green); }
.chunk.partial { background:var(--amber); }
.chunk.missing { background:#e3e8ef; }
.events { display:grid; gap:8px; max-height:430px; overflow:auto; }
.event { display:grid; grid-template-columns:64px 58px minmax(0,1fr); gap:8px; padding:9px; border:1px solid var(--line); border-radius:7px; align-items:center; }
.kind { font-weight:800; font-size:12px; }
.kind.PASS,.kind.START { color:var(--green); } .kind.FAIL,.kind.LEAK { color:var(--red); } .kind.OLD { color:var(--amber); }
.mono { font-family:Consolas,"Courier New",monospace; word-break:break-all; }
.preview { min-height:260px; border:1px solid var(--line); border-radius:8px; background:#fbfcfe; display:grid; place-items:center; overflow:hidden; }
.preview img,.preview video { max-width:100%; max-height:520px; display:block; }
.preview audio { width:92%; }
.preview iframe { width:100%; height:520px; border:0; background:white; }
.ok { color:var(--green); font-weight:760; } .fail { color:var(--red); font-weight:760; }
@media (max-width:960px){ .metrics,.grid{grid-template-columns:1fr}.chunk-map{grid-template-columns:repeat(30, minmax(6px,1fr));} }
</style>
</head>
<body>
<header>
  <div><h1>FPGA UDP File Transfer</h1><div class="sub">PC1 sends real file chunks on UDP/5001 while decoys should be dropped. PC2 reconstructs and previews the completed file.</div></div>
  <button id="reset">Restart dashboard</button>
</header>
<main>
  <section class="metrics">
    <div class="metric good"><div class="label">Received chunks</div><div class="value" id="received">0</div></div>
    <div class="metric"><div class="label">Total chunks</div><div class="value" id="total">-</div></div>
    <div class="metric"><div class="label">Missing</div><div class="value" id="missing">-</div></div>
    <div class="metric bad"><div class="label">Decoy leaks</div><div class="value" id="leaks">0</div></div>
    <div class="metric"><div class="label">Chunks/sec</div><div class="value" id="rate">0.0</div></div>
    <div class="metric"><div class="label">SHA-256</div><div class="value" id="shaState">-</div></div>
  </section>
  <section class="grid">
    <div class="panel">
      <h2>Transfer Progress</h2>
      <div class="progress"><div class="bar" id="bar"></div></div>
      <p class="note" id="progressText"></p>
      <div class="chunk-map" id="chunkMap"></div>
      <p class="note mono" id="missingList"></p>
      <p class="note mono" id="shaText"></p>
    </div>
    <div class="panel">
      <h2>Reconstructed File Preview</h2>
      <div class="preview" id="preview"><p class="note">Waiting for completed file...</p></div>
      <p class="note mono" id="outputPath"></p>
    </div>
  </section>
  <section class="grid">
    <div class="panel">
      <h2>Recent Events</h2>
      <div class="events" id="events"></div>
    </div>
    <div class="panel">
      <h2>Receiver Status</h2>
      <p class="note" id="status"></p>
      <p class="note fail" id="error"></p>
    </div>
  </section>
</main>
<script>
const ids=["received","total","missing","leaks","rate","shaState","bar","progressText","chunkMap","missingList","shaText","preview","outputPath","events","status","error"];
const el=Object.fromEntries(ids.map(id=>[id,document.getElementById(id)]));
let currentPreviewKey="";
function renderPreview(d){
  const key=d.complete ? `${d.output_url}|${d.mime_type}|${d.actual_sha}` : "waiting";
  if(key===currentPreviewKey) return;
  currentPreviewKey=key;
  if(!d.complete){
    const missing=d.missing_count||0;
    const detail=missing?`Missing ${missing} chunk${missing===1?"":"s"}; waiting for a complete byte-exact file before writing or previewing.`:"Waiting for completed file...";
    el.preview.innerHTML=`<p class="note">${detail}</p>`;
    return;
  }
  const url=d.output_url;
  const mime=d.mime_type||"";
  if(mime.startsWith("image/")) el.preview.innerHTML=`<img src="${url}" alt="received file">`;
  else if(mime.startsWith("video/")) el.preview.innerHTML=`<video src="${url}" controls></video>`;
  else if(mime.startsWith("audio/")) el.preview.innerHTML=`<audio src="${url}" controls></audio>`;
  else if(mime.startsWith("text/")) el.preview.innerHTML=`<iframe src="${url}"></iframe>`;
  else el.preview.innerHTML=`<p class="note">File complete. Browser preview is not available for ${mime || "this type"}.</p><p><a href="${url}" target="_blank">Open reconstructed file</a></p>`;
}
function renderChunks(d){
  const total=d.total_chunks||0;
  if(!total){ el.chunkMap.innerHTML=""; return; }
  const received=new Set(d.received_chunks||[]);
  const buckets=Math.min(600,total);
  let html="";
  for(let b=0;b<buckets;b++){
    const start=Math.floor((b*total)/buckets);
    const end=Math.floor(((b+1)*total)/buckets)-1;
    let have=0;
    for(let i=start;i<=end;i++) if(received.has(i)) have++;
    const span=end-start+1;
    const cls=have===0?"missing":(have===span?"full":"partial");
    html+=`<div class="chunk ${cls}" title="chunks ${start}-${end}: ${have}/${span}"></div>`;
  }
  el.chunkMap.innerHTML=html;
}
async function refresh(){
  const r=await fetch("/api/state",{cache:"no-store"}); const d=await r.json();
  const total=d.total_chunks||0, rec=d.received_count||0;
  const pct=total?Math.min(100,(rec/total)*100):0;
  el.received.textContent=rec; el.total.textContent=total||"-"; el.missing.textContent=total?d.missing_count:"-";
  el.leaks.textContent=d.leak_packets; el.rate.textContent=d.chunks_per_second.toFixed(1);
  el.shaState.innerHTML=d.complete?(d.sha_ok?'<span class="ok">PASS</span>':'<span class="fail">FAIL</span>'):"-";
  el.bar.style.width=pct+"%";
  el.progressText.textContent=`${pct.toFixed(1)}% | ${d.bytes_received}/${d.file_size||"?"} bytes | duplicates ${d.duplicate_chunks} | other ${d.other_packets}`;
  el.missingList.textContent=d.missing_preview.length?`missing preview: ${d.missing_preview.join(", ")}`:"";
  el.shaText.textContent=d.expected_sha?`expected ${d.expected_sha}${d.actual_sha?` | actual ${d.actual_sha}`:""}`:"Waiting for transfer metadata...";
  el.outputPath.textContent=d.complete?d.output_path:"";
  el.status.textContent=`${d.version} | file_id=${d.file_id} | MIME=${d.mime_type}`;
  el.error.textContent=d.sniff_error||"";
  el.events.innerHTML=d.events.map(e=>`<div class="event"><div class="note">${e.time}</div><div class="kind ${e.kind}">${e.kind}</div><div>${e.detail}</div></div>`).join("")||'<p class="note">No packets yet.</p>';
  renderChunks(d); renderPreview(d);
}
async function reset(){ await fetch("/api/reset",{method:"POST"}); await refresh(); }
document.getElementById("reset").addEventListener("click", reset);
refresh(); setInterval(refresh,500);
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
        elif parsed.path == "/file":
            self.send_file()
        else:
            self.send_text(HTTPStatus.NOT_FOUND, "not found", "text/plain; charset=utf-8")

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path == "/api/reset":
            self.state.reset()
            self.send_text(HTTPStatus.OK, json.dumps({"ok": True}), "application/json; charset=utf-8")
        else:
            self.send_text(HTTPStatus.NOT_FOUND, "not found", "text/plain; charset=utf-8")

    def send_file(self):
        snapshot = self.state.snapshot()
        path = Path(snapshot["output_path"])
        if not snapshot["complete"] or not path.exists():
            self.send_text(HTTPStatus.NOT_FOUND, "file not complete", "text/plain; charset=utf-8")
            return
        payload = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", snapshot["mime_type"])
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Content-Disposition", f'inline; filename="{path.name}"')
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)


def sniff_worker(state, iface, timeout):
    try:
        sniff_timeout = None if timeout <= 0 else timeout
        sniff(iface=iface, prn=state.handle_packet, store=False, timeout=sniff_timeout)
    except Exception as exc:
        state.set_error(str(exc))


def main():
    parser = argparse.ArgumentParser(description="Receive, reconstruct, and visualize the FPGA UDP file demo.")
    parser.add_argument("--iface", required=True, help="Scapy interface connected to W5500 B / FPGA egress.")
    parser.add_argument(
        "--output",
        default="received_fw_file.bin",
        help="Reconstructed file path. The default .bin suffix is auto-replaced with .mp4/.jpg/.png when bytes identify a supported type.",
    )
    parser.add_argument("--file-port", type=int, default=FILE_UDP_PORT)
    parser.add_argument("--timeout", type=int, default=0, help="Sniff timeout in seconds; 0 means run until Ctrl+C.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8092, help="Browser dashboard port.")
    parser.add_argument("--no-dashboard", action="store_true", help="Run terminal-only receiver without the browser dashboard.")
    parser.add_argument("--no-auto-extension", action="store_true", help="Keep --output exactly as provided instead of replacing .bin with a detected media suffix.")
    parser.add_argument("--no-auto-next", action="store_true", help="Do not automatically accept a new file_id after the current file completes.")
    args = parser.parse_args()

    state = FileReceiverState(
        args.output,
        args.file_port,
        auto_extension=not args.no_auto_extension,
        auto_next=not args.no_auto_next,
    )
    print(f"listening on {args.iface} for UDP dst port {args.file_port}")

    if args.no_dashboard:
        sniff_worker(state, args.iface, args.timeout)
        snapshot = state.snapshot()
        if snapshot["complete"]:
            print(f"PASS" if snapshot["sha_ok"] else "FAIL")
            print(f"wrote {snapshot['output_path']}")
            print(f"sha256 expected={snapshot['expected_sha']} actual={snapshot['actual_sha']}")
        else:
            print(f"incomplete: received {snapshot['received_count']}/{snapshot['total_chunks'] or '?'} chunks")
            if snapshot["missing_preview"]:
                print("missing chunks:", ",".join(str(idx) for idx in snapshot["missing_preview"]))
        return

    Handler.state = state
    thread = threading.Thread(target=sniff_worker, args=(state, args.iface, args.timeout), daemon=True)
    thread.start()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"File receiver dashboard running at http://{args.host}:{args.port}")
    print("Stop with Ctrl+C.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
