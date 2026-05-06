#!/usr/bin/env python3
import argparse
import json
import math
from pathlib import Path
import random
import socket
import struct
import time


MAGIC = b"FWSINE2\0"
DEFAULT_SRC_IP = "192.168.1.10"
DEFAULT_DST_IP = "192.168.1.1"
DEFAULT_W5500_A_MAC = "02:00:00:de:ad:0a"
DEFAULT_FILE_PORT = 5001
DEFAULT_DECOY_PORT = 5002
DEFAULT_STATE_FILE = ".sine_sender_state.json"


def load_state(path):
    if path is None or not path.exists():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            state = json.load(handle)
        return {
            "run_id": int(state["run_id"]) & 0xFFFFFFFF,
            "seq": int(state["seq"]) & 0xFFFFFFFF,
            "phase": float(state["phase"]),
        }
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
        return None


def save_state(path, run_id, seq, phase):
    if path is None:
        return
    state = {"run_id": run_id & 0xFFFFFFFF, "seq": seq & 0xFFFFFFFF, "phase": phase}
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    with tmp_path.open("w", encoding="utf-8") as handle:
        json.dump(state, handle, separators=(",", ":"))
    tmp_path.replace(path)


def build_sine_payload(run_id, seq, sample_rate, sine_hz, samples_per_packet, phase):
    samples = []
    for idx in range(samples_per_packet):
        t = phase + idx / sample_rate
        value = int(28000 * math.sin(2.0 * math.pi * sine_hz * t))
        samples.append(value)
    next_phase = phase + samples_per_packet / sample_rate
    header = MAGIC + struct.pack("!IIHHH", run_id, seq, sample_rate, sine_hz, samples_per_packet)
    body = struct.pack("!" + "h" * samples_per_packet, *samples)
    return header + body, next_phase


def build_decoy(seq, mode, file_port):
    if mode == "content" or (mode == "mixed" and seq % 2):
        return file_port, f"FW-BLOCK sine-content-block seq={seq}".encode("ascii")
    return DEFAULT_DECOY_PORT, f"FW-DEMO-DROP-UDP5002 sine-decoy seq={seq}".encode("ascii")


def main():
    parser = argparse.ArgumentParser(description="Continuously send a sine stream through the FPGA UDP policy gateway.")
    parser.add_argument("--iface", default="en0", help="PC1 Ethernet interface used in setup hints.")
    parser.add_argument("--src-ip", default=DEFAULT_SRC_IP)
    parser.add_argument("--dst-ip", default=DEFAULT_DST_IP)
    parser.add_argument("--src-port", type=int, default=40000)
    parser.add_argument("--port", type=int, default=DEFAULT_FILE_PORT, help="Allowed UDP destination port.")
    parser.add_argument("--decoy-port", type=int, default=DEFAULT_DECOY_PORT)
    parser.add_argument("--w5500-mac", default=DEFAULT_W5500_A_MAC, help="W5500 A SHAR for setup hints.")
    parser.add_argument("--sample-rate", type=int, default=200)
    parser.add_argument("--sine-hz", type=int, default=1)
    parser.add_argument("--samples-per-packet", type=int, default=16)
    parser.add_argument("--packets-per-second", type=float, default=5.0)
    parser.add_argument("--decoy-every", type=int, default=4, help="Send one blocked decoy every N allowed packets; 0 disables decoys.")
    parser.add_argument("--decoy-mode", choices=["udp", "content", "mixed"], default="mixed")
    parser.add_argument("--run-id", type=lambda value: int(value, 0), default=None, help="Optional 32-bit stream ID; default is random per run.")
    parser.add_argument("--state-file", default=DEFAULT_STATE_FILE, help="Persist run ID, sequence, and phase for one continuous demo across sender restarts; empty disables.")
    parser.add_argument("--fresh-run", action="store_true", help="Ignore saved state and start a new run ID/sequence.")
    parser.add_argument("--print-setup", action="store_true", help="Print PC1 setup commands and exit.")
    args = parser.parse_args()

    if args.packets_per_second <= 0:
        parser.error("--packets-per-second must be greater than 0")
    if args.samples_per_packet <= 0:
        parser.error("--samples-per-packet must be greater than 0")
    if args.src_port < 1 or args.src_port > 65535:
        parser.error("--src-port must be 1..65535")

    setup = [
        f"sudo ifconfig {args.iface} inet {args.src_ip} netmask 255.255.255.0 up",
        f"sudo arp -d {args.dst_ip} 2>/dev/null || true",
        f"sudo arp -s {args.dst_ip} {args.w5500_mac}",
        f"sudo tcpdump -i {args.iface} -nn -e 'host {args.dst_ip} and udp'",
    ]
    if args.print_setup:
        print("\n".join(setup))
        return

    interval = 1.0 / args.packets_per_second
    state_path = Path(args.state_file).expanduser() if args.state_file else None
    saved_state = None if args.fresh_run else load_state(state_path)
    run_id = args.run_id if args.run_id is not None else (
        saved_state["run_id"] if saved_state is not None else random.getrandbits(32)
    )
    run_id &= 0xFFFFFFFF
    can_resume_state = saved_state is not None and saved_state["run_id"] == run_id
    seq = saved_state["seq"] if can_resume_state else 0
    phase = saved_state["phase"] if can_resume_state else 0.0

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.src_ip, args.src_port))

    print(f"Streaming sine wave on {args.iface}: {args.sine_hz} Hz, UDP dst port {args.port}")
    print(f"src={args.src_ip}:{args.src_port} dst={args.dst_ip}")
    print(f"Allowed packets/sec={args.packets_per_second:g}, samples/packet={args.samples_per_packet}")
    print(f"Run ID=0x{run_id:08x}")
    print(f"Starting seq={seq}")
    if state_path is not None:
        print(f"State file={state_path}")
    print("Setup commands:")
    for cmd in setup:
        print(f"  {cmd}")
    print("Stop with Ctrl+C.")

    try:
        while True:
            payload, phase = build_sine_payload(run_id, seq, args.sample_rate, args.sine_hz, args.samples_per_packet, phase)
            sock.sendto(payload, (args.dst_ip, args.port))
            if args.decoy_every > 0 and seq % args.decoy_every == 0:
                decoy_port, decoy_payload = build_decoy(seq, args.decoy_mode, args.port)
                if decoy_port == DEFAULT_DECOY_PORT:
                    decoy_port = args.decoy_port
                sock.sendto(decoy_payload, (args.dst_ip, decoy_port))

            seq = (seq + 1) & 0xFFFFFFFF
            if (seq % 10) == 0:
                save_state(state_path, run_id, seq, phase)
            time.sleep(interval)
    except KeyboardInterrupt:
        save_state(state_path, run_id, seq, phase)
        print(f"\nstopped after {seq} allowed packets")


if __name__ == "__main__":
    main()
