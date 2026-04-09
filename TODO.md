# TODO

## Current Milestone
- [x] M1: Packet source simulation infrastructure
- [x] M2: Parser implementation
- [x] M3: Rule engine implementation
- [x] M4: Firewall core integration
- [x] M5: SPI master implementation
- [x] M6: Ethernet controller adapter shell
- [ ] M7: One-port hardware bring-up
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
- [ ] Freeze the Quartus project and pin assignment flow around `de1_soc_w5500_top`
- [ ] Prepare the first minimal DE1-SoC hardware image and bring-up checklist
- [ ] Use the PC-side Scapy helper during physical test once the first RX path is alive
