# Next Bench Session — Cheat Sheet (2026-05-05)

This is the working state after eight diagnostic rounds. The remaining open
question on the FPGA side is whether the new bounded-discard adapter
(`rtl/eth_if/ethernet_controller_adapter.v`) lets demo UDP/80 frames survive
the Mac's `mDNSResponder` link-up flood.

## What we know for sure

| Layer | Status |
| --- | --- |
| PC1 (Mac) Scapy sender | OK. `tcpdump -i en0 udp port 80` confirmed five demo broadcasts leaving en0 with `src=1c:f6:4c:44:ff:46`, `dst=ff:ff:ff:ff:ff:ff`, `dport=80`. |
| Cable PC1 -> W5500 A | OK. Direct point-to-point, no switch. |
| W5500 A PHY | OK. `stp_phy_cfgr = 0xBF` -> LNK=1, SPD=1 (100M), DPX=1 (full). |
| W5500 A MAC | Receives mDNS multicast frames cleanly (we see them streamed). |
| FPGA RX FIFO + parser | OK. Every IPv4/UDP frame counted in `frames_ipv4` / `frames_udp_dport80`. |
| FPGA forwarder + packet_buffer | OK. Forwards allowed frames to W5500 B. |
| W5500 B TX adapter | OK. `b_buf_writes / send_issued / send_cleared / tx_count` all increment for forwarded frames; no timeouts. |
| W5500 B PHY -> PC2 | OK. Wireshark on PC2 has shown forwarded mDNS multicast arriving end-to-end. |
| Cable W5500 B -> PC2 | OK. Direct point-to-point. |

## What we don't know yet

- Whether **demo UDP/80** frames specifically survive the chip's RX buffer.
  In every round so far, only the Mac's mDNS background ended up in
  `frames_ipv4` (with `regen_dst_port = 0x14E9 = 5353`). UDP/80 was always 0.
- Whether the round-8 RTL fix (bounded discard) lets demo frames buffered
  behind a single corrupted-length mDNS frame survive long enough to be
  parsed and forwarded.

## Bench protocol (do exactly this)

1. Pull the latest repo on PC1 (the sender script default is now
   broadcast / dst IP `192.168.1.255`).
2. Confirm topology:
   ```
   PC1 (Mac, en0) ---direct cable--- W5500 A (FPGA)
   W5500 B (FPGA) ---direct cable--- PC2 (Win NIC)
   ```
   No switches, hubs, or other devices on either link.
3. Flash the latest SOF (I'll do this after each Quartus compile finishes).
4. Press FPGA reset (`KEY[0]`); wait for `LEDR0=1` and `LEDR1=0`.
5. **Wait at least 30 seconds**. The Mac's `mDNSResponder` floods Bonjour
   announces every time it sees a link-up event, and that flood is the source
   of the ~150 "bad-length discard" cycles we kept seeing in earlier captures.
6. Start the sender on PC1:
   ```bash
   sudo python3 scripts/rule_demo_sender.py --iface en0 --rate 2 \
       --packet-gap 0.05 --no-ssh-allow --no-tcp-drop --verbose-each
   ```
   It should print `dst_mac=ff:ff:ff:ff:ff:ff` and `Cycle: UDP/80 allow`.
7. (Optional sanity check) `sudo tcpdump -i en0 -nn -e -c 5 udp port 80` to
   verify frames are leaving en0.
8. Tell me to capture. I'll run:
   ```powershell
   quartus_stp.exe -t scripts/signaltap_capture.tcl `
       quartus/de1_soc_w5500.stp `
       captures/stp/round<N>.csv 30
   py -3 scripts/inspect_signaltap_csv.py captures/stp/round<N>.csv
   ```
9. Paste the bottom Diagnosis block back. I'll act on it.

## What to look for in the next capture

- `frames_ipv4` should be **moderate** (not 159). With direct cable + 30 s
  settle time, expect maybe 5-30 over a 30 s window (Mac's residual mDNS).
- `frames_udp_dport80 > 0` and `frames_demo_match > 0` — the round-8
  bounded-discard should let these accumulate at ~2 per second.
- `b_tx_count > 0` and equal to `frames_demo_match` (plus whatever mDNS got
  forwarded). Means PC2 is receiving the demo via FPGA.
- `stp_b_tx_first16` should start with `FFFFFFFFFFFF` (broadcast dst MAC) and
  ethertype `0800` (IPv4) — proof the demo frame survived end-to-end.

## If the demo still doesn't show up after round 8

Two remaining hypotheses:

1. **The Mac's `mDNSResponder` flood is so heavy that the chip's 16 KB
   RX buffer fills up faster than our SPI drain rate (~166 frames/sec at
   `SPI_CLK_DIV=50`). Demo frames get dropped at the chip's MAC level when
   the RX buffer is full.** Mitigation: bump SPI clock by lowering
   `SPI_CLK_DIV` from 50 to e.g. 8 (faster drain), or temporarily disable
   mDNSResponder on the Mac:
   ```bash
   sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.mDNSResponder.plist
   ```
   (re-enable with `launchctl load`).

2. **The W5500's MAC silently filters broadcast frames in some chip-state
   we can't see from PHYCFGR alone.** Mitigation: try `MFEN=1` in `S0_MR`
   (so the chip explicitly accepts broadcast / matches SHAR), or write a
   non-zero `Sn_IMR` to ensure interrupt handling is enabled.

I'd try mitigation #1 (lower `SPI_CLK_DIV`) first — it's a one-line RTL change.

## Reference — what each round added

| Round | RTL change | Hardware result |
| --- | --- | --- |
| 1 | Initial SW9 byte-debug + IPv4-only shadow + per-ethertype counters | Showed only IPv6 mDNS in shadow |
| 2 | Sender switched to broadcast (no RTL change) | tcpdump confirmed sender works |
| 3 | First round-2 SignalTap with IPv4-only shadow + frame counters | Confirmed FPGA forwards IPv4 mDNS end-to-end; no UDP/80 |
| 4 | SHAR write at init + S0_CR clear poll after RECV | No counter change |
| 5 | S0_IR clear after RECV | No counter change |
| 6 | New probes for chip RSR / commit / stream byte count | No SOF change yet |
| 7 | PHYCFGR read + `stp_phy_cfgr` probe | Proved PHY at 100M FDX; revealed 159 commits vs 2 streamed -> bad-length discards eating the buffer |
| 8 | Bounded discard (`min(rx_size_bytes, 1520)`) | **Pending hardware verification** |
