#!/usr/bin/env python3
"""Print a compact summary of a SignalTap CSV export."""

from __future__ import annotations

import csv
import sys
from pathlib import Path


INTERESTING = (
    "stp_switches",
    "stp_adapter_b_state",
    "stp_b_buf_writes",
    "stp_b_send_issued",
    "stp_b_send_cleared",
    "stp_b_send_timeouts",
    "stp_b_tx_count",
    "stp_b_last_pkt_len",
    "stp_b_status",
    "stp_tx_b_ctrl",
    "stp_tx_b_data",
    "stp_rx_ctrl",
    "stp_rx_data",
    "stp_spi_b",
    "stp_b_tx_first16",
    "stp_a_rx_first16",
    "stp_a_rx_ipv4_first16",
    "stp_regen_ethertype",
    "stp_regen_ip_proto",
    "stp_regen_dst_port",
    "stp_frames_ipv4",
    "stp_frames_ipv6",
    "stp_frames_arp",
    "stp_frames_other",
    "stp_frames_udp_dport80",
    "stp_frames_demo_match",
)

SUMMARY_SIGNALS = (
    "stp_switches[9..0]",
    "stp_adapter_b_state[4..0]",
    "stp_b_buf_writes[31..0]",
    "stp_b_send_issued[31..0]",
    "stp_b_send_cleared[31..0]",
    "stp_b_send_timeouts[31..0]",
    "stp_b_tx_count[31..0]",
    "stp_b_last_pkt_len[15..0]",
    "stp_b_status[7..0]",
    "stp_a_rx_first16[127..0]",
    "stp_a_rx_ipv4_first16[127..0]",
    "stp_b_tx_first16[127..0]",
    "stp_rx_ctrl[4..0]",
    "stp_rx_data[7..0]",
    "stp_tx_b_ctrl[4..0]",
    "stp_tx_b_data[7..0]",
    "stp_spi_b[3..0]",
    "stp_regen_ethertype[15..0]",
    "stp_regen_ip_proto[7..0]",
    "stp_regen_dst_port[15..0]",
    "stp_frames_ipv4[31..0]",
    "stp_frames_ipv6[31..0]",
    "stp_frames_arp[31..0]",
    "stp_frames_other[31..0]",
    "stp_frames_udp_dport80[31..0]",
    "stp_frames_demo_match[31..0]",
)


def read_rows(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8-sig") as f:
        lines = f.readlines()

    data_idx = 0
    for idx, line in enumerate(lines):
        if line.strip() == "Data:":
            data_idx = idx + 1
            break

    if data_idx >= len(lines):
        return [], []

    data_text = "".join(lines[data_idx:])
    reader = csv.reader(data_text.splitlines())
    try:
        raw_fields = next(reader)
    except StopIteration:
        return [], []

    fields: list[str] = []
    seen: dict[str, int] = {}
    for idx, field in enumerate(raw_fields):
        name = field.strip()
        if not name:
            name = f"unnamed_{idx}"
        if name in seen:
            seen[name] += 1
            name = f"{name}#{seen[name]}"
        else:
            seen[name] = 0
        fields.append(name)

    rows = []
    for values in reader:
        if not values or all(not value.strip() for value in values):
            continue
        if len(values) < len(fields):
            values = values + [""] * (len(fields) - len(values))
        rows.append({field: values[idx].strip() if idx < len(values) else "" for idx, field in enumerate(fields)})
    return fields, rows


def _last_nonx_per_field(rows: list[dict[str, str]], fields: list[str]) -> dict[str, str]:
    """Build a synthetic row that contains, for each field, the most recent non-X value.

    SignalTap CSV exports often have leading and trailing rows where signals
    show as ``X`` (uninitialized / outside the valid sample window). The literal
    last row is therefore not a reliable source of "current state". We scan
    each column independently and take the last value that doesn't contain X.
    """
    snapshot: dict[str, str] = {}
    for field in fields:
        for row in reversed(rows):
            v = row.get(field, "").strip()
            if v and "X" not in v.upper():
                snapshot[field] = v
                break
        else:
            snapshot[field] = rows[-1].get(field, "")
    return snapshot


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: inspect_signaltap_csv.py <capture.csv>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    fields, rows = read_rows(path)
    if not rows:
        print(f"{path}: no rows")
        return 1

    print(f"{path}")
    print(f"rows: {len(rows)}")
    print(f"columns: {len(fields)}")

    matching = [field for field in SUMMARY_SIGNALS if field in fields]
    if not matching:
        matching = [field for field in fields if any(name in field for name in INTERESTING)]
    if not matching:
        print("No known stp_* columns found. First columns:")
        for field in fields[:20]:
            print(f"  {field}")
        return 0

    first = rows[0]
    last_literal = rows[-1]
    last = _last_nonx_per_field(rows, fields)
    changed = []

    print("\nSignal summary:")
    for field in matching:
        values = [row.get(field, "") for row in rows]
        unique = []
        for value in values:
            if value not in unique:
                unique.append(value)
            if len(unique) > 6:
                break
        if first.get(field) != last.get(field):
            changed.append(field)
        print(f"  {field}: first={first.get(field, '')} last={last.get(field, '')} unique={unique[:8]}")

    print("\nTransitions:")
    for field in matching:
        last_value = None
        transitions = []
        for row in rows:
            value = row.get(field, "")
            if value != last_value:
                transitions.append((row.get("time unit: ns", ""), value))
                last_value = value
            if len(transitions) > 10:
                break
        print(f"  {field}:")
        for time_ns, value in transitions[:10]:
            print(f"    t={time_ns} ns -> {value}")
        if len(transitions) > 10:
            print("    ...")

    a_first16 = last.get("stp_a_rx_first16[127..0]", "")
    a_ipv4_first16 = last.get("stp_a_rx_ipv4_first16[127..0]", "")
    b_first16 = last.get("stp_b_tx_first16[127..0]", "")
    if a_first16 and b_first16:
        print("\nFrame-header check:")
        print(f"  A RX last EOP first16    = {a_first16}")
        if a_ipv4_first16:
            print(f"  A RX last IPv4 first16   = {a_ipv4_first16}")
        print(f"  B TX last EOP first16    = {b_first16}")
        print(f"  A_last == B_last         = {a_first16 == b_first16}")
        if a_ipv4_first16:
            print(f"  A_ipv4_last == B_last    = {a_ipv4_first16 == b_first16}")
        print()
        decode_eth(a_first16, "A RX last EOP")
        if a_ipv4_first16 and any(c != "0" for c in a_ipv4_first16) and a_ipv4_first16.upper() != "X" * len(a_ipv4_first16):
            decode_eth(a_ipv4_first16, "A RX last IPv4")
        if b_first16:
            decode_eth(b_first16, "B TX last EOP")

    print_diagnosis(last)
    return 0


def decode_eth(hex_bytes: str, label: str) -> None:
    """Pretty-print the first 16 Ethernet bytes from a packed hex string."""
    if not hex_bytes or hex_bytes.upper() == "X" * len(hex_bytes):
        print(f"  {label}: <no data>")
        return
    if len(hex_bytes) < 32:
        print(f"  {label}: short ({len(hex_bytes)} hex chars)")
        return
    bytes_list = [hex_bytes[i:i+2] for i in range(0, 32, 2)]
    dst_mac = ":".join(bytes_list[0:6])
    src_mac = ":".join(bytes_list[6:12])
    ethertype = bytes_list[12] + bytes_list[13]
    extra = " ".join(bytes_list[14:16])
    et_label = {
        "0800": "IPv4",
        "86DD": "IPv6",
        "0806": "ARP",
        "8100": "VLAN",
    }.get(ethertype.upper(), "?")
    print(f"  {label}: dst={dst_mac} src={src_mac} ethertype={ethertype} ({et_label}) next={extra}")


def print_diagnosis(last: dict[str, str]) -> None:
    print("\nDiagnosis:")
    counters = {
        "IPv4 frames":            "stp_frames_ipv4[31..0]",
        "IPv6 frames":            "stp_frames_ipv6[31..0]",
        "ARP frames":             "stp_frames_arp[31..0]",
        "Other frames":           "stp_frames_other[31..0]",
        "IPv4 UDP dst=80 frames": "stp_frames_udp_dport80[31..0]",
        "Demo-match frames":      "stp_frames_demo_match[31..0]",
        "B TX count":             "stp_b_tx_count[31..0]",
        "B buf-writes":           "stp_b_buf_writes[31..0]",
        "B SEND issued":          "stp_b_send_issued[31..0]",
        "B SEND cleared":         "stp_b_send_cleared[31..0]",
        "B SEND timeouts":        "stp_b_send_timeouts[31..0]",
    }
    values: dict[str, int] = {}
    for label, key in counters.items():
        raw = last.get(key, "")
        try:
            values[label] = int(raw, 16) if raw and raw.upper() != "X" * len(raw) else None
        except ValueError:
            values[label] = None
        display = f"0x{values[label]:08X} ({values[label]})" if values[label] is not None else "<unknown>"
        print(f"  {label:<24} = {display}")

    print()
    ipv4 = values.get("IPv4 frames")
    ipv6 = values.get("IPv6 frames")
    demo = values.get("Demo-match frames")
    btx = values.get("B TX count")
    btw = values.get("B buf-writes")
    if ipv4 == 0 and ipv6 and ipv6 > 0:
        print("  CONCLUSION: A is receiving IPv6 only. PC1 demo IPv4 frames are not reaching the W5500.")
        print("  Action: tcpdump on PC1 iface; confirm Mac is sending the demo frame and binding the right NIC.")
    elif ipv4 and ipv4 > 0 and demo == 0:
        print("  CONCLUSION: IPv4 frames are reaching A, but NONE match the demo profile (UDP dst=80).")
        print("  Action: check sender script's dst port/proto; check W5500 isn't truncating header bytes.")
    elif demo and demo > 0 and btw == 0:
        print("  CONCLUSION: demo IPv4/UDP-dst-80 frames seen at A, but B never started a TX-buffer write.")
        print("  Action: the gap is fifo / forwarder / packet_buffer. Trigger SignalTap on tx_to_b_valid edge.")
    elif btw and btw > 0 and btx == 0:
        print("  CONCLUSION: B started a TX-buffer write but never completed SEND.")
        print("  Action: trigger SignalTap on adapter_b_debug_state==SEND/WAIT_SEND; check S0_CR clear.")
    elif btx and btx > 0:
        print("  CONCLUSION: B has completed SENDs. If PC2 still sees nothing, suspect Wireshark filter,")
        print("  PC2 NIC IPv4 multicast filter (224.0.0.251 needs IGMP membership), or W5500-B PHY/cable.")
    else:
        print("  No clear conclusion from the counters alone. Re-run capture with traffic active.")


if __name__ == "__main__":
    raise SystemExit(main())
