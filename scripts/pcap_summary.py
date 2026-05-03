#!/usr/bin/env python3
import argparse
from collections import Counter

try:
    from scapy.all import Ether, IP, IPv6, PcapNgReader, Raw, TCP, UDP
except ImportError as exc:
    raise SystemExit("Scapy is required. Install it with: pip install scapy") from exc


MARKERS = [
    b"FW-DEMO-ALLOW-SSH",
    b"FW-DEMO-ALLOW",
    b"FW-DEMO-DROP-TCP23",
    b"FW-SINE",
]


def payload_bytes(pkt):
    try:
        raw = bytes(pkt)
    except Exception:
        raw = b""
    if Raw in pkt:
        return bytes(pkt[Raw].load) + raw
    return raw


def main():
    parser = argparse.ArgumentParser(description="Small Ethernet pcap summary for the FPGA firewall demo.")
    parser.add_argument("pcap")
    parser.add_argument("--limit", type=int, default=12)
    args = parser.parse_args()

    eth_pairs = Counter()
    eth_types = Counter()
    ip_pairs = Counter()
    l4 = Counter()
    markers = Counter()
    total = 0

    for pkt in PcapNgReader(args.pcap):
        total += 1
        if Ether in pkt:
            eth = pkt[Ether]
            eth_pairs[(eth.src, eth.dst)] += 1
            eth_types[f"0x{eth.type:04x}"] += 1
        if IP in pkt:
            ip = pkt[IP]
            ip_pairs[(ip.src, ip.dst)] += 1
        elif IPv6 in pkt:
            ip6 = pkt[IPv6]
            ip_pairs[(ip6.src, ip6.dst)] += 1
        if TCP in pkt:
            l4[(f"tcp/{pkt[TCP].sport}", f"tcp/{pkt[TCP].dport}")] += 1
        elif UDP in pkt:
            l4[(f"udp/{pkt[UDP].sport}", f"udp/{pkt[UDP].dport}")] += 1

        searchable = payload_bytes(pkt)
        for marker in MARKERS:
            if marker in searchable:
                markers[marker.decode("ascii")] += 1

    print(f"pcap={args.pcap}")
    print(f"total={total}")
    print("\nEther src -> dst:")
    for (src, dst), count in eth_pairs.most_common(args.limit):
        print(f"  {count:6d}  {src} -> {dst}")
    print("\nEthertypes:")
    for eth_type, count in eth_types.most_common(args.limit):
        print(f"  {count:6d}  {eth_type}")
    print("\nIP src -> dst:")
    for (src, dst), count in ip_pairs.most_common(args.limit):
        print(f"  {count:6d}  {src} -> {dst}")
    print("\nL4 ports:")
    for (src, dst), count in l4.most_common(args.limit):
        print(f"  {count:6d}  {src} -> {dst}")
    print("\nMarkers:")
    if markers:
        for marker, count in markers.most_common():
            print(f"  {count:6d}  {marker}")
    else:
        print("       0  demo markers")


if __name__ == "__main__":
    main()
