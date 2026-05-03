#!/usr/bin/env python3
import argparse
import os
import sys
from collections import OrderedDict
from datetime import datetime

try:
    from scapy.all import Ether, Raw, sniff
except ImportError:
    print("Scapy is required. Install it with: pip install scapy", file=sys.stderr)
    sys.exit(1)


DEFAULT_SRC_MAC = "00:11:22:33:44:55"

PROFILES = OrderedDict(
    (
        ("udp_allow", (b"FW-UDP-ALLOW", "ALLOW")),
        ("tcp_drop", (b"FW-TCP-DROP", "DROP")),
        ("tcp_allow_ssh", (b"FW-TCP-ALLOW-SSH", "ALLOW")),
    )
)


def clear_screen():
    os.system("cls" if os.name == "nt" else "clear")


def find_profile(pkt, src_mac):
    if Ether not in pkt:
        return None
    if src_mac is not None and pkt[Ether].src.lower() != src_mac:
        return None

    payload = bytes(pkt[Raw].load) if Raw in pkt else b""
    for name, (marker, expected) in PROFILES.items():
        if marker in payload:
            return name, expected

    return "unknown", "UNKNOWN"


def render(counts, last_seen, src_mac):
    clear_screen()
    print("FPGA firewall PC-side traffic view")
    print(f"Interface traffic source filter: {src_mac or 'any'}")
    print()
    print(f"{'profile':<18} {'expected':<9} {'count':>6}  last seen")
    print("-" * 55)
    for name, (_, expected) in PROFILES.items():
        print(f"{name:<18} {expected:<9} {counts[name]:>6}  {last_seen[name] or '-'}")
    print(f"{'unknown':<18} {'UNKNOWN':<9} {counts['unknown']:>6}  {last_seen['unknown'] or '-'}")
    print()
    print("FPGA actual decision is on LEDs/HEX. Stop with Ctrl+C.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Live PC-side view for deterministic FPGA firewall packets.")
    parser.add_argument("--iface", default="Ethernet", help="Scapy interface name to sniff.")
    parser.add_argument("--src-mac", default=DEFAULT_SRC_MAC, help="Optional source MAC filter; use 'any' to match markers from any source.")
    args = parser.parse_args()
    src_mac = None if args.src_mac.lower() == "any" else args.src_mac.lower()

    counts = {name: 0 for name in PROFILES}
    counts["unknown"] = 0
    last_seen = {name: "" for name in counts}
    render(counts, last_seen, src_mac)

    def on_packet(pkt):
        result = find_profile(pkt, src_mac)
        if result is None:
            return
        name, _expected = result
        counts[name] += 1
        last_seen[name] = datetime.now().strftime("%H:%M:%S")
        render(counts, last_seen, src_mac)

    try:
        sniff(iface=args.iface, prn=on_packet, store=False)
    except KeyboardInterrupt:
        print()
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
