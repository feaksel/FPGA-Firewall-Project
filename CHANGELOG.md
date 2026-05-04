# CHANGELOG

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
