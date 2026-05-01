#!/usr/bin/env python3
import argparse
import hashlib
import struct
import sys
import time
from pathlib import Path

try:
    from scapy.all import Raw, UDP, sniff
except ImportError:
    print("Scapy is required. Install it with: pip install scapy", file=sys.stderr)
    sys.exit(1)


MAGIC = b"FWFILE1\0"
HEADER_LEN = len(MAGIC) + 2 + 2 + 2 + 4 + 32
FILE_UDP_PORT = 5001


def parse_payload(payload: bytes):
    if len(payload) < HEADER_LEN or not payload.startswith(MAGIC):
        return None
    offset = len(MAGIC)
    file_id, chunk_index, total_chunks, file_size = struct.unpack("!HHHI", payload[offset : offset + 10])
    offset += 10
    sha256_hex = payload[offset : offset + 32].hex()
    offset += 32
    return {
        "file_id": file_id,
        "chunk_index": chunk_index,
        "total_chunks": total_chunks,
        "file_size": file_size,
        "sha256": sha256_hex,
        "data": payload[offset:],
    }


class Receiver:
    def __init__(self, output_path, file_port):
        self.output_path = Path(output_path)
        self.file_port = file_port
        self.file_id = None
        self.total_chunks = None
        self.file_size = None
        self.expected_sha = None
        self.chunks = {}
        self.last_update = time.time()

    def handle_packet(self, pkt):
        if UDP not in pkt or pkt[UDP].dport != self.file_port or Raw not in pkt:
            return

        parsed = parse_payload(bytes(pkt[Raw].load))
        if parsed is None:
            return

        if self.file_id is None:
            self.file_id = parsed["file_id"]
            self.total_chunks = parsed["total_chunks"]
            self.file_size = parsed["file_size"]
            self.expected_sha = parsed["sha256"]
            print(f"transfer started: file_id={self.file_id} chunks={self.total_chunks} bytes={self.file_size}")
            print(f"expected sha256={self.expected_sha}")

        if parsed["file_id"] != self.file_id:
            return

        self.chunks[parsed["chunk_index"]] = parsed["data"]
        now = time.time()
        if now - self.last_update >= 0.25 or len(self.chunks) == self.total_chunks:
            self.last_update = now
            missing = self.missing_chunks()
            print(f"received {len(self.chunks)}/{self.total_chunks} chunks, missing={len(missing)}")

        if self.complete():
            self.finish()
            raise KeyboardInterrupt

    def missing_chunks(self):
        if self.total_chunks is None:
            return []
        return [idx for idx in range(self.total_chunks) if idx not in self.chunks]

    def complete(self):
        return self.total_chunks is not None and len(self.chunks) == self.total_chunks

    def finish(self):
        data = b"".join(self.chunks[idx] for idx in range(self.total_chunks))[: self.file_size]
        actual_sha = hashlib.sha256(data).hexdigest()
        self.output_path.write_bytes(data)
        print(f"wrote {self.output_path} ({len(data)} bytes)")
        print(f"actual sha256={actual_sha}")
        if actual_sha == self.expected_sha:
            print("PASS: reconstructed file checksum matches")
        else:
            print("FAIL: checksum mismatch")


def main():
    parser = argparse.ArgumentParser(description="Receive and reconstruct the inline firewall file demo.")
    parser.add_argument("--iface", required=True, help="Scapy interface connected to W5500 B / FPGA egress.")
    parser.add_argument("--output", default="received_fw_file.bin", help="Reconstructed file path.")
    parser.add_argument("--file-port", type=int, default=FILE_UDP_PORT)
    parser.add_argument("--timeout", type=int, default=60, help="Sniff timeout in seconds.")
    args = parser.parse_args()

    receiver = Receiver(args.output, args.file_port)
    print(f"listening on {args.iface} for UDP dst port {args.file_port}")
    try:
        sniff(iface=args.iface, prn=receiver.handle_packet, store=False, timeout=args.timeout)
    except KeyboardInterrupt:
        pass

    if not receiver.complete():
        missing = receiver.missing_chunks()
        print(f"incomplete: received {len(receiver.chunks)}/{receiver.total_chunks or '?'} chunks")
        if missing:
            print("missing chunks:", ",".join(str(idx) for idx in missing[:40]))


if __name__ == "__main__":
    main()
