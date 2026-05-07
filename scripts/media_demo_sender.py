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
    DECOY_UDP_PORT,
    CONSERVATIVE_CHUNK_SIZE,
    SAFE_INTERVAL_SEC,
    build_file_payload,
    build_decoy,
    synthesized_frame_len,
)


DEMO_DIR = Path("demo files")
DEMO_FILES = {
    "jpg": "demo_jpg.jpg",
    "png": "demo_png.png",
    "gif": "demo_gif.gif",
    "mp4": "demo_mp4.mp4",
}
IMAGE_PROFILES = {"jpg", "png", "gif"}


def setup_lines(args):
    return [
        f"sudo ifconfig {args.iface} inet {args.src_ip} netmask 255.255.255.0 up",
        f"sudo arp -d {args.dst_ip} 2>/dev/null || true",
        f"sudo arp -s {args.dst_ip} {args.w5500_mac}",
        f"sudo tcpdump -i {args.iface} -nn -e 'host {args.dst_ip} and udp'",
    ]


def expand_profiles(profile):
    if profile == "all":
        return ["jpg", "png", "gif", "mp4"]
    if profile == "images":
        return ["jpg", "png", "gif"]
    return [profile]


def encode_resized_image(path: Path, args):
    from io import BytesIO

    from PIL import Image

    target_bytes = args.image_target_kb * 1024
    best = None
    with Image.open(path) as img:
        img = img.convert("RGB")
        side = args.image_max_side
        while side >= 96:
            candidate = img.copy()
            candidate.thumbnail((side, side))
            for quality in (args.jpeg_quality, 60, 50, 40, 32):
                out = BytesIO()
                candidate.save(out, format="JPEG", quality=max(1, min(100, quality)), optimize=True)
                data = out.getvalue()
                best = data
                if len(data) <= target_bytes:
                    return data, side, quality, True
            side = int(side * 0.75)
    return best or path.read_bytes(), side, args.jpeg_quality, False


def load_media_bytes(path: Path, profile: str, args):
    data = path.read_bytes()
    if args.original or profile not in IMAGE_PROFILES or args.image_max_side <= 0:
        return data, path.name, "original"

    try:
        resized, side, quality, hit_target = encode_resized_image(path, args)
    except ImportError:
        raise SystemExit(
            "Pillow is required for the fast resized image demo. Install with: "
            "python3 -m pip install pillow, or add --original to send exact original bytes slowly."
        )

    status = "target" if hit_target else "best-effort"
    return resized, f"{path.stem}_{side}px_q{quality}.jpg", f"resized-jpeg-{status}"


def send_bytes_as_file(sock, args, data: bytes, display_name: str, file_id: int):
    sha256_hex = hashlib.sha256(data).hexdigest()
    chunks = [data[i : i + args.chunk_size] for i in range(0, len(data), args.chunk_size)]
    total_chunks = len(chunks)
    max_synth = synthesized_frame_len(max((len(chunk) for chunk in chunks), default=0))
    datagrams = total_chunks * (1 + args.decoys)
    duration = datagrams * args.interval

    print(
        f"send file_id={file_id} {display_name} bytes={len(data)} chunks={total_chunks} "
        f"sha256={sha256_hex[:12]}... synth_max={max_synth} est={duration:.1f}s"
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
        description="Send the checked-in demo media files through the FPGA UDP/5001 policy gateway."
    )
    parser.add_argument("--iface", default="en0", help="PC1 Ethernet interface used in setup hints.")
    parser.add_argument("--dir", default=str(DEMO_DIR), help="Folder containing demo_jpg.jpg, demo_png.png, demo_gif.gif, and demo_mp4.mp4.")
    parser.add_argument("--profile", choices=["jpg", "png", "gif", "mp4", "images", "all"], default="jpg")
    parser.add_argument("--repeat", type=int, default=1, help="Repeat selected media set this many times; 0 repeats until Ctrl+C.")
    parser.add_argument("--repeat-delay", type=float, default=0.5)
    parser.add_argument("--chunk-size", type=int, default=CONSERVATIVE_CHUNK_SIZE)
    parser.add_argument("--interval", type=float, default=SAFE_INTERVAL_SEC)
    parser.add_argument("--decoys", type=int, default=0, help="Decoys per chunk. Use 1 for policy proof, 0 for faster visual media demos.")
    parser.add_argument("--retry-passes", type=int, default=1, help="Send each selected media item this many times with the same file_id so PC2 can fill missed chunks.")
    parser.add_argument("--file-id-start", type=int, default=200)
    parser.add_argument("--original", action="store_true", help="Send exact image bytes instead of resized JPEG demo bytes.")
    parser.add_argument("--image-max-side", type=int, default=240, help="Resize JPG/PNG/GIF profiles to this max side before sending. Use 0 with --original behavior.")
    parser.add_argument("--image-target-kb", type=int, default=48, help="Best-effort target size for resized image payloads.")
    parser.add_argument("--jpeg-quality", type=int, default=65)
    parser.add_argument("--src-ip", default=DEFAULT_SRC_IP)
    parser.add_argument("--dst-ip", default=DEFAULT_DST_IP)
    parser.add_argument("--src-port", type=int, default=40020)
    parser.add_argument("--file-port", type=int, default=FILE_UDP_PORT)
    parser.add_argument("--decoy-port", type=int, default=DECOY_UDP_PORT)
    parser.add_argument("--w5500-mac", default=DEFAULT_W5500_A_MAC)
    parser.add_argument("--print-setup", action="store_true")
    args = parser.parse_args()

    if args.chunk_size <= 0:
        parser.error("--chunk-size must be greater than zero")
    if args.interval < 0:
        parser.error("--interval must be non-negative")
    if args.repeat < 0:
        parser.error("--repeat must be non-negative")
    if args.repeat_delay < 0:
        parser.error("--repeat-delay must be non-negative")
    if args.decoys < 0:
        parser.error("--decoys must be non-negative")
    if args.retry_passes <= 0:
        parser.error("--retry-passes must be greater than zero")
    if not 0 <= args.file_id_start <= 65535:
        parser.error("--file-id-start must be 0..65535")
    if args.image_max_side < 0:
        parser.error("--image-max-side must be non-negative")
    if args.image_target_kb <= 0:
        parser.error("--image-target-kb must be greater than zero")
    if not 1 <= args.jpeg_quality <= 100:
        parser.error("--jpeg-quality must be 1..100")

    if args.print_setup:
        print("\n".join(setup_lines(args)))
        return

    directory = Path(args.dir)
    profiles = expand_profiles(args.profile)
    paths = [(profile, directory / DEMO_FILES[profile]) for profile in profiles]
    missing = [str(path) for _, path in paths if not path.exists()]
    if missing:
        parser.error("missing demo file(s): " + ", ".join(missing))

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.src_ip, args.src_port))

    print("PC2 receiver:")
    print("  py -3 scripts\\file_receiver.py --iface Ethernet --port 8092")
    print("Setup commands:")
    for line in setup_lines(args):
        print(f"  {line}")
    print(
        f"profile={args.profile} interval={args.interval:g}s chunk_size={args.chunk_size} "
        f"decoys={args.decoys} retry_passes={args.retry_passes} "
        f"image_max_side={args.image_max_side} image_target_kb={args.image_target_kb} original={args.original}"
    )

    file_id = args.file_id_start
    pass_index = 0
    total_allowed = 0
    total_decoys = 0
    try:
        while args.repeat == 0 or pass_index < args.repeat:
            for profile, path in paths:
                data, display_name, mode = load_media_bytes(path, profile, args)
                print(f"source={path} mode={mode}")
                for retry_pass in range(args.retry_passes):
                    if args.retry_passes > 1:
                        print(f"  retry pass {retry_pass + 1}/{args.retry_passes} with file_id={file_id}")
                    allowed, decoys = send_bytes_as_file(sock, args, data, display_name, file_id)
                    total_allowed += allowed
                    total_decoys += decoys
                file_id = (file_id + 1) & 0xFFFF
            pass_index += 1
            if args.repeat == 0 or pass_index < args.repeat:
                time.sleep(args.repeat_delay)
    except KeyboardInterrupt:
        print()

    print(f"done: passes={pass_index} allowed_chunks={total_allowed} decoys={total_decoys}")


if __name__ == "__main__":
    main()
