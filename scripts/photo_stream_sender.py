#!/usr/bin/env python3
import argparse
import hashlib
import socket
import time
from pathlib import Path

from file_sender import (
    DEFAULT_DST_IP,
    DEFAULT_SRC_IP,
    DEFAULT_W5500_A_MAC,
    FILE_UDP_PORT,
    CONSERVATIVE_CHUNK_SIZE,
    SAFE_INTERVAL_SEC,
    build_file_payload,
    build_decoy,
    synthesized_frame_len,
)


DEFAULT_PATTERNS = "*.jpg,*.jpeg,*.png"


def collect_images(directory: Path, patterns: str):
    files = []
    for pattern in patterns.split(","):
        pattern = pattern.strip()
        if pattern:
            files.extend(directory.glob(pattern))
    return sorted(path for path in files if path.is_file())


def send_one_image(sock, args, path: Path, file_id: int):
    data = path.read_bytes()
    sha256_hex = hashlib.sha256(data).hexdigest()
    chunks = [data[i : i + args.chunk_size] for i in range(0, len(data), args.chunk_size)]
    total_chunks = len(chunks)
    max_synth = synthesized_frame_len(max((len(chunk) for chunk in chunks), default=0))

    print(
        f"frame file_id={file_id} {path.name} bytes={len(data)} chunks={total_chunks} "
        f"sha256={sha256_hex[:12]}... synth_max={max_synth}"
    )

    sent_allowed = 0
    sent_decoys = 0
    for chunk_index, chunk in enumerate(chunks):
        payload = build_file_payload(file_id, chunk_index, total_chunks, len(data), sha256_hex, chunk)
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

    return sent_allowed, sent_decoys


def main():
    parser = argparse.ArgumentParser(
        description="Send a directory of JPEG/PNG files as successive FPGA UDP file-demo transfers."
    )
    parser.add_argument("--iface", default="en0", help="PC1 Ethernet interface used in setup hints.")
    parser.add_argument("--dir", required=True, help="Directory containing JPEG/PNG frames.")
    parser.add_argument("--patterns", default=DEFAULT_PATTERNS, help="Comma-separated glob patterns. Default: *.jpg,*.jpeg,*.png")
    parser.add_argument("--loop", action="store_true", help="Repeat the image list until Ctrl+C.")
    parser.add_argument("--watch", action="store_true", help="Keep rescanning the directory and send new images as they appear.")
    parser.add_argument("--watch-interval", type=float, default=1.0, help="Seconds between directory rescans in --watch mode.")
    parser.add_argument("--frame-gap", type=float, default=0.5, help="Seconds to wait after each complete image.")
    parser.add_argument("--chunk-size", type=int, default=CONSERVATIVE_CHUNK_SIZE)
    parser.add_argument("--interval", type=float, default=SAFE_INTERVAL_SEC, help="Seconds between UDP datagrams.")
    parser.add_argument("--file-id-start", type=int, default=100, help="First 16-bit file_id to use.")
    parser.add_argument("--src-ip", default=DEFAULT_SRC_IP)
    parser.add_argument("--dst-ip", default=DEFAULT_DST_IP)
    parser.add_argument("--src-port", type=int, default=40010)
    parser.add_argument("--file-port", type=int, default=FILE_UDP_PORT)
    parser.add_argument("--decoy-port", type=int, default=5002)
    parser.add_argument("--w5500-mac", default=DEFAULT_W5500_A_MAC, help="W5500 A SHAR for setup hints.")
    parser.add_argument("--decoys", type=int, default=0, help="Decoys to interleave after each image chunk. Keep 0 for the fastest visual stream.")
    parser.add_argument("--print-setup", action="store_true", help="Print PC1 setup commands and exit.")
    args = parser.parse_args()

    if args.chunk_size <= 0:
        parser.error("--chunk-size must be greater than zero")
    if args.interval < 0:
        parser.error("--interval must be non-negative")
    if args.frame_gap < 0:
        parser.error("--frame-gap must be non-negative")
    if args.decoys < 0:
        parser.error("--decoys must be non-negative")
    if not 0 <= args.file_id_start <= 65535:
        parser.error("--file-id-start must be 0..65535")
    if args.watch_interval < 0:
        parser.error("--watch-interval must be non-negative")
    if args.loop and args.watch:
        parser.error("--loop and --watch are mutually exclusive")

    setup = [
        f"sudo ifconfig {args.iface} inet {args.src_ip} netmask 255.255.255.0 up",
        f"sudo arp -d {args.dst_ip} 2>/dev/null || true",
        f"sudo arp -s {args.dst_ip} {args.w5500_mac}",
        f"sudo tcpdump -i {args.iface} -nn -e 'host {args.dst_ip} and udp'",
    ]
    if args.print_setup:
        print("\n".join(setup))
        return

    directory = Path(args.dir)
    images = collect_images(directory, args.patterns)
    if not images:
        parser.error(f"no images found in {directory} matching {args.patterns}")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.src_ip, args.src_port))

    print(f"Sending {len(images)} image(s) from {directory}")
    print(f"patterns={args.patterns} chunk_size={args.chunk_size} interval={args.interval:g}s frame_gap={args.frame_gap:g}s decoys={args.decoys}")
    print("Use small compressed images for a fluid demo, for example 160x120 or 320x240 JPEG/PNG.")
    print("PC2 receiver should run: py -3 scripts\\file_receiver.py --iface Ethernet --port 8092")
    print("Setup commands:")
    for cmd in setup:
        print(f"  {cmd}")

    file_id = args.file_id_start
    total_allowed = 0
    total_decoys = 0
    sent_paths = set()
    try:
        while True:
            if args.watch:
                images = [path for path in collect_images(directory, args.patterns) if path not in sent_paths]
                if not images:
                    time.sleep(args.watch_interval)
                    continue

            for path in images:
                allowed, decoys = send_one_image(sock, args, path, file_id)
                total_allowed += allowed
                total_decoys += decoys
                sent_paths.add(path)
                file_id = (file_id + 1) & 0xFFFF
                time.sleep(args.frame_gap)
            if args.watch:
                time.sleep(args.watch_interval)
            elif not args.loop:
                break
    except KeyboardInterrupt:
        print()

    print(f"done: image_chunks={total_allowed} decoys={total_decoys}")


if __name__ == "__main__":
    main()
