#!/usr/bin/env python3
import argparse
import math
import struct
import sys
import time

try:
    from scapy.all import Ether, IP, TCP, UDP, Raw, sendp
except ImportError:
    print("Scapy is required. Install it with: pip install scapy", file=sys.stderr)
    sys.exit(1)


MAGIC = b"FWSINE1\0"
DEFAULT_SRC_MAC = "00:11:22:33:44:55"
DEFAULT_DST_MAC = "ff:ff:ff:ff:ff:ff"
DEFAULT_SRC_IP = "192.168.50.10"
DEFAULT_DST_IP = "192.168.50.20"
DEFAULT_FILE_PORT = 5001


def build_sine_payload(seq, sample_rate, sine_hz, samples_per_packet, phase):
    samples = []
    for idx in range(samples_per_packet):
        t = phase + idx / sample_rate
        value = int(28000 * math.sin(2.0 * math.pi * sine_hz * t))
        samples.append(value)
    next_phase = phase + samples_per_packet / sample_rate
    header = MAGIC + struct.pack("!IHHH", seq, sample_rate, sine_hz, samples_per_packet)
    body = struct.pack("!" + "h" * samples_per_packet, *samples)
    return header + body, next_phase


def build_allowed_packet(args, payload):
    return (
        Ether(dst=args.dst_mac, src=args.src_mac)
        / IP(src=args.src_ip, dst=args.dst_ip)
        / UDP(sport=args.src_port, dport=args.port)
        / Raw(load=payload)
    )


def build_decoy_packet(args, seq):
    marker = f"FW-SINE-DECOY-DROP-{seq}".encode("ascii")
    if args.decoy_mode == "tcp" or (args.decoy_mode == "mixed" and seq % 2 == 0):
        return (
            Ether(dst=args.dst_mac, src=args.src_mac)
            / IP(src=args.blocked_src_ip, dst=args.dst_ip)
            / TCP(sport=41000 + (seq % 1000), dport=23, flags="S")
            / Raw(load=marker)
        )
    return (
        Ether(dst=args.dst_mac, src=args.src_mac)
        / IP(src=args.src_ip, dst=args.dst_ip)
        / UDP(sport=args.src_port, dport=args.decoy_port)
        / Raw(load=marker)
    )


def main():
    parser = argparse.ArgumentParser(description="Continuously send a sine-wave demo stream plus blocked decoy traffic.")
    parser.add_argument("--iface", required=True, help="Scapy interface connected to W5500 A / FPGA ingress.")
    parser.add_argument("--src-mac", default=DEFAULT_SRC_MAC)
    parser.add_argument("--dst-mac", default=DEFAULT_DST_MAC)
    parser.add_argument("--src-ip", default=DEFAULT_SRC_IP)
    parser.add_argument("--dst-ip", default=DEFAULT_DST_IP)
    parser.add_argument("--blocked-src-ip", default="10.99.0.42")
    parser.add_argument("--src-port", type=int, default=40000)
    parser.add_argument("--port", type=int, default=DEFAULT_FILE_PORT, help="Allowed UDP destination port.")
    parser.add_argument("--decoy-port", type=int, default=5002)
    parser.add_argument("--sample-rate", type=int, default=1000)
    parser.add_argument("--sine-hz", type=int, default=3)
    parser.add_argument("--samples-per-packet", type=int, default=32)
    parser.add_argument("--packets-per-second", type=float, default=20.0)
    parser.add_argument("--decoy-every", type=int, default=4, help="Send one blocked decoy every N allowed packets; 0 disables decoys.")
    parser.add_argument("--decoy-mode", choices=["tcp", "udp", "mixed"], default="tcp", help="Blocked decoy profile to interleave.")
    args = parser.parse_args()

    interval = 1.0 / args.packets_per_second
    seq = 0
    phase = 0.0
    print(f"Streaming sine wave on {args.iface}: {args.sine_hz} Hz, UDP dst port {args.port}")
    print(f"Allowed packets/sec={args.packets_per_second:g}, samples/packet={args.samples_per_packet}")
    print("Stop with Ctrl+C.")

    try:
        while True:
            payload, phase = build_sine_payload(seq, args.sample_rate, args.sine_hz, args.samples_per_packet, phase)
            sendp(build_allowed_packet(args, payload), iface=args.iface, verbose=False)

            if args.decoy_every > 0 and seq % args.decoy_every == 0:
                sendp(build_decoy_packet(args, seq), iface=args.iface, verbose=False)

            seq += 1
            time.sleep(interval)
    except KeyboardInterrupt:
        print(f"\nstopped after {seq} allowed packets")


if __name__ == "__main__":
    main()
