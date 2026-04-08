# TODO

## Current Milestone
- [ ] M1: Packet source simulation infrastructure
- [ ] M2: Parser implementation
- [ ] M3: Rule engine implementation
- [ ] M4: Firewall core integration
- [ ] M5: SPI master implementation
- [ ] M6: Ethernet controller adapter shell
- [ ] M7: One-port hardware bring-up
- [ ] M8: Optional second-port forwarding

## Immediate Tasks
- [x] Finalize `docs/interfaces.md`
- [x] Add packet memory vectors to `tb/packets/`
- [ ] Make `parser_tb` pass with IPv4 TCP and UDP packets
- [ ] Make `rule_engine_tb` pass
- [ ] Make `packet_buffer_tb` pass
- [ ] Make `spi_master_tb` pass
- [ ] Integrate parser + rules into `firewall_core_tb`
- [ ] Freeze the actual Ethernet controller choice for the adapter implementation
