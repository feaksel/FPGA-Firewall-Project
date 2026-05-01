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
- [x] verify power and pin mapping
- [x] verify reset wiring
- [x] verify SPI clock polarity and phase assumptions
- [x] verify controller reset sequence
- [x] read one known register
- [ ] read multiple known registers consistently

## Day 2 with hardware
- [x] complete init sequence
- [x] verify RX status, interrupt, or polling path
- [x] detect packet arrival
- [x] read packet length
- [ ] dump first packet bytes over debug or UART if available

## Day 3+
- [x] feed real packet bytes into existing firewall core
- [x] compare parsed fields against Wireshark capture
- [ ] verify allow/drop counts
- [ ] only then start second-port forwarding

## 2026-05-01 hardware status

Current verified state:
- DE1-SoC JTAG/SRAM programming works through USB-Blaster.
- W5500 reset, SPI register access, and MACRAW initialization work on the physical module.
- `VERSIONR` register access is confirmed after correcting the W5500 SPI control byte definitions.
- The adapter reaches RX polling with `init_done` high and `init_error` low.
- The PC-side Scapy sender produced deterministic packets that appeared in Wireshark:
  - `udp_allow`
  - `tcp_drop`
  - `tcp_allow_ssh`
- Board LEDs show receive/counter activity while Ethernet traffic is present.

Current limitation:
- Allow/drop behavior is visible only through single-bit counter LEDs, so per-packet profile correlation still needs a cleaner debug method.
- The design remains receive/inspect only; forwarding must wait until allow/drop validation is repeatable.

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
