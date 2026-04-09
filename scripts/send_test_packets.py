#!/usr/bin/env python3
import argparse
import sys
import time

try:
    from scapy.all import Ether, IP, TCP, UDP, Raw, sendp
except ImportError:
    print("Scapy is required. Install it with: pip install scapy", file=sys.stderr)
    sys.exit(1)


def build_packet(name: str):
    if name == "udp_allow":
        return (
            Ether(dst="ff:ff:ff:ff:ff:ff", src="00:11:22:33:44:55")
            / IP(src="192.168.1.10", dst="192.168.1.1", proto=17)
            / UDP(sport=0x1234, dport=80)
            / Raw(load=b"FW-UDP-ALLOW")
        )

    if name == "tcp_drop":
        return (
            Ether(dst="ff:ff:ff:ff:ff:ff", src="00:11:22:33:44:55")
            / IP(src="10.0.0.42", dst="192.168.1.99", proto=6)
            / TCP(sport=0x1234, dport=23, flags="S")
            / Raw(load=b"FW-TCP-DROP")
        )

    if name == "tcp_allow_ssh":
        return (
            Ether(dst="ff:ff:ff:ff:ff:ff", src="00:11:22:33:44:55")
            / IP(src="10.1.2.3", dst="192.168.1.99", proto=6)
            / TCP(sport=0x08AE, dport=22, flags="S")
            / Raw(load=b"FW-TCP-ALLOW-SSH")
        )

    raise ValueError(f"Unknown packet profile: {name}")


def main():
    parser = argparse.ArgumentParser(description="Send deterministic firewall test packets.")
    parser.add_argument("--iface", required=True, help="Interface name used by Scapy/sendp.")
    parser.add_argument(
        "--packet",
        required=True,
        choices=["udp_allow", "tcp_drop", "tcp_allow_ssh"],
        help="Packet profile to send.",
    )
    parser.add_argument("--count", type=int, default=1, help="Number of packets to send.")
    parser.add_argument(
        "--interval",
        type=float,
        default=0.5,
        help="Seconds between packets when count > 1.",
    )
    args = parser.parse_args()

    pkt = build_packet(args.packet)
    print(f"Sending {args.count} '{args.packet}' packet(s) on {args.iface}")

    for idx in range(args.count):
        sendp(pkt, iface=args.iface, verbose=False)
        print(f"sent {idx + 1}/{args.count}")
        if idx + 1 < args.count:
            time.sleep(args.interval)


if __name__ == "__main__":
    main()
