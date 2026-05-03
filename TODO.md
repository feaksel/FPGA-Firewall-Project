# TODO

## Current Milestone
- [x] M1: Packet source simulation infrastructure
- [x] M2: Parser implementation
- [x] M3: Rule engine implementation
- [x] M4: Firewall core integration
- [x] M5: SPI master implementation
- [x] M6: Ethernet controller adapter shell
- [x] M7: One-port hardware bring-up
- [ ] M8: Real one-way inline forwarding
- [ ] M9: File/video transfer demo with telemetry dashboard

Current status note, 2026-05-03:
- M8 is blocked. `SW6` proves W5500 B can transmit a known FPGA-generated frame to PC2, and `SW5` proves W5500 A can receive PC1 traffic. However, A-triggered transmission is not yet working on real hardware:
  - `SW7` raw A-to-B bypass: TX count can rise, but PC2 sees no demo frames.
  - `SW8` generated rule-demo mode: latest hardware report shows `SW[3:1]=101` stuck at `0000`, so the generated TX trigger is not firing.
- The next milestone is hardware diagnostics, not more demo features.

## Immediate Tasks
- [x] Finalize `docs/interfaces.md`
- [x] Add packet memory vectors to `tb/packets/`
- [x] Make `parser_tb` pass with IPv4 TCP and UDP packets
- [x] Make `rule_engine_tb` pass
- [x] Make `packet_buffer_tb` pass
- [x] Make `spi_master_tb` pass
- [x] Integrate parser + rules into `firewall_core_tb`
- [x] Freeze the Ethernet controller choice for the adapter implementation
- [x] Add adapter-level integration coverage with `adapter_firewall_integration_tb`
- [x] Freeze the Quartus project and pin assignment flow around `de1_soc_w5500_top`
- [x] Prepare the first minimal DE1-SoC hardware image and bring-up checklist
- [x] Add and verify the RX FIFO hardening path between adapter and firewall core
- [x] Use the PC-side Scapy helper during physical test once the first RX path is alive
- [x] Confirm W5500 `VERSIONR` register access on the physical module
- [x] Confirm W5500 MACRAW initialization reaches RX polling on hardware
- [x] Confirm deterministic PC packets appear in Wireshark while the FPGA receive path is running
- [x] Add cleaner hardware-visible per-profile allow/drop validation beyond single-bit LED counters
- [x] Add a repeatable hardware smoke-test note or script for board programming plus packet send/capture checks
- [x] Re-run the full simulation suite after the W5500 SPI control-byte correction
- [x] Add a visual PC-side browser dashboard for deterministic traffic tests
- [x] Add dashboard user-manual reference for HEX pages, switches, and test flow
- [x] Make dashboard manual toggleable and add a compact packet-flow visualization
- [ ] Validate the new HEX debug pages on the physical board with `udp_allow`, `tcp_drop`, and `tcp_allow_ssh`
- [x] Add the first stream-level forwarding wrapper for allow/drop forwarding tests
- [x] Reserve the second W5500 logical wiring on `GPIO_1[0..5]`
- [x] Add a standalone W5500 TX engine and simulation model for TX-buffer/SEND coverage
- [x] Add a transmit-only UART telemetry module on `GPIO_0_D6`
- [x] Add PC-side chunked file sender/receiver scripts for the final demo concept
- [x] Add continuous sine-wave sender and PC2 browser receiver dashboard
- [x] Extend the dashboard with a two-port file-demo preview panel
- [ ] Make `firewall_forwarder_tb` pass reliably under XSim
- [ ] Make `w5500_tx_engine_tb` pass under XSim
- [x] Integrate W5500 A RX -> rules -> W5500 B TX in a single hardware top
- [x] Replace W5500 B byte-at-a-time TX payload writes with burst TX-buffer writes
- [ ] Use PC2 receiver/Wireshark plus board HEX pages as the first no-UART two-port telemetry path
- [ ] Add a PC/dashboard UART reader later as an optional live FPGA counter source
- [ ] Validate W5500 B alone on hardware: reset, `VERSIONR`, MACRAW init
- [ ] Prove a fixed test frame transmitted from FPGA to PC2
- [ ] Prove one allowed PC1-to-PC2 forwarded packet and one dropped packet
- [ ] Run the final file/video transfer and verify PC2 SHA-256 match

## Current Debug Tasks

- [ ] Add HEX-visible first-byte diagnostics for W5500 A RX:
  - received frame byte 0..3 should usually be `FF FF FF FF` for the current broadcast demo frames.
  - received frame bytes 6..11 should include source MAC `00:11:22:33:44:55` for the Scapy sender.
- [ ] Add HEX-visible first-byte diagnostics for the frame submitted to W5500 B TX.
- [ ] Add a TX-completion/error page that distinguishes:
  - frame accepted by TX adapter,
  - TX buffer write started,
  - TX buffer write completed,
  - `S0_TX_WR` updated,
  - `SEND` command written,
  - `S0_CR` cleared.
- [ ] Re-test `SW6` after every TX adapter edit as the known-good B-side baseline.
- [ ] Re-test `SW5=1` raw ingress after every RX adapter edit as the known-good A-side baseline.
- [ ] Do not continue the file/video or sine-wave demos until a PC1-triggered frame is visible on PC2.
