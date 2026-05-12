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
- [x] verify allow/drop counts on the UDP socket policy path
- [x] prove PC1-triggered W5500 B TX on the UDP socket policy path
- [x] start final second-port forwarding/file demo
- [ ] complete final safe-rate file SHA-256 proof with decoys and no leaks

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

## 2026-05-03 hardware status

Current verified state:
- W5500 A RX path works in raw/debug mode:
  - `SW5=1`, `SW[3:1]=001` raw byte count can rise.
  - `SW[3:1]=010` commit count can rise.
  - `SW[3:1]=100` last frame length has shown realistic values around `0x50` to `0x52`.
- W5500 B direct TX works:
  - `SW6=1` emits the internal `FW-DEMO-ALLOW-SSH` frame and PC2 can capture it.
- Direct PC1-to-PC2 cable test works:
  - direct capture contains frames from source MAC `00:11:22:33:44:55`.

Historical blocker at that time:
- A-triggered MACRAW transmit was narrowed but not accepted:
  - `SW7=1` raw bypass has produced TX counts such as `0004`/`0006`, but PC2 captures did not show the intended demo markers.
  - `SW8=1` generated rule-demo mode latest report showed `SW[3:1]=101 = 0000`, so no generated B TX was triggered.
  - SignalTap now proves `SW7=1` can reach W5500 B TX for at least one frame: SEND is issued, SEND clears, timeout stays zero, and B TX first bytes are `FFFFFFFFFFFF00112233445508004500`.
  - Command-line SignalTap plus `sw7-0004.pcapng` proves at least some real Mac-origin multicast frames cross A -> FPGA -> B -> PC2.
  - The old demo senders forced spoofed source MAC `00:11:22:33:44:55`; they now default to PC1's real interface MAC.

Latest debug image:
- SW9 debug image compiled and programmed on 2026-05-03 at 21:41.
- Programming file: `build/quartus/de1_soc_w5500.sof`.
- Programmer checksum: `0x03D248C1`.
- Adds `SW9` byte/state debug mode for A RX first bytes, B TX input first bytes, W5500 B TX progress, and SW8 parser fields.
- SignalTap-enabled image compiled and programmed on 2026-05-03 at 23:02.
- SignalTap programmer checksum: `0x06381BE5`.
- Adds preserved `stp_*` probe registers for A RX, B TX input, B TX progress, SPI B, switches, and SW8 parser fields.

Current rule:
- Do not treat FPGA TX count alone as proof of forwarding. The acceptance evidence is a PC2 capture containing the expected demo source/payload caused by PC1 traffic.

Next bring-up action:
The 2026-05-03 action list is now historical. The final path moved away from
A-side MACRAW and uses W5500 UDP sockets.

## 2026-05-07 hardware status

Current verified state:
- W5500 A UDP socket ingress works for UDP/80 and UDP/5001.
- W5500 B transmits PC1-triggered allowed frames to PC2.
- SOF checksum `0x085D8724` includes the forwarder 16-bit byte-index fix.
- SignalTap proved safe-size file-demo forwarding with `last_frame_len=0x015C`,
  `b_last_pkt_len=0x015C`, `b_tx_count=0x7D`, and `b_send_timeouts=0`.
- PC2 Npcap sniff captured UDP/5001 `FWFILE1\0` chunks with 306-byte payloads.

Current bring-up action:
1. Use normal mode: `SW0=1`, `SW5=0`, `SW7=0`, `SW8=0`, `SW9=0`.
2. Run the final file receiver on PC2:
   `py -3 scripts\file_receiver.py --iface Ethernet --output .\received_demo.mp4 --port 8092`.
3. Run the safe PC1 sender:
   `sudo python3 scripts/file_sender.py --iface en0 --file demo.mp4 --decoys 1 --interval 0.10`.
4. Confirm PC2 SHA-256 pass and zero UDP/5002 / `FW-BLOCK` leaks.
5. If UART is not connected, capture SignalTap force-export and decode it with
   `scripts/inspect_signaltap_csv.py`.

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
