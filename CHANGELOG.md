# CHANGELOG

## 2026-05-06
- Reworked `scripts/file_receiver.py` into a visual PC2 browser dashboard on port `8092` while preserving terminal-only mode via `--no-dashboard`.
  - Shows chunk progress, chunk-map buckets, missing chunk preview, duplicate count, leak count, expected/actual SHA-256, output path, and recent events.
  - Serves the reconstructed file at `/file` after completion and previews image/video/audio/text files in the browser when supported.
- Reworked `scripts/sine_receiver_dashboard.py` so the sine display uses timestamped sample dots on a rolling wall-clock axis instead of plotting samples by array index.
  - Sample timestamps are reconstructed from packet sequence, sample rate, and samples per packet.
  - Missing packets leave visible empty time intervals; resumed packets appear at their later stream time rather than being connected across the gap.
  - The packets/sec chart now uses the same wall-clock sampling model.
- Generalized `scripts/sine_sender.py` into a payload-waveform sender while keeping the existing `FWSINE2\0` marker for FPGA signature telemetry.
  - Added `--wave sine|square|triangle|saw|step|noise|values|text`.
  - Added `--values` / `--values-file` so the PC1 stream can carry arbitrary signed int16 sample sequences.
  - Kept `--sine-hz` as a compatibility alias for `--wave-hz`.
- Updated the sine dashboard wording and docs to state explicitly that PC2 plots the received payload sample values only. A square-wave packet stream now renders as a square wave, and missing/dropped packets produce real blank intervals.
- Diagnosed the file-transfer "only one chunk on PC2" capture (`filesending1chunk.pcapng`): the only forwarded chunk was `41/42`, the final short chunk. Full 512-byte file chunks produce 604-byte FPGA-internal frames (`42` synthesized Ethernet/IP/UDP bytes + `50` file-demo header + `512` data), which are discarded by any image/path still enforcing a 512-byte ingress-frame guard.
- Changed `scripts/file_sender.py` default `--chunk-size` from `512` to conservative `256` and added a warning when a selected chunk size exceeds the 512-byte synthesized-frame budget.
- Changed `scripts/file_sender.py` default pacing from `0.01 s` to hardware-safe `0.10 s` per datagram and added `--limit-chunks` for staged PC2 bring-up.
  - Recommended first probe: `--decoys 0 --limit-chunks 4 --interval 0.10`.
  - Recommended full proof: `--decoys 1 --interval 0.10`.
- Fixed the payload waveform dashboard x-axis so the live graph defaults to real packet-arrival time instead of drifting by mismatched payload sample-rate metadata.
  - One vertical waveform grid column is one wall-clock second.
  - Removed the fake green zero line when no samples are visible.
  - Changed `scripts/sine_sender.py` so the default payload sample rate is derived from `packets-per-second * samples-per-packet` (`80 Hz` for the default `5 * 16` stream).
- Python compile checks pass for `file_receiver.py`, `sine_receiver_dashboard.py`, `file_sender.py`, and `sine_sender.py`.

## 2026-05-05 - UDP Policy Gateway Pivot And FPGA Signature Demo
- Reframed the hardware demo as a W5500-based UDP packet-policy gateway instead of a transparent L2/TCP firewall. The project name can remain, but the final docs now explicitly explain that the reliable hardware path is W5500 UDP sockets plus FPGA stream processing, while A-side MACRAW is retained as diagnostic history.
- Extended W5500 A UDP ingress from one socket to three services:
  - socket 0: UDP/80 allow/demo traffic,
  - socket 1: UDP/5001 file/sine/data allow traffic,
  - socket 2: UDP/5002 intentional drop/decoy traffic.
- Added round-robin W5500 socket polling and internal Ethernet/IPv4/UDP frame synthesis so the existing parser, policy forwarder, packet-buffer, and W5500 B TX path remain the core datapath.
- Added FPGA-visible policy counters for UDP/80 allow, UDP/5001 allow, UDP/5002 drop, content-block drop, and default drop.
- Added a small streaming payload signature matcher in the forwarder:
  - `FWFILE1\0` increments file-demo telemetry,
  - `FWSINE2\0` increments sine-demo telemetry,
  - `FW-BLOCK` and `FW-DEMO-DROP` force a content-block drop even on otherwise allowed UDP ports.
- Extended UART telemetry with compact per-rule histogram fields (`U80`, `U51`, `D52`, `SIG`, `DEF`, `FIL`, `SIN`) for the dashboard.
- Reworked the canonical PC1 demo senders to use normal UDP sockets and static ARP instead of depending on raw MACRAW behavior:
  - UDP/80 allow,
  - UDP/5001 file/sine/data allow,
  - UDP/5002 drop,
  - UDP/80 or UDP/5001 with `FW-BLOCK` content-drop override.
- Updated the PC2 dashboard to show live packet flow, leak warnings, marker classification, UART rule histograms, and file/sine signature evidence.
- Updated the final bench framing and docs so the nine-round MACRAW investigation remains visible as engineering evidence while the submission path ships the reliable UDP policy engine.
- Ran the focused verification set after the pivot:
  - Python compile checks for the updated sender/dashboard/pcap scripts,
  - `parser_tb`, `rule_engine_tb`, `firewall_core_tb`, `firewall_forwarder_tb`,
  - `w5500_udp_rx_adapter_tb`, `adapter_firewall_integration_tb`,
  - `de1_soc_top_udp_socket_forward_tb`, `de1_soc_top_bypass_tb`, and `de1_soc_top_rule_regen_tb`.
- Compiled and flashed the new Quartus image. Programmer reported SOF checksum `0x085DC65F`; the final recompile removed the earlier `ck` latch-inference warning in `de1_soc_w5500_top`.
- Post-flash idle SignalTap capture `captures/stp/udp_policy_gateway_after_flash.csv` showed W5500 A socket status `0x22`, switches `001`, zero B SEND timeouts, and zero traffic counters; next capture must be run with the final PC1 UDP policy sender active.
- Documented the live UART wiring path end to end: `GPIO_0_D6` / `GPIO_0[6]` FPGA `UART_TX` to a 3.3 V TTL USB-UART adapter `RXD`, common ground, `115200 8N1`, dashboard `--uart COMx`.
- Changed and documented the rule dashboard rate graph so its x-axis is a real rolling time window instead of advancing only when allowed packets arrive.

## 2026-04-08
- Created the repository structure from the project planning document
- Added project docs, milestone flow, and helper scripts
- Added synthesizable RTL for SPI, parser, rule engine, packet buffer, controller adapter shell, firewall core, and top-level integration
- Added packet vectors and dedicated simulation testbenches
- Added a PowerShell simulation helper for local `iverilog` runs
- Added a mixed-language verification flow with shared SystemVerilog testbench utilities
- Converted the parser, rule engine, and firewall core benches to SystemVerilog
- Added an SSH-allow TCP packet vector to improve rule and integration coverage

## 2026-04-09
- Fixed remaining simulation pulse-capture issues in the rule engine and packet buffer benches
- Updated the SPI master to support multi-byte transactions with held chip-select
- Replaced the placeholder adapter with a W5500-oriented MACRAW RX path
- Added a reusable W5500 SPI/RX simulation model and adapter-to-firewall integration bench
- Added a DE1-SoC board wrapper and froze the first GPIO wiring contract in docs
- Added an XSim suite runner and a Scapy-based deterministic packet sender scaffold for physical testing

## 2026-04-16
- Added `docs/project_overview.md` as a newcomer-friendly project guide covering goals, architecture, stages, testing flow, deployment, hardware, and key files
- Updated `README.md` to reference the overview guide and give new teammates a clearer documentation entry path
- Added an RX-side frame FIFO between the Ethernet adapter and firewall core, plus a dedicated FIFO testbench and FIFO-enabled integration coverage
- Hardened the DE1-SoC top-level with synchronized reset release and synchronized board-control sampling for the live hardware path
- Removed the Quartus SPI truncation warnings and the `KEY[0]` global-clock warning from the current build flow
- Validated the updated pre-hardware flow with full XSim regression, a Questa smoke check, and a fresh Quartus compile that emits `build/quartus/de1_soc_w5500.sof`

## 2026-05-01
- Programmed the DE1-SoC over JTAG with the W5500 receive-inspection image and completed the first live hardware bring-up pass
- Increased W5500 reset/release timing for real hardware and widened the adapter wait counter so millisecond-scale reset delays work correctly
- Corrected W5500 SPI control-byte definitions so read commands use `RWB=0` and write commands use `RWB=1`
- Updated the W5500 simulation model to match the corrected SPI read/write control-byte behavior
- Increased the hardware RX frame limit to 2048 bytes for realistic Ethernet frames
- Changed malformed or oversized W5500 RX frames to be discarded/committed instead of permanently forcing `init_error`
- Restored the clean board LED contract after temporary diagnostic bring-up overlays:
  - `LEDR[0]` = `init_done`
  - `LEDR[1]` = `init_error`
  - `LEDR[2]` = `rx_packet_seen`
  - `LEDR[6:3]` = adapter state
  - `LEDR[7:9]` = RX/allow/drop counter low bits
- Confirmed PC-to-W5500 traffic with Wireshark and Scapy:
  - 3 `udp_allow` packets
  - 3 `tcp_drop` packets
  - 3 `tcp_allow_ssh` packets
- Added stream-level forwarding scaffolding with `firewall_forwarder` and a focused forwarding testbench
- Added a standalone W5500 TX engine, TX simulation model, and TX engine testbench for the next inline-forwarding phase
- Reserved the second W5500 wiring contract on `GPIO_1[0..5]` in the DE1-SoC top-level and Quartus assignment flow
- Added transmit-only UART telemetry on `GPIO_0_D6` for FPGA counter/event readback
- Added chunked file sender/receiver scripts for the final PC1-to-PC2 SHA-256 demo
- Extended the browser dashboard with a two-port file-demo preview and updated docs/TODO/decisions for the real inline-firewall roadmap
- Added README instructions for cloning the repo and running the PC1 sender / PC2 receiver setup
- Added a continuous sine-wave demo sender and PC2 browser dashboard for live allow/drop visualization
- Improved the sine demo with slower readable defaults, a packet-by-packet decision strip, expected-drop markers, leak markers, missing-sequence markers, and a live packet-rate graph
- Added a restart button to the sine receiver dashboard for clearing the live demo view without restarting the sniffer
- Changed W5500 B TX payload writes from one SPI transaction per byte to a single burst TX-buffer write per frame, improving the two-port forwarding demo throughput
- Added the same restart/reset control to the deterministic traffic dashboard

## 2026-05-03
- Added focused two-port hardware debug modes to `de1_soc_w5500_top`:
  - `SW5`: raw W5500 A ingress drain/debug mode.
  - `SW6`: direct W5500 B internally generated TX test mode.
  - `SW7`: raw A-to-B bypass debug mode.
  - `SW8`: experimental generated rule-demo mode that should emit a known-good B-side frame when A-side traffic matches allow rules.
- Added debug HEX pages for raw ingress counts, W5500 B TX count, last RX size, and last frame length.
- Confirmed by hardware observation that W5500 A ingress works in raw mode and W5500 B direct transmit works in `SW6`.
- Confirmed by capture comparison that direct PC1-to-PC2 traffic contains demo frames, while SW7/SW8 FPGA paths do not yet produce visible demo frames on PC2.
- Added and updated two-port simulation coverage:
  - `two_port_bypass_tb`
  - `de1_soc_top_bypass_tb`
  - `de1_soc_top_rule_regen_tb`
- Updated W5500 TX behavior:
  - removed false TX error on normal backpressure,
  - changed TX free-space handling to wait/retry,
  - added `S0_CR` command-clear polling after `SEND`.
- Updated W5500 simulation models:
  - added repeated RX packet support to `w5500_macraw_model`,
  - added `S0_CR` readback/clear behavior to `w5500_tx_model`.
- Updated simulation runners to include the newer TX/debug sources.
- Documented the current unresolved hardware blocker: individual A RX and B TX paths work, but A-triggered TX still fails on real hardware.
- Added `SW9` byte/state debug mode:
  - first 16 committed bytes from W5500 A RX,
  - first 16 committed bytes handed to W5500 B TX,
  - W5500 B TX progress counters and sticky progress LEDs,
  - SW8 rule-regen parser field visibility.
- Widened W5500 B TX adapter debug state to 5 bits so state `16` no longer aliases to idle on debug outputs.
- Added `docs/signaltap_debug.md` with a practical SignalTap II setup guide for the A-triggered TX hardware blocker.
- Added preserved `stp_*` SignalTap probe registers and a SignalTap-enabled compile/program flow.
- Captured first useful SW7 SignalTap evidence: A-triggered B TX writes one 0x4E-byte frame, issues SEND, W5500 B clears SEND, and no TX timeout occurs.
- Added command-line SignalTap capture/export support with `scripts/signaltap_capture.tcl` and CSV summarization with `scripts/inspect_signaltap_csv.py`.
- Added `scripts/pcap_summary.py` for quick Wireshark capture triage by Ethernet source/destination, ethertype, IP pair, ports, and demo markers.
- Used SignalTap plus `sw7-0004.pcapng` to narrow the SW7 bug: Mac-origin multicast frames are forwarded through A -> FPGA -> B -> PC2, while the old spoofed-source demo markers are absent.
- Changed `rule_demo_sender.py`, `sine_sender.py`, and `file_sender.py` to use PC1's real interface MAC by default; `--src-mac` is now an explicit spoofing override.

## 2026-05-04
- Added an IPv4-only RX shadow `stp_a_rx_ipv4_first16` and per-ethertype EOP frame counters (`stp_frames_ipv4`, `stp_frames_ipv6`, `stp_frames_arp`, `stp_frames_other`, `stp_frames_udp_dport80`, `stp_frames_demo_match`) to `de1_soc_w5500_top.v`, so the SignalTap rolling shadow can no longer be hidden behind background IPv6 multicast traffic.
- Updated `scripts/inspect_signaltap_csv.py` to decode the first 16 bytes into `dst/src/ethertype` rows and to print a one-line Diagnosis that selects between five concrete next actions (no-IPv4-on-wire, IPv4-but-no-demo, demo-but-no-buf-write, buf-write-but-no-SEND-clear, all-fine-look-at-PC2).
- Added `docs/next_bench_session.md` as a focused round-2 cheat sheet for reflashing, adding the new probes to the existing `.stp`, capturing, and interpreting the diagnosis.
- Re-ran Questa regression on `two_port_bypass_tb`, `de1_soc_top_bypass_tb`, and `de1_soc_top_rule_regen_tb` after the new probes/counters were added; all pass. Quartus full compile succeeds at 67% ALM utilization.
- Reflashed the round-2 SOF (checksum `0x07AAAEF6`) and ran round-2 SignalTap capture. The capture proves the FPGA pipeline forwards IPv4 multicast end-to-end: A RX, parser, forwarder, packet_buffer, B TX adapter, W5500 B all show 3-of-3 forwarded frames with `dst=01:00:5E:00:00:FB src=1C:F6:4C:44:FF:46 ethertype=0800` and zero errors. Forwarded frames are mDNS (UDP/5353) from the Mac's `mDNSResponder`, not the rule_demo_sender's UDP/80. Conclusion: the FPGA bug is closed; the residual problem is PC1-side delivery of the demo UDP/80 frames.
- Added `scripts/signaltap_capture_force.tcl` (force-trigger variant) and `scripts/make_anytrig_stp.py` (relax all `level-0` triggers to `dont_care`) so CLI captures still produce a CSV when the configured trigger doesn't fire on hardware.
- Fixed `scripts/inspect_signaltap_csv.py` to use the most recent non-`X` value per column instead of the literal last row, so trailing-X padded SignalTap exports report the correct counters.
- Defaulted `scripts/rule_demo_sender.py` to broadcast (`ff:ff:ff:ff:ff:ff`, dst IP `192.168.1.255`) to bypass macOS multicast routing peculiarities. The original multicast IP/MAC remain available via `--dst-mac` and the script still defaults to UDP/80.

## 2026-05-04 (round 4: chip-state hardening)
- `rtl/eth_if/ethernet_controller_adapter.v`:
  - Added `SHAR` (Source Hardware Address Register) write to `02:00:00:DE:AD:0A` during init. Some W5500 firmware revisions need a non-zero SHAR for reliable MAC-layer RX even with `MFEN=0`.
  - New state `ST_WAIT_RECV` polls `S0_CR` until the chip clears it after each `RECV` command. Per W5500 datasheet, accessing the chip while a command is in flight gives undefined results, which can stall RX.
- `rtl/eth_if/w5500_macraw_tx_adapter.v`: mirrored `SHAR` write to `02:00:00:DE:AD:0B` for symmetry.
- Hardware result: counters still frozen at the same `3 IPv4 / 2 IPv6 / 0 demo` pattern. SHAR + RECV-clear did not move the needle. Captures preserved in `captures/stp/round4_*.csv`.

## 2026-05-04 (round 5: interrupt-clear hardening)
- Extended `ST_WAIT_RECV` in `ethernet_controller_adapter.v` to also write `S0_IR=0xFF` after `RECV` clears, clearing every pending socket interrupt bit (RECV, CON, DISCON, etc.) per WIZnet's recommended sequence.
- Hardware result: still no change. The Sn_IR-pending hypothesis was wrong.

## 2026-05-04 (round 6: visibility expansion)
- Added SignalTap probes `stp_last_rx_size`, `stp_last_frame_len`, `stp_rx_commit_count`, `stp_rx_stream_byte_count` to distinguish chip-side from adapter-side RX failures.

## 2026-05-04 (round 7: PHY visibility)
- `rtl/eth_if/ethernet_controller_adapter.v`: added new state `ST_READ_PHY` and outputs `phy_cfgr_value` + `phy_read_count`. Reads `PHYCFGR` (common 0x002E) once at init and re-reads after every successful frame commit. Exposes link, speed, duplex bits.
- Top-level: added `stp_phy_cfgr` and `stp_phy_read_count` SignalTap probes.
- Hardware result: `stp_phy_cfgr = 0xBF` -> LNK=1, SPD=1 (100M), DPX=1 (full). The W5500 PHY is fully linked in 100M FDX. PHY layer is *not* the issue.
- Same capture revealed `rx_commit_count = 159` while `frames_ipv4 + frames_ipv6 = 2` and `rx_stream_byte_count = 199`. 157 of 159 commits were "bad-length" discards. `last_frame_len = 0x3333` matches the first two bytes of an IPv6-multicast destination MAC, suggesting our adapter occasionally read frame data as if it were a length prefix -> alignment was getting flushed by the discard logic.

## 2026-05-05 (round 8: bounded discard)
- `rtl/eth_if/ethernet_controller_adapter.v`: replaced the "flush entire RX buffer on bad length" path with a bounded `rx_read_ptr + min(rx_size_bytes, 1520)` advance. A single corrupted length header now costs at most one Ethernet frame's worth of buffer, instead of throwing away every valid frame queued behind it. Demo UDP/80 frames buffered behind a single noisy mDNS frame should now survive the discard recovery.
- Bench protocol updated: after every reflash, **wait at least 30 seconds** before triggering SignalTap. The Mac's `mDNSResponder` floods Bonjour announces every time it sees a link-up event; that flood is what produces ~150 discarded frames in the first few seconds and obscures the real demo traffic.

## 2026-05-05 (rounds 9-13: MACRAW filter/drain matrix)
- Tested bounded-discard plus `MFEN=1` (`S0_MR=0x84`) and confirmed the W5500 A PHY stayed healthy (`PHYCFGR=0xBF`) while UDP/80 still did not appear.
- Raised W5500 A SPI drain rate from divider 50 to 8, then 4, and added repeated-bad-length resync. Captures still showed PC1-origin IPv4 mDNS/Bonjour frames, not the demo UDP/80 flow.
- Added last-IPv4 parser-field SignalTap latches so `stp_regen_ethertype/ip_proto/dst_port` can show the last parsed IPv4 frame even when later IPv6 traffic overwrites the rolling shadow.
- Reverted MFEN for a control image and confirmed MACRAW still forwarded background IPv4 but not the verified demo UDP/80 packet.

## 2026-05-05 (rounds 14-16: sender-shape and normal-socket proof)
- Added `--allow-dst-ip` / `--dst-ip` to `scripts/rule_demo_sender.py` and fixed its stale `--dst-mac` help text.
- Added `scripts/rule_demo_udp_socket_sender.py`, a normal UDP socket sender that relies on a static ARP entry for `192.168.1.1 -> 02:00:00:de:ad:0a`.
- PC1 tcpdump proved the normal socket sender put `1c:f6:4c:44:ff:46 > 02:00:00:de:ad:0a`, IPv4, `192.168.1.10:4660 > 192.168.1.1:80` on `en0`, 10/10 packets with zero kernel drops.
- Hardware still showed `frames_udp_dport80=0`; W5500 A continued receiving broadcast/multicast Mac background frames but not the verified unicast UDP/80 packet.

## 2026-05-05 (rounds 17-19: W5500 A readbacks and pivot)
- Added non-invasive W5500 A readback probes for `S0_MR`, `SHAR`, and `SIPR`, packed into existing SignalTap columns:
  - `stp_b_status` = A `S0_MR`
  - `stp_b_last_pkt_len` + `stp_b_buf_writes` = A `SHAR`
  - `stp_b_send_issued` = A `SIPR`
- Verified hardware readbacks:
  - round 17: `S0_MR=0x04`, `SHAR=02:00:00:DE:AD:0A`
  - round 18: `S0_MR=0x84`, `SHAR=02:00:00:DE:AD:0A`
  - round 19: `S0_MR=0x84`, `SHAR=02:00:00:DE:AD:0A`, `SIPR=192.168.1.1`
- Programmed W5500 A common network registers for the unicast test (`GAR=192.168.1.10`, `SUBR=255.255.255.0`, `SIPR=192.168.1.1`) and confirmed readback.
- Final round-19 capture still reported `frames_udp_dport80=0` with PC1 tcpdump clean. Decision: stop chasing A-side MACRAW for the demo path and pivot to W5500 A normal UDP socket receive mode.

## 2026-05-05 (UDP socket ingress implementation checkpoint)
- Added `rtl/eth_if/w5500_udp_rx_adapter.v`, which configures W5500 A as a normal UDP socket on port 80, reads the W5500 UDP RX record, and synthesizes an internal Ethernet/IPv4/UDP byte stream for the existing parser/forwarder/B-TX path.
- Added `tb/models/w5500_udp_rx_model.sv`, `tb/tests/w5500_udp_rx_adapter_tb.sv`, and `tb/tests/de1_soc_top_udp_socket_forward_tb.sv` to cover the socket RX adapter and the normal top-level A-to-B forwarding path.
- Switched `de1_soc_w5500_top` A ingress from the MACRAW adapter to the UDP socket adapter, while restoring SignalTap's B-side TX counter packing for the next hardware acceptance capture.
- Updated simulator and Quartus source lists for the new UDP RX RTL/model. Follow-up Questa runs passed before hardware compilation.

## 2026-05-05 (round 22: UDP socket ingress hardware success)
- Added periodic W5500 A PHY/socket-status refresh and delayed UDP socket open until `PHYCFGR.LNK=1`.
- Recompiled and flashed SOF checksum `0x0850DD25`.
- Round-22 SignalTap force capture `captures/stp/round22_udp_waitlink.csv` showed:
  - `stp_b_status=0x22` (W5500 A socket 0 open in UDP mode)
  - `stp_phy_cfgr=0xBF` (100M full-duplex link)
  - `frames_ipv4=frames_udp_dport80=frames_demo_match=0x74`
  - `b_buf_writes=b_send_issued=b_send_cleared=b_tx_count=0x74`
  - `b_send_timeouts=0`
  - A RX and B TX first 16 bytes both `FFFFFFFFFFFF00112233445508004500`
- This proves the PC1-triggered UDP/80 demo path reaches W5500 A UDP RX, is reconstructed internally, matches the firewall rule, and completes W5500 B SENDs with no timeouts. Remaining validation is PC2 Wireshark/dashboard visibility.
