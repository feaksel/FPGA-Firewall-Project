#!/usr/bin/env python3
import argparse
import socket
import time

from file_sender import (
    DEFAULT_DST_IP,
    DEFAULT_SRC_IP,
    DEFAULT_W5500_A_MAC,
    FILE_UDP_PORT,
    DECOY_UDP_PORT,
    CONSERVATIVE_CHUNK_SIZE,
    SAFE_INTERVAL_SEC,
)
from media_demo_sender import send_bytes_as_file, setup_lines


def encode_snapshot(camera_index, max_side, jpeg_quality):
    try:
        import cv2
    except ImportError:
        raise SystemExit(
            "OpenCV is required for webcam capture. Install on PC1 with: python3 -m pip install opencv-python"
        )

    cap = cv2.VideoCapture(camera_index)
    if not cap.isOpened():
        raise SystemExit(f"Could not open webcam index {camera_index}. Check camera permission and try --camera-index 1.")
    ok, frame = cap.read()
    cap.release()
    if not ok or frame is None:
        raise SystemExit("Could not read a frame from the webcam.")

    height, width = frame.shape[:2]
    longest = max(width, height)
    if max_side > 0 and longest > max_side:
        scale = max_side / float(longest)
        frame = cv2.resize(frame, (int(width * scale), int(height * scale)), interpolation=cv2.INTER_AREA)

    ok, encoded = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), int(jpeg_quality)])
    if not ok:
        raise SystemExit("Could not encode webcam frame as JPEG.")
    return encoded.tobytes()


def main():
    parser = argparse.ArgumentParser(
        description="Capture webcam snapshots on PC1 and send them as JPEG file transfers through the FPGA UDP gateway."
    )
    parser.add_argument("--iface", default="en0", help="PC1 Ethernet interface used in setup hints.")
    parser.add_argument("--camera-index", type=int, default=0)
    parser.add_argument("--count", type=int, default=1, help="Number of snapshots to send; 0 sends until Ctrl+C.")
    parser.add_argument("--period", type=float, default=2.0, help="Seconds between webcam snapshots.")
    parser.add_argument("--max-side", type=int, default=320, help="Resize webcam JPEG to this max side before sending.")
    parser.add_argument("--jpeg-quality", type=int, default=70)
    parser.add_argument("--chunk-size", type=int, default=CONSERVATIVE_CHUNK_SIZE)
    parser.add_argument("--interval", type=float, default=SAFE_INTERVAL_SEC)
    parser.add_argument("--decoys", type=int, default=0, help="Decoys per chunk. Keep 0 for the cleanest visual webcam demo.")
    parser.add_argument("--file-id-start", type=int, default=500)
    parser.add_argument("--src-ip", default=DEFAULT_SRC_IP)
    parser.add_argument("--dst-ip", default=DEFAULT_DST_IP)
    parser.add_argument("--src-port", type=int, default=40030)
    parser.add_argument("--file-port", type=int, default=FILE_UDP_PORT)
    parser.add_argument("--decoy-port", type=int, default=DECOY_UDP_PORT)
    parser.add_argument("--w5500-mac", default=DEFAULT_W5500_A_MAC)
    parser.add_argument("--print-setup", action="store_true")
    args = parser.parse_args()

    if args.count < 0:
        parser.error("--count must be non-negative")
    if args.period < 0:
        parser.error("--period must be non-negative")
    if args.max_side < 0:
        parser.error("--max-side must be non-negative")
    if not 1 <= args.jpeg_quality <= 100:
        parser.error("--jpeg-quality must be 1..100")
    if args.chunk_size <= 0:
        parser.error("--chunk-size must be greater than zero")
    if args.interval < 0:
        parser.error("--interval must be non-negative")
    if args.decoys < 0:
        parser.error("--decoys must be non-negative")
    if not 0 <= args.file_id_start <= 65535:
        parser.error("--file-id-start must be 0..65535")

    if args.print_setup:
        print("\n".join(setup_lines(args)))
        return

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.src_ip, args.src_port))

    print("PC2 receiver:")
    print("  py -3 scripts\\file_receiver.py --iface Ethernet --port 8092")
    print("Setup commands:")
    for line in setup_lines(args):
        print(f"  {line}")
    print(
        f"webcam index={args.camera_index} count={'forever' if args.count == 0 else args.count} "
        f"period={args.period:g}s max_side={args.max_side} quality={args.jpeg_quality}"
    )

    sent = 0
    file_id = args.file_id_start
    try:
        while args.count == 0 or sent < args.count:
            data = encode_snapshot(args.camera_index, args.max_side, args.jpeg_quality)
            display_name = f"webcam_{sent:04d}.jpg"
            send_bytes_as_file(sock, args, data, display_name, file_id)
            file_id = (file_id + 1) & 0xFFFF
            sent += 1
            if args.count == 0 or sent < args.count:
                time.sleep(args.period)
    except KeyboardInterrupt:
        print()

    print(f"done: snapshots={sent}")


if __name__ == "__main__":
    main()
