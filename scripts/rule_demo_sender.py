#!/usr/bin/env python3
import argparse
import itertools
import sys
import time

try:
    from scapy.all import Ether, IP, TCP, UDP, Raw, get_if_hwaddr, get_if_list, sendp
except ImportError:
    print("Scapy is required. Install it with: pip install scapy", file=sys.stderr)
    sys.exit(1)


DEFAULT_DST_MAC = "01:00:5e:00:00:fb"
ALLOW_SRC_IP = "192.168.1.10"
ALLOW_DST_IP = "192.168.1.1"
DROP_SRC_IP = "10.0.0.42"
DROP_DST_IP = "192.168.1.99"
SSH_SRC_IP = "10.1.2.3"
SSH_DST_IP = "192.168.1.99"


def allowed_udp(seq, src_mac, dst_mac):
    return (
        Ether(dst=dst_mac, src=src_mac)
        / IP(src=ALLOW_SRC_IP, dst=ALLOW_DST_IP, proto=17)
        / UDP(sport=0x1234, dport=80)
        / Raw(load=f"FW-DEMO-ALLOW seq={seq}".encode("ascii"))
    )


def dropped_tcp(seq, src_mac, dst_mac):
    return (
        Ether(dst=dst_mac, src=src_mac)
        / IP(src=DROP_SRC_IP, dst=DROP_DST_IP, proto=6)
        / TCP(sport=0x1234, dport=23, flags="S")
        / Raw(load=f"FW-DEMO-DROP-TCP23 seq={seq}".encode("ascii"))
    )


def allowed_ssh(seq, src_mac, dst_mac):
    return (
        Ether(dst=dst_mac, src=src_mac)
        / IP(src=SSH_SRC_IP, dst=SSH_DST_IP, proto=6)
        / TCP(sport=0x08AE, dport=22, flags="S")
        / Raw(load=f"FW-DEMO-ALLOW-SSH seq={seq}".encode("ascii"))
    )

def main():
    parser = argparse.ArgumentParser(description="Simple continuous FPGA firewall rule demo sender.")
    parser.add_argument("--iface", required=True, help="Mac Ethernet interface connected to W5500 A.")
    parser.add_argument("--rate", type=float, default=1.0, help="Demo cycles per second. One cycle sends allow + selected decoys.")
    parser.add_argument("--count", type=int, default=0, help="Number of cycles to send; 0 means run forever.")
    parser.add_argument("--burst", type=int, default=1, help="Repeat each packet this many times per cycle.")
    parser.add_argument("--packet-gap", type=float, default=0.15, help="Seconds to wait between individual packets in a cycle.")
    parser.add_argument("--list-ifaces", action="store_true", help="List Scapy interface names and exit.")
    parser.add_argument("--verbose-each", action="store_true", help="Print one line per send cycle instead of updating one status line.")
    parser.add_argument("--dst-mac", default=DEFAULT_DST_MAC, help="Ethernet destination MAC. Default uses IPv4 multicast because that path is proven on the two-W5500 bench.")
    parser.add_argument("--udp-allow", action="store_true", default=True, help="Send the UDP/80 allow profile. Enabled by default.")
    parser.add_argument("--no-udp-allow", action="store_false", dest="udp_allow", help="Disable the UDP/80 allow profile.")
    parser.add_argument("--no-ssh-allow", action="store_true", help="Do not send TCP/22 SSH allow frames.")
    parser.add_argument("--no-tcp-drop", action="store_true", help="Do not send TCP/23 drop decoys.")
    parser.add_argument("--src-mac", help="Override Ethernet source MAC. Default uses the selected interface's real MAC.")
    args = parser.parse_args()

    if args.list_ifaces:
        print("Scapy interfaces:")
        for iface in get_if_list():
            print(f"  {iface}")
        return

    if args.rate <= 0:
        parser.error("--rate must be greater than 0")
    if args.burst <= 0:
        parser.error("--burst must be greater than 0")
    if args.packet_gap < 0:
        parser.error("--packet-gap must be zero or greater")

    src_mac = args.src_mac
    if src_mac is None:
        try:
            src_mac = get_if_hwaddr(args.iface)
        except Exception as exc:
            parser.error(f"could not read MAC for {args.iface}: {exc}")

    interval = 1.0 / args.rate
    sent_allow_udp = 0
    sent_allow_ssh = 0
    sent_drop = 0

    print("FPGA firewall rule demo sender")
    print(f"iface={args.iface} rate={args.rate:g} cycles/sec")
    print(f"src_mac={src_mac} dst_mac={args.dst_mac}")
    profiles = []
    if args.udp_allow:
        profiles.append("UDP/80 allow")
    if not args.no_ssh_allow:
        profiles.append("TCP/22 SSH allow")
    if not args.no_tcp_drop:
        profiles.append("TCP/23 drop")
    print("Cycle: " + ", ".join(profiles))
    print(f"burst={args.burst} copies/profile/cycle packet_gap={args.packet_gap:g}s")
    print("Stop with Ctrl+C.")

    try:
        seq_iter = range(args.count) if args.count > 0 else itertools.count()
        for seq in seq_iter:
            if args.udp_allow:
                for _ in range(args.burst):
                    sendp(allowed_udp(seq, src_mac, args.dst_mac), iface=args.iface, verbose=False)
                    sent_allow_udp += 1
                    time.sleep(args.packet_gap)

            if not args.no_ssh_allow:
                for _ in range(args.burst):
                    sendp(allowed_ssh(seq, src_mac, args.dst_mac), iface=args.iface, verbose=False)
                    sent_allow_ssh += 1
                    time.sleep(args.packet_gap)

            if not args.no_tcp_drop:
                for _ in range(args.burst):
                    sendp(dropped_tcp(seq, src_mac, args.dst_mac), iface=args.iface, verbose=False)
                    sent_drop += 1
                    time.sleep(args.packet_gap)

            msg = f"seq={seq} udp_allow={sent_allow_udp} ssh_allow={sent_allow_ssh} expected_drop={sent_drop}"
            if args.verbose_each:
                print(msg, flush=True)
            else:
                print(f"\r{msg}", end="", flush=True)
            profile_count = int(args.udp_allow) + int(not args.no_ssh_allow) + int(not args.no_tcp_drop)
            time.sleep(max(interval - (args.packet_gap * args.burst * profile_count), 0.0))
        print(f"\ndone: udp_allow={sent_allow_udp} ssh_allow={sent_allow_ssh} expected_drop={sent_drop}")
    except KeyboardInterrupt:
        print(f"\nstopped: udp_allow={sent_allow_udp} ssh_allow={sent_allow_ssh} expected_drop={sent_drop}")


if __name__ == "__main__":
    main()
