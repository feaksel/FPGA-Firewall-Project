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
WAVE_CHOICES = ("sine", "square", "triangle", "saw", "step", "noise", "values", "text")
TEXT_FONT = {
    " ": ("00000", "00000", "00000", "00000", "00000", "00000", "00000"),
    "-": ("00000", "00000", "00000", "11111", "00000", "00000", "00000"),
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
    "3": ("11110", "00001", "00001", "01110", "00001", "00001", "11110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "10000", "11110", "00001", "00001", "11110"),
    "6": ("01110", "10000", "10000", "11110", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00001", "01110"),
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "B": ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
    "C": ("01110", "10001", "10000", "10000", "10000", "10001", "01110"),
    "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "F": ("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
    "G": ("01110", "10001", "10000", "10111", "10001", "10001", "01110"),
    "H": ("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
    "I": ("01110", "00100", "00100", "00100", "00100", "00100", "01110"),
    "J": ("00001", "00001", "00001", "00001", "10001", "10001", "01110"),
    "K": ("10001", "10010", "10100", "11000", "10100", "10010", "10001"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
    "M": ("10001", "11011", "10101", "10101", "10001", "10001", "10001"),
    "N": ("10001", "11001", "10101", "10011", "10001", "10001", "10001"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "Q": ("01110", "10001", "10001", "10001", "10101", "10010", "01101"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
    "U": ("10001", "10001", "10001", "10001", "10001", "10001", "01110"),
    "V": ("10001", "10001", "10001", "10001", "10001", "01010", "00100"),
    "W": ("10001", "10001", "10001", "10101", "10101", "10101", "01010"),
    "X": ("10001", "10001", "01010", "00100", "01010", "10001", "10001"),
    "Y": ("10001", "10001", "01010", "00100", "00100", "00100", "00100"),
    "Z": ("11111", "00001", "00010", "00100", "01000", "10000", "11111"),
}


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


def clamp_i16(value):
    return max(-32768, min(32767, int(round(value))))


def parse_custom_values(values_text):
    values = []
    for raw in values_text.replace(",", " ").split():
        values.append(clamp_i16(int(raw, 0)))
    return values


def load_custom_values(path):
    if path is None:
        return []
    return parse_custom_values(path.read_text(encoding="utf-8"))


def build_text_columns(message):
    columns = []
    for ch in message.upper():
        glyph = TEXT_FONT.get(ch, TEXT_FONT[" "])
        for col in range(5):
            columns.append(tuple(row[col] == "1" for row in glyph))
        columns.append((False,) * 7)
    return columns or [(False,) * 7]


def wave_sample(args, t, global_sample_index, custom_values, text_columns):
    amplitude = args.amplitude
    offset = args.offset
    hz = max(args.wave_hz, 0)

    if args.wave == "values":
        if not custom_values:
            return clamp_i16(offset)
        return custom_values[global_sample_index % len(custom_values)]

    if args.wave == "noise":
        return clamp_i16(offset + random.randint(-amplitude, amplitude))

    if args.wave == "text":
        row_count = 7
        col = (global_sample_index // row_count) % len(text_columns)
        row = global_sample_index % row_count
        if not text_columns[col][row]:
            return clamp_i16(offset - amplitude)
        row_pos = 1.0 - (2.0 * row / (row_count - 1))
        return clamp_i16(offset + amplitude * row_pos)

    if hz == 0:
        return clamp_i16(offset)

    cycle = (t * hz) % 1.0
    if args.wave == "sine":
        value = math.sin(2.0 * math.pi * cycle)
    elif args.wave == "square":
        value = 1.0 if cycle < args.duty_cycle else -1.0
    elif args.wave == "triangle":
        value = 4.0 * abs(cycle - 0.5) - 1.0
    elif args.wave == "saw":
        value = (2.0 * cycle) - 1.0
    elif args.wave == "step":
        step = int(cycle * 4.0) & 3
        value = (-1.0, -0.33, 0.33, 1.0)[step]
    else:
        value = 0.0
    return clamp_i16(offset + amplitude * value)


def build_wave_payload(run_id, seq, sample_rate, wave_hz, samples_per_packet, phase, args, custom_values, text_columns):
    samples = []
    for idx in range(samples_per_packet):
        t = phase + idx / sample_rate
        global_sample_index = seq * samples_per_packet + idx
        samples.append(wave_sample(args, t, global_sample_index, custom_values, text_columns))
    next_phase = phase + samples_per_packet / sample_rate
    header = MAGIC + struct.pack("!IIHHH", run_id, seq, sample_rate, int(wave_hz), samples_per_packet)
    body = struct.pack("!" + "h" * samples_per_packet, *samples)
    return header + body, next_phase


def build_decoy(seq, mode, file_port):
    if mode == "content" or (mode == "mixed" and seq % 2):
        return file_port, f"FW-BLOCK waveform-content-block seq={seq}".encode("ascii")
    return DEFAULT_DECOY_PORT, f"FW-DEMO-DROP-UDP5002 waveform-decoy seq={seq}".encode("ascii")


def main():
    parser = argparse.ArgumentParser(description="Continuously send payload sample streams through the FPGA UDP policy gateway.")
    parser.add_argument("--iface", default="en0", help="PC1 Ethernet interface used in setup hints.")
    parser.add_argument("--src-ip", default=DEFAULT_SRC_IP)
    parser.add_argument("--dst-ip", default=DEFAULT_DST_IP)
    parser.add_argument("--src-port", type=int, default=40000)
    parser.add_argument("--port", type=int, default=DEFAULT_FILE_PORT, help="Allowed UDP destination port.")
    parser.add_argument("--decoy-port", type=int, default=DEFAULT_DECOY_PORT)
    parser.add_argument("--w5500-mac", default=DEFAULT_W5500_A_MAC, help="W5500 A SHAR for setup hints.")
    parser.add_argument("--sample-rate", type=int, default=None, help="Payload sample rate in Hz. Default is packets/sec * samples/packet so the dashboard time axis matches real time.")
    parser.add_argument("--wave", choices=WAVE_CHOICES, default="sine", help="Payload sample pattern to transmit.")
    parser.add_argument("--wave-hz", "--sine-hz", dest="wave_hz", type=int, default=1, help="Pattern frequency in Hz; --sine-hz is kept as a compatibility alias.")
    parser.add_argument("--amplitude", type=int, default=28000, help="Peak amplitude for generated waveforms, in signed int16 units.")
    parser.add_argument("--offset", type=int, default=0, help="DC offset added to generated waveform samples.")
    parser.add_argument("--duty-cycle", type=float, default=0.5, help="High fraction for square wave mode.")
    parser.add_argument("--values", default="", help="Comma/space-separated signed int16 values for --wave values.")
    parser.add_argument("--values-file", type=Path, default=None, help="Text file containing signed int16 values for --wave values.")
    parser.add_argument("--text", default="FPGA UDP", help="Message for --wave text; supported characters are A-Z, 0-9, space, and dash.")
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
    if args.samples_per_packet <= 0 or args.samples_per_packet > 65535:
        parser.error("--samples-per-packet must be 1..65535")
    if args.sample_rate is None:
        args.sample_rate = int(round(args.packets_per_second * args.samples_per_packet))
    if args.sample_rate <= 0 or args.sample_rate > 65535:
        parser.error("--sample-rate must be 1..65535")
    if args.wave_hz < 0 or args.wave_hz > 65535:
        parser.error("--wave-hz must be 0..65535")
    if args.amplitude < 0 or args.amplitude > 32767:
        parser.error("--amplitude must be 0..32767")
    if args.offset < -32768 or args.offset > 32767:
        parser.error("--offset must be -32768..32767")
    if args.duty_cycle <= 0.0 or args.duty_cycle >= 1.0:
        parser.error("--duty-cycle must be between 0 and 1")
    if args.src_port < 1 or args.src_port > 65535:
        parser.error("--src-port must be 1..65535")
    custom_values = parse_custom_values(args.values) if args.values else []
    custom_values.extend(load_custom_values(args.values_file))
    text_columns = build_text_columns(args.text) if args.wave == "text" else []
    if args.wave == "values" and not custom_values:
        parser.error("--wave values requires --values or --values-file")

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

    print(f"Streaming {args.wave} payload values on {args.iface}: {args.wave_hz} Hz metadata, UDP dst port {args.port}")
    print(f"src={args.src_ip}:{args.src_port} dst={args.dst_ip}")
    print(f"Allowed packets/sec={args.packets_per_second:g}, samples/packet={args.samples_per_packet}")
    print(f"Sample rate={args.sample_rate} Hz, amplitude={args.amplitude}, offset={args.offset}")
    if custom_values:
        print(f"Custom values={len(custom_values)} sample(s), repeated in payload order")
    if args.wave == "text":
        print(f"Text message={args.text!r}, {len(text_columns)} columns x 7 rows encoded as samples")
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
            payload, phase = build_wave_payload(
                run_id, seq, args.sample_rate, args.wave_hz,
                args.samples_per_packet, phase, args, custom_values, text_columns
            )
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
