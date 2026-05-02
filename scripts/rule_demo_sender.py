#!/usr/bin/env python3
import argparse
import itertools
import sys
import time

try:
    from scapy.all import Ether, IP, TCP, UDP, Raw, sendp
except ImportError:
    print("Scapy is required. Install it with: pip install scapy", file=sys.stderr)
    sys.exit(1)


SRC_MAC = "00:11:22:33:44:55"
DST_MAC = "ff:ff:ff:ff:ff:ff"
SRC_IP = "192.168.50.10"
DST_IP = "192.168.50.20"
BLOCKED_SRC_IP = "10.99.0.42"


def allowed_udp(seq):
    return (
        Ether(dst=DST_MAC, src=SRC_MAC)
        / IP(src=SRC_IP, dst=DST_IP)
        / UDP(sport=40000, dport=5001)
        / Raw(load=f"FW-DEMO-ALLOW seq={seq}".encode("ascii"))
    )


def dropped_tcp(seq):
    return (
        Ether(dst=DST_MAC, src=SRC_MAC)
        / IP(src=BLOCKED_SRC_IP, dst=DST_IP)
        / TCP(sport=41000 + (seq % 1000), dport=23, flags="S")
        / Raw(load=f"FW-DEMO-DROP-TCP23 seq={seq}".encode("ascii"))
    )


def dropped_udp(seq):
    return (
        Ether(dst=DST_MAC, src=SRC_MAC)
        / IP(src=SRC_IP, dst=DST_IP)
        / UDP(sport=40001, dport=5002)
        / Raw(load=f"FW-DEMO-DROP-UDP5002 seq={seq}".encode("ascii"))
    )


def main():
    parser = argparse.ArgumentParser(description="Simple continuous FPGA firewall rule demo sender.")
    parser.add_argument("--iface", required=True, help="Mac Ethernet interface connected to W5500 A.")
    parser.add_argument("--rate", type=float, default=2.0, help="Demo cycles per second. One cycle sends allow + selected decoys.")
    parser.add_argument("--no-tcp-drop", action="store_true", help="Do not send TCP/23 drop decoys.")
    parser.add_argument("--no-udp-drop", action="store_true", help="Do not send UDP/5002 drop decoys.")
    args = parser.parse_args()

    if args.rate <= 0:
        parser.error("--rate must be greater than 0")

    interval = 1.0 / args.rate
    sent_allow = 0
    sent_drop = 0

    print("FPGA firewall rule demo sender")
    print(f"iface={args.iface} rate={args.rate:g} cycles/sec")
    print("Cycle: UDP/5001 allow, TCP/23 drop, UDP/5002 drop")
    print("Stop with Ctrl+C.")

    try:
        for seq in itertools.count():
            sendp(allowed_udp(seq), iface=args.iface, verbose=False)
            sent_allow += 1

            if not args.no_tcp_drop:
                sendp(dropped_tcp(seq), iface=args.iface, verbose=False)
                sent_drop += 1
            if not args.no_udp_drop:
                sendp(dropped_udp(seq), iface=args.iface, verbose=False)
                sent_drop += 1

            print(f"\rseq={seq} sent_allow={sent_allow} sent_expected_drop={sent_drop}", end="", flush=True)
            time.sleep(interval)
    except KeyboardInterrupt:
        print(f"\nstopped: sent_allow={sent_allow} sent_expected_drop={sent_drop}")


if __name__ == "__main__":
    main()
