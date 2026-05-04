#!/usr/bin/env python3
"""Copy a Quartus SignalTap .stp file and relax all trigger level conditions to dont_care.

Useful for CLI captures when you don't care WHICH event fires the trigger; you
just want any sample buffered into the data window so the new counters are visible.

Usage:
  python3 scripts/make_anytrig_stp.py <input.stp> <output.stp>
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: make_anytrig_stp.py <input.stp> <output.stp>", file=sys.stderr)
        return 2

    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    raw = src.read_bytes()
    text = raw.decode("utf-8", errors="strict")

    new_text = re.sub(r'level-0="(low|high|rising_edge|falling_edge|edge|0|1)"',
                      'level-0="dont_care"', text)

    # SignalTap requires at least one non-dont_care trigger condition or it
    # never fires. Force a single bit (SW[0]) to "high" because SW[0]=1 during
    # normal operation. That makes the trigger essentially "any sample after init".
    pinned = re.subn(
        r'(<node\b[^>]*name="stp_switches\[0\]"[^>]*?level-0=)"dont_care"',
        r'\1"high"',
        new_text,
        count=1,
    )
    new_text, n_pinned = pinned

    changes = sum(1 for _ in re.finditer(r'level-0="(low|high|rising_edge|falling_edge|edge|0|1)"', text))
    dst.write_bytes(new_text.encode("utf-8"))
    print(f"copied {src} -> {dst}, replaced {changes} non-dont_care trigger levels; pinned stp_switches[0]=high ({n_pinned} match)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
