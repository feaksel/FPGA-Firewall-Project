#!/usr/bin/env python3
import argparse
import hashlib
import struct
import sys
import time
from pathlib import Path

try:
    from scapy.all import Ether, IP, TCP, UDP, Raw, sendp
except ImportError:
    print("Scapy is required. Install it with: pip install scapy", file=sys.stderr)
    sys.exit(1)


MAGIC = b"FWFILE1\0"
DEFAULT_SRC_MAC = "00:11:22:33:44:55"
DEFAULT_DST_MAC = "ff:ff:ff:ff:ff:ff"
DEFAULT_SRC_IP = "192.168.50.10"
DEFAULT_DST_IP = "192.168.50.20"
FILE_UDP_PORT = 5001


def build_file_payload(file_id: int, chunk_index: int, total_chunks: int, file_size: int, sha256_hex: str, data: bytes) -> bytes:
    sha_bytes = bytes.fromhex(sha256_hex)
    header = MAGIC + struct.pack("!HHHI", file_id, chunk_index, total_chunks, file_size) + sha_bytes
    return header + data


def build_allowed_chunk(args, file_id, chunk_index, total_chunks, file_size, sha256_hex, data):
    payload = build_file_payload(file_id, chunk_index, total_chunks, file_size, sha256_hex, data)
    return (
        Ether(dst=args.dst_mac, src=args.src_mac)
        / IP(src=args.src_ip, dst=args.dst_ip)
        / UDP(sport=args.src_port, dport=args.file_port)
        / Raw(load=payload)
    )


def build_decoy(args, chunk_index):
    marker = f"FW-DECOY-DROP-{chunk_index}".encode("ascii")
    if chunk_index % 2 == 0:
        return (
            Ether(dst=args.dst_mac, src=args.src_mac)
            / IP(src=args.blocked_src_ip, dst=args.dst_ip)
            / TCP(sport=41000 + (chunk_index % 1000), dport=23, flags="S")
            / Raw(load=marker)
        )

    return (
        Ether(dst=args.dst_mac, src=args.src_mac)
        / IP(src=args.src_ip, dst=args.dst_ip)
        / UDP(sport=args.src_port, dport=args.decoy_port)
        / Raw(load=marker)
    )


def main():
    parser = argparse.ArgumentParser(description="Send a chunked file demo through the inline FPGA firewall.")
    parser.add_argument("--iface", required=True, help="Scapy interface connected to W5500 A / FPGA ingress.")
    parser.add_argument("--file", required=True, help="File to send.")
    parser.add_argument("--chunk-size", type=int, default=512, help="Payload bytes per allowed file chunk.")
    parser.add_argument("--interval", type=float, default=0.01, help="Seconds between frames.")
    parser.add_argument("--file-id", type=int, default=1, help="16-bit file transfer id.")
    parser.add_argument("--src-mac", default=DEFAULT_SRC_MAC)
    parser.add_argument("--dst-mac", default=DEFAULT_DST_MAC)
    parser.add_argument("--src-ip", default=DEFAULT_SRC_IP)
    parser.add_argument("--dst-ip", default=DEFAULT_DST_IP)
    parser.add_argument("--blocked-src-ip", default="10.99.0.42")
    parser.add_argument("--src-port", type=int, default=40000)
    parser.add_argument("--file-port", type=int, default=FILE_UDP_PORT)
    parser.add_argument("--decoy-port", type=int, default=5002)
    parser.add_argument("--decoys", type=int, default=1, help="Decoy/drop frames to interleave after each chunk.")
    args = parser.parse_args()

    src_path = Path(args.file)
    data = src_path.read_bytes()
    sha256_hex = hashlib.sha256(data).hexdigest()
    chunks = [data[i : i + args.chunk_size] for i in range(0, len(data), args.chunk_size)]
    total_chunks = len(chunks)

    print(f"Sending {src_path} ({len(data)} bytes, {total_chunks} chunks)")
    print(f"sha256={sha256_hex}")
    print(f"allowed profile: UDP dst port {args.file_port}")
    print("blocked decoys: TCP dst port 23 and UDP non-file port")

    sent_allowed = 0
    sent_decoys = 0
    for chunk_index, chunk in enumerate(chunks):
        pkt = build_allowed_chunk(args, args.file_id, chunk_index, total_chunks, len(data), sha256_hex, chunk)
        sendp(pkt, iface=args.iface, verbose=False)
        sent_allowed += 1
        time.sleep(args.interval)

        for decoy_index in range(args.decoys):
            decoy = build_decoy(args, chunk_index * max(args.decoys, 1) + decoy_index)
            sendp(decoy, iface=args.iface, verbose=False)
            sent_decoys += 1
            time.sleep(args.interval)

    print(f"done: allowed_chunks={sent_allowed} decoys={sent_decoys}")


if __name__ == "__main__":
    main()
