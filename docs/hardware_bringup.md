# Hardware Bring-Up Checklist

## Before board/module arrives
- [x] `parser_tb` passes
- [x] `rule_engine_tb` passes
- [x] `firewall_core_tb` passes
- [x] `spi_master_tb` passes
- [x] controller adapter shell exists
- [x] debug counters available at top-level
- [x] `packet_buffer_tb` passes
- [x] `eth_controller_adapter_tb` passes

## Day 1 with hardware
- [ ] verify power and pin mapping
- [ ] verify reset wiring
- [ ] verify SPI clock polarity and phase assumptions
- [ ] verify controller reset sequence
- [ ] read one known register
- [ ] read multiple known registers consistently

## Day 2 with hardware
- [ ] complete init sequence
- [ ] verify RX status, interrupt, or polling path
- [ ] detect packet arrival
- [ ] read packet length
- [ ] dump first packet bytes over debug or UART if available

## Day 3+
- [ ] feed real packet bytes into existing firewall core
- [ ] compare parsed fields against Wireshark capture
- [ ] verify allow/drop counts
- [ ] only then start second-port forwarding

## Red flags
Stop and document before proceeding if:
- SPI reads inconsistent values
- reset behavior unstable
- controller init sequence partially works
- received packet lengths are nonsense
- first bytes do not match expected Ethernet headers

If any red flag appears:
1. log in `BUGS.md`
2. save the waveform or notes
3. do not add more features until root cause is isolated
