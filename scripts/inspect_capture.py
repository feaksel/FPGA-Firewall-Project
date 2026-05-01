#!/usr/bin/env python3
import sys
from collections import Counter

from scapy.all import Ether, IP, Raw, TCP, UDP, rdpcap


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: inspect_capture.py <capture.pcapng>")
        return 2

    packets = rdpcap(sys.argv[1])
    profiles = {"udp_allow": 0, "tcp_drop": 0, "tcp_allow_ssh": 0}
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
            for marker in (b"FW-UDP-ALLOW", b"FW-TCP-DROP", b"FW-TCP-ALLOW-SSH"):
                if marker in payload:
                    payload_hits[marker.decode("ascii")] += 1

        if Ether not in pkt or pkt[Ether].src.lower() != "00:11:22:33:44:55":
            continue

        payload = bytes(pkt[Raw].load) if Raw in pkt else b""
        name = "unknown"
        if b"FW-UDP-ALLOW" in payload:
            name = "udp_allow"
            profiles[name] += 1
        elif b"FW-TCP-DROP" in payload:
            name = "tcp_drop"
            profiles[name] += 1
        elif b"FW-TCP-ALLOW-SSH" in payload:
            name = "tcp_allow_ssh"
            profiles[name] += 1

        ip_info = ""
        if IP in pkt:
            ip_info = f"{pkt[IP].src}->{pkt[IP].dst} proto={pkt[IP].proto}"

        port_info = ""
        if UDP in pkt:
            port_info = f"udp {pkt[UDP].sport}->{pkt[UDP].dport}"
        elif TCP in pkt:
            port_info = f"tcp {pkt[TCP].sport}->{pkt[TCP].dport}"

        matches.append((idx, name, ip_info, port_info, len(pkt)))

    print(f"total_packets={len(packets)}")
    print(f"src_mac_00_11_22_33_44_55={len(matches)}")
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
