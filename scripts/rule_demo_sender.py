#!/usr/bin/env python3
import argparse
import itertools
import sys
import time

try:
    from scapy.all import Ether, IP, TCP, UDP, Raw, get_if_list, sendp
except ImportError:
    print("Scapy is required. Install it with: pip install scapy", file=sys.stderr)
    sys.exit(1)


SRC_MAC = "00:11:22:33:44:55"
DST_MAC = "ff:ff:ff:ff:ff:ff"
ALLOW_SRC_IP = "192.168.1.10"
ALLOW_DST_IP = "192.168.1.1"
DROP_SRC_IP = "10.0.0.42"
DROP_DST_IP = "192.168.1.99"
SSH_SRC_IP = "10.1.2.3"
SSH_DST_IP = "192.168.1.99"


def allowed_udp(seq):
    return (
        Ether(dst=DST_MAC, src=SRC_MAC)
        / IP(src=ALLOW_SRC_IP, dst=ALLOW_DST_IP, proto=17)
        / UDP(sport=0x1234, dport=80)
        / Raw(load=f"FW-DEMO-ALLOW seq={seq}".encode("ascii"))
    )


def dropped_tcp(seq):
    return (
        Ether(dst=DST_MAC, src=SRC_MAC)
        / IP(src=DROP_SRC_IP, dst=DROP_DST_IP, proto=6)
        / TCP(sport=0x1234, dport=23, flags="S")
        / Raw(load=f"FW-DEMO-DROP-TCP23 seq={seq}".encode("ascii"))
    )


def allowed_ssh(seq):
    return (
        Ether(dst=DST_MAC, src=SRC_MAC)
        / IP(src=SSH_SRC_IP, dst=SSH_DST_IP, proto=6)
        / TCP(sport=0x08AE, dport=22, flags="S")
        / Raw(load=f"FW-DEMO-ALLOW-SSH seq={seq}".encode("ascii"))
    )


def main():
    parser = argparse.ArgumentParser(description="Simple continuous FPGA firewall rule demo sender.")
    parser.add_argument("--iface", required=True, help="Mac Ethernet interface connected to W5500 A.")
    parser.add_argument("--rate", type=float, default=5.0, help="Demo cycles per second. One cycle sends allow + selected decoys.")
    parser.add_argument("--count", type=int, default=0, help="Number of cycles to send; 0 means run forever.")
    parser.add_argument("--list-ifaces", action="store_true", help="List Scapy interface names and exit.")
    parser.add_argument("--verbose-each", action="store_true", help="Print one line per send cycle instead of updating one status line.")
    parser.add_argument("--udp-allow", action="store_true", help="Also send the UDP/80 allow profile. SSH allow is the default primary profile.")
    parser.add_argument("--no-tcp-drop", action="store_true", help="Do not send TCP/23 drop decoys.")
    args = parser.parse_args()

    if args.list_ifaces:
        print("Scapy interfaces:")
        for iface in get_if_list():
            print(f"  {iface}")
        return

    if args.rate <= 0:
        parser.error("--rate must be greater than 0")

    interval = 1.0 / args.rate
    sent_allow_udp = 0
    sent_allow_ssh = 0
    sent_drop = 0

    print("FPGA firewall rule demo sender")
    print(f"iface={args.iface} rate={args.rate:g} cycles/sec")
    print("Cycle: TCP/22 SSH allow, TCP/23 drop" + (", UDP/80 allow" if args.udp_allow else ""))
    print("Stop with Ctrl+C.")

    try:
        seq_iter = range(args.count) if args.count > 0 else itertools.count()
        for seq in seq_iter:
            sendp(allowed_ssh(seq), iface=args.iface, verbose=False)
            sent_allow_ssh += 1

            if args.udp_allow:
                sendp(allowed_udp(seq), iface=args.iface, verbose=False)
                sent_allow_udp += 1

            if not args.no_tcp_drop:
                sendp(dropped_tcp(seq), iface=args.iface, verbose=False)
                sent_drop += 1

            msg = f"seq={seq} udp_allow={sent_allow_udp} ssh_allow={sent_allow_ssh} expected_drop={sent_drop}"
            if args.verbose_each:
                print(msg, flush=True)
            else:
                print(f"\r{msg}", end="", flush=True)
            time.sleep(interval)
        print(f"\ndone: udp_allow={sent_allow_udp} ssh_allow={sent_allow_ssh} expected_drop={sent_drop}")
    except KeyboardInterrupt:
        print(f"\nstopped: udp_allow={sent_allow_udp} ssh_allow={sent_allow_ssh} expected_drop={sent_drop}")


if __name__ == "__main__":
    main()
