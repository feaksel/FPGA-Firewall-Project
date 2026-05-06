#!/usr/bin/env python3
import argparse
import hashlib
import socket
import struct
import time
from pathlib import Path


MAGIC = b"FWFILE1\0"
FILE_HEADER_BYTES = len(MAGIC) + 2 + 2 + 2 + 4 + 32
SYNTH_ETH_IPV4_UDP_BYTES = 42
CONSERVATIVE_FPGA_FRAME_LIMIT = 512
CONSERVATIVE_CHUNK_SIZE = 256
DEFAULT_SRC_IP = "192.168.1.10"
DEFAULT_DST_IP = "192.168.1.1"
DEFAULT_W5500_A_MAC = "02:00:00:de:ad:0a"
FILE_UDP_PORT = 5001
DECOY_UDP_PORT = 5002


def build_file_payload(file_id: int, chunk_index: int, total_chunks: int, file_size: int, sha256_hex: str, data: bytes) -> bytes:
    sha_bytes = bytes.fromhex(sha256_hex)
    header = MAGIC + struct.pack("!HHHI", file_id, chunk_index, total_chunks, file_size) + sha_bytes
    return header + data


def synthesized_frame_len(data_len: int) -> int:
    return SYNTH_ETH_IPV4_UDP_BYTES + FILE_HEADER_BYTES + data_len


def build_decoy(chunk_index, file_port, decoy_port):
    if chunk_index % 2 == 0:
        return decoy_port, f"FW-DEMO-DROP-UDP5002 decoy={chunk_index}".encode("ascii")
    return file_port, f"FW-BLOCK file-port-content-block decoy={chunk_index}".encode("ascii")


def main():
    parser = argparse.ArgumentParser(description="Send a chunked file through the FPGA UDP policy gateway.")
    parser.add_argument("--iface", default="en0", help="PC1 Ethernet interface used in setup hints.")
    parser.add_argument("--file", required=True, help="File to send.")
    parser.add_argument(
        "--chunk-size",
        type=int,
        default=CONSERVATIVE_CHUNK_SIZE,
        help="Payload bytes per allowed file chunk. Default keeps synthesized FPGA frames below 512 bytes.",
    )
    parser.add_argument("--interval", type=float, default=0.01, help="Seconds between UDP datagrams.")
    parser.add_argument("--file-id", type=int, default=1, help="16-bit file transfer id.")
    parser.add_argument("--src-ip", default=DEFAULT_SRC_IP)
    parser.add_argument("--dst-ip", default=DEFAULT_DST_IP)
    parser.add_argument("--src-port", type=int, default=40000)
    parser.add_argument("--file-port", type=int, default=FILE_UDP_PORT)
    parser.add_argument("--decoy-port", type=int, default=DECOY_UDP_PORT)
    parser.add_argument("--w5500-mac", default=DEFAULT_W5500_A_MAC, help="W5500 A SHAR for setup hints.")
    parser.add_argument("--decoys", type=int, default=1, help="Decoy/drop datagrams to interleave after each chunk.")
    parser.add_argument("--print-setup", action="store_true", help="Print PC1 setup commands and exit.")
    args = parser.parse_args()

    if args.chunk_size <= 0:
        parser.error("--chunk-size must be greater than zero")
    if args.src_port < 1 or args.src_port > 65535:
        parser.error("--src-port must be 1..65535")

    setup = [
        f"sudo ifconfig {args.iface} inet {args.src_ip} netmask 255.255.255.0 up",
        f"sudo arp -d {args.dst_ip} 2>/dev/null || true",
        f"sudo arp -s {args.dst_ip} {args.w5500_mac}",
        f"sudo tcpdump -i {args.iface} -nn -e 'host {args.dst_ip} and udp'",
    ]
    if args.print_setup:
        print("\n".join(setup))
        return

    src_path = Path(args.file)
    data = src_path.read_bytes()
    sha256_hex = hashlib.sha256(data).hexdigest()
    chunks = [data[i : i + args.chunk_size] for i in range(0, len(data), args.chunk_size)]
    total_chunks = len(chunks)
    max_synth_frame = synthesized_frame_len(max((len(chunk) for chunk in chunks), default=0))
    conservative_max_chunk = CONSERVATIVE_FPGA_FRAME_LIMIT - SYNTH_ETH_IPV4_UDP_BYTES - FILE_HEADER_BYTES

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.src_ip, args.src_port))

    print(f"Sending {src_path} ({len(data)} bytes, {total_chunks} chunks)")
    print(f"sha256={sha256_hex}")
    print(f"src={args.src_ip}:{args.src_port} dst={args.dst_ip}")
    print(f"chunk_size={args.chunk_size} synthesized_frame_max={max_synth_frame} bytes")
    if max_synth_frame > CONSERVATIVE_FPGA_FRAME_LIMIT:
        print(
            "WARNING: synthesized frames exceed the conservative 512-byte FPGA ingress limit. "
            f"Use --chunk-size {conservative_max_chunk} or smaller if only the final short chunk arrives."
        )
    print(f"allowed profile: UDP dst port {args.file_port} with {MAGIC!r} marker")
    print(f"blocked decoys: UDP dst port {args.decoy_port} and FW-BLOCK content override")
    print("Setup commands:")
    for cmd in setup:
        print(f"  {cmd}")

    sent_allowed = 0
    sent_decoys = 0
    for chunk_index, chunk in enumerate(chunks):
        payload = build_file_payload(args.file_id, chunk_index, total_chunks, len(data), sha256_hex, chunk)
        sock.sendto(payload, (args.dst_ip, args.file_port))
        sent_allowed += 1
        time.sleep(args.interval)

        for decoy_index in range(args.decoys):
            decoy_port, decoy_payload = build_decoy(
                chunk_index * max(args.decoys, 1) + decoy_index,
                args.file_port,
                args.decoy_port,
            )
            sock.sendto(decoy_payload, (args.dst_ip, decoy_port))
            sent_decoys += 1
            time.sleep(args.interval)

    print(f"done: allowed_chunks={sent_allowed} decoys={sent_decoys}")


if __name__ == "__main__":
    main()
