#!/usr/bin/env python3
import argparse
import itertools
import socket
import time


DEFAULT_SRC_IP = "192.168.1.10"
DEFAULT_SRC_PORT = 0x1234
DEFAULT_DST_IP = "192.168.1.1"
DEFAULT_W5500_A_MAC = "02:00:00:de:ad:0a"


PROFILES = (
    ("allow80", 80, b"FW-DEMO-ALLOW80"),
    ("allow5001", 5001, b"FWFILE1\x00FW-DEMO-ALLOW5001"),
    ("drop5002", 5002, b"FW-UDP5002-DROP"),
    ("block80", 80, b"FW-BLOCK content-block"),
)


def build_payload(profile, seq, min_bytes):
    name, _port, marker = profile
    payload = marker + f" profile={name} seq={seq}".encode("ascii")
    if len(payload) >= min_bytes:
        return payload
    return payload + (b"." * (min_bytes - len(payload)))


def main():
    parser = argparse.ArgumentParser(
        description="Normal UDP-socket sender for the FPGA UDP policy gateway demo."
    )
    parser.add_argument("--iface", default="en0", help="PC1 Ethernet interface used in setup hints.")
    parser.add_argument("--src-ip", default=DEFAULT_SRC_IP, help="Source IP to bind. This must be assigned to the PC1 interface.")
    parser.add_argument("--src-port", type=int, default=DEFAULT_SRC_PORT, help="UDP source port.")
    parser.add_argument("--dst-ip", default=DEFAULT_DST_IP, help="W5500 A IP with a static ARP entry.")
    parser.add_argument("--w5500-mac", default=DEFAULT_W5500_A_MAC, help="W5500 A SHAR for setup hints.")
    parser.add_argument("--rate", type=float, default=1.0, help="Profile cycles per second.")
    parser.add_argument("--count", type=int, default=0, help="Cycles to send; 0 means run forever.")
    parser.add_argument("--packet-gap", type=float, default=0.05, help="Seconds between profiles within a cycle.")
    parser.add_argument("--payload-min-bytes", type=int, default=96, help="Pad payload to at least this many bytes.")
    parser.add_argument("--no-allow80", action="store_true", help="Disable UDP/80 allow profile.")
    parser.add_argument("--no-allow5001", action="store_true", help="Disable UDP/5001 allow/file-marker profile.")
    parser.add_argument("--no-drop5002", action="store_true", help="Disable UDP/5002 drop profile.")
    parser.add_argument("--no-block80", action="store_true", help="Disable content-block override profile.")
    parser.add_argument("--verbose-each", action="store_true", help="Print one line per packet.")
    parser.add_argument("--print-setup", action="store_true", help="Print the PC1 setup commands and exit.")
    args = parser.parse_args()

    if args.rate <= 0:
        parser.error("--rate must be greater than 0")
    if args.src_port < 1 or args.src_port > 65535:
        parser.error("--src-port must be 1..65535")
    if args.payload_min_bytes < 0:
        parser.error("--payload-min-bytes must be zero or greater")

    enabled = []
    for profile in PROFILES:
        name = profile[0]
        if name == "allow80" and args.no_allow80:
            continue
        if name == "allow5001" and args.no_allow5001:
            continue
        if name == "drop5002" and args.no_drop5002:
            continue
        if name == "block80" and args.no_block80:
            continue
        enabled.append(profile)
    if not enabled:
        parser.error("all profiles are disabled")

    setup = [
        f"sudo ifconfig {args.iface} inet {args.src_ip} netmask 255.255.255.0 up",
        f"sudo arp -d {args.dst_ip} 2>/dev/null || true",
        f"sudo arp -s {args.dst_ip} {args.w5500_mac}",
        f"sudo tcpdump -i {args.iface} -nn -e 'host {args.dst_ip} and udp'",
    ]
    if args.print_setup:
        print("\n".join(setup))
        return

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.src_ip, args.src_port))

    interval = 1.0 / args.rate
    sent = {name: 0 for name, _port, _marker in PROFILES}

    print("FPGA UDP policy gateway sender")
    print(f"iface={args.iface} src={args.src_ip}:{args.src_port} dst={args.dst_ip}")
    print("profiles: " + ", ".join(f"{name}/udp{port}" for name, port, _marker in enabled))
    print(f"static ARP required: {args.dst_ip} -> {args.w5500_mac}")
    print("Setup commands:")
    for cmd in setup:
        print(f"  {cmd}")
    print("Stop with Ctrl+C.")

    try:
        seq_iter = range(args.count) if args.count > 0 else itertools.count()
        for seq in seq_iter:
            cycle_start = time.time()
            for profile in enabled:
                name, port, _marker = profile
                payload = build_payload(profile, seq, args.payload_min_bytes)
                sock.sendto(payload, (args.dst_ip, port))
                sent[name] += 1
                msg = " ".join(f"{key}={value}" for key, value in sent.items())
                if args.verbose_each:
                    print(f"seq={seq} sent {name} udp/{port} bytes={len(payload)} {msg}", flush=True)
                else:
                    print(f"\rseq={seq} {msg}", end="", flush=True)
                time.sleep(args.packet_gap)

            sleep_left = interval - (time.time() - cycle_start)
            if sleep_left > 0:
                time.sleep(sleep_left)
        print("\ndone: " + " ".join(f"{key}={value}" for key, value in sent.items()))
    except KeyboardInterrupt:
        print("\nstopped: " + " ".join(f"{key}={value}" for key, value in sent.items()))


if __name__ == "__main__":
    main()
