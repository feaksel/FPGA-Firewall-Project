#!/usr/bin/env python3
import sys
from collections import Counter

from scapy.all import Ether, IP, Raw, TCP, UDP, rdpcap


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: inspect_capture.py <capture.pcapng>")
        return 2

    packets = rdpcap(sys.argv[1])
    profiles = {
        "allow80": 0,
        "allow5001": 0,
        "drop5002_marker": 0,
        "content_block_marker": 0,
        "file_marker": 0,
        "sine_marker": 0,
        "legacy_tcp_drop": 0,
        "legacy_tcp_allow_ssh": 0,
    }
    matches = []
    src_macs = Counter()
    dst_macs = Counter()
    ip_pairs = Counter()
    payload_hits = Counter()

    for idx, pkt in enumerate(packets, 1):
        if Ether in pkt:
            src_macs[pkt[Ether].src.lower()] += 1
            dst_macs[pkt[Ether].dst.lower()] += 1
        if IP in pkt:
            ip_pairs[(pkt[IP].src, pkt[IP].dst)] += 1
        if Raw in pkt:
            payload = bytes(pkt[Raw].load)
            marker_map = {
                b"FW-DEMO-ALLOW80": "allow80",
                b"FW-DEMO-ALLOW5001": "allow5001",
                b"FW-DEMO-DROP-UDP5002": "drop5002_marker",
                b"FW-BLOCK": "content_block_marker",
                b"FWFILE1\x00": "file_marker",
                b"FWSINE2\x00": "sine_marker",
                b"FW-TCP-DROP": "legacy_tcp_drop",
                b"FW-TCP-ALLOW-SSH": "legacy_tcp_allow_ssh",
            }
            for marker, profile in marker_map.items():
                if marker in payload:
                    payload_hits[marker.decode("ascii", errors="replace")] += 1
                    profiles[profile] += 1

        payload = bytes(pkt[Raw].load) if Raw in pkt else b""
        name = "unknown"
        if b"FW-DEMO-ALLOW80" in payload:
            name = "allow80"
        elif b"FW-DEMO-ALLOW5001" in payload:
            name = "allow5001"
        elif b"FW-DEMO-DROP-UDP5002" in payload:
            name = "drop5002_marker"
        elif b"FW-BLOCK" in payload:
            name = "content_block_marker"
        elif b"FWFILE1\x00" in payload:
            name = "file_marker"
        elif b"FWSINE2\x00" in payload:
            name = "sine_marker"
        elif b"FW-TCP-DROP" in payload:
            name = "legacy_tcp_drop"
        elif b"FW-TCP-ALLOW-SSH" in payload:
            name = "legacy_tcp_allow_ssh"

        ip_info = ""
        if IP in pkt:
            ip_info = f"{pkt[IP].src}->{pkt[IP].dst} proto={pkt[IP].proto}"

        port_info = ""
        if UDP in pkt:
            port_info = f"udp {pkt[UDP].sport}->{pkt[UDP].dport}"
        elif TCP in pkt:
            port_info = f"tcp {pkt[TCP].sport}->{pkt[TCP].dport}"

        if name != "unknown":
            matches.append((idx, name, ip_info, port_info, len(pkt)))

    print(f"total_packets={len(packets)}")
    print(f"demo_marker_packets={len(matches)}")
    for name, count in profiles.items():
        print(f"{name}={count}")
    print("first_matches:")
    for row in matches[:20]:
        print(row)
    print("top_src_macs:")
    for mac, count in src_macs.most_common(10):
        print(f"{mac}={count}")
    print("top_dst_macs:")
    for mac, count in dst_macs.most_common(10):
        print(f"{mac}={count}")
    print("top_ip_pairs:")
    for pair, count in ip_pairs.most_common(10):
        print(f"{pair[0]}->{pair[1]}={count}")
    print("payload_marker_hits:")
    for marker, count in payload_hits.items():
        print(f"{marker}={count}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
