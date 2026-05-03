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
    "stp_b_tx_first16[127..0]",
    "stp_rx_ctrl[4..0]",
    "stp_rx_data[7..0]",
    "stp_tx_b_ctrl[4..0]",
    "stp_tx_b_data[7..0]",
    "stp_spi_b[3..0]",
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
    last = rows[-1]
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
    b_first16 = last.get("stp_b_tx_first16[127..0]", "")
    if a_first16 and b_first16:
        print("\nFrame-header check:")
        print(f"  A RX first16 = {a_first16}")
        print(f"  B TX first16 = {b_first16}")
        print(f"  match        = {a_first16 == b_first16}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
