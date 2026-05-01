# TODO

## Current Milestone
- [x] M1: Packet source simulation infrastructure
- [x] M2: Parser implementation
- [x] M3: Rule engine implementation
- [x] M4: Firewall core integration
- [x] M5: SPI master implementation
- [x] M6: Ethernet controller adapter shell
- [x] M7: One-port hardware bring-up
- [ ] M8: Optional second-port forwarding

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
- [ ] Validate the new HEX debug pages on the physical board with `udp_allow`, `tcp_drop`, and `tcp_allow_ssh`
- [ ] Extend the browser dashboard for two-port tests once a second NIC/PC or FPGA telemetry path is available
- [ ] Decide whether the next telemetry path should be UART, HPS bridge, JTAG debug, or Ethernet TX
