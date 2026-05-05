#!/usr/bin/env python3
import argparse
import itertools
import socket
import time


DEFAULT_SRC_IP = "192.168.1.10"
DEFAULT_SRC_PORT = 0x1234
DEFAULT_DST_IP = "192.168.1.1"
DEFAULT_DST_PORT = 80
DEFAULT_W5500_A_MAC = "02:00:00:de:ad:0a"


def build_payload(seq, min_bytes):
    marker = f"FW-DEMO-ALLOW seq={seq}".encode("ascii")
    if len(marker) >= min_bytes:
        return marker
    return marker + (b"." * (min_bytes - len(marker)))


def main():
    parser = argparse.ArgumentParser(
        description="Normal UDP-socket sender for the FPGA firewall rule demo."
    )
    parser.add_argument("--iface", default="en0", help="PC1 Ethernet interface used in setup hints.")
    parser.add_argument("--src-ip", default=DEFAULT_SRC_IP, help="Source IP to bind. This must be assigned to the PC1 interface.")
    parser.add_argument("--src-port", type=int, default=DEFAULT_SRC_PORT, help="UDP source port.")
    parser.add_argument("--dst-ip", default=DEFAULT_DST_IP, help="Destination IP with a static ARP entry pointing at W5500 A.")
    parser.add_argument("--dst-port", type=int, default=DEFAULT_DST_PORT, help="UDP destination port.")
    parser.add_argument("--w5500-mac", default=DEFAULT_W5500_A_MAC, help="W5500 A SHAR for setup hints.")
    parser.add_argument("--rate", type=float, default=2.0, help="Packets per second.")
    parser.add_argument("--count", type=int, default=0, help="Packets to send; 0 means run forever.")
    parser.add_argument("--payload-min-bytes", type=int, default=96, help="Pad payload to at least this many bytes.")
    parser.add_argument("--verbose-each", action="store_true", help="Print one line per packet.")
    parser.add_argument("--print-setup", action="store_true", help="Print the PC1 setup commands and exit.")
    args = parser.parse_args()

    if args.rate <= 0:
        parser.error("--rate must be greater than 0")
    if args.src_port < 1 or args.src_port > 65535:
        parser.error("--src-port must be 1..65535")
    if args.dst_port < 1 or args.dst_port > 65535:
        parser.error("--dst-port must be 1..65535")
    if args.payload_min_bytes < 0:
        parser.error("--payload-min-bytes must be zero or greater")

    setup = [
        f"sudo ifconfig {args.iface} inet {args.src_ip} netmask 255.255.255.0 up",
        f"sudo arp -d {args.dst_ip} 2>/dev/null || true",
        f"sudo arp -s {args.dst_ip} {args.w5500_mac}",
        f"sudo tcpdump -i {args.iface} -nn -e 'udp port {args.dst_port} and host {args.dst_ip}'",
    ]
    if args.print_setup:
        print("\n".join(setup))
        return

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.src_ip, args.src_port))

    interval = 1.0 / args.rate
    sent = 0

    print("FPGA firewall UDP socket sender")
    print(f"iface={args.iface} src={args.src_ip}:{args.src_port} dst={args.dst_ip}:{args.dst_port}")
    print(f"static ARP required: {args.dst_ip} -> {args.w5500_mac}")
    print("Setup commands:")
    for cmd in setup:
        print(f"  {cmd}")
    print("Stop with Ctrl+C.")

    try:
        seq_iter = range(args.count) if args.count > 0 else itertools.count()
        for seq in seq_iter:
            payload = build_payload(seq, args.payload_min_bytes)
            sock.sendto(payload, (args.dst_ip, args.dst_port))
            sent += 1
            msg = f"seq={seq} udp_allow={sent} bytes={len(payload)}"
            if args.verbose_each:
                print(msg, flush=True)
            else:
                print(f"\r{msg}", end="", flush=True)
            time.sleep(interval)
        print(f"\ndone: udp_allow={sent}")
    except KeyboardInterrupt:
        print(f"\nstopped: udp_allow={sent}")


if __name__ == "__main__":
    main()
