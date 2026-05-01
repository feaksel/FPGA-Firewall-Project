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
