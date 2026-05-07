# TODO

## Current Milestone
- [x] M1: Packet source simulation infrastructure
- [x] M2: Parser implementation
- [x] M3: Rule engine implementation
- [x] M4: Firewall core integration
- [x] M5: SPI master implementation
- [x] M6: Ethernet controller adapter shell
- [x] M7: One-port hardware bring-up
- [x] M8: Real one-way UDP policy forwarding
- [ ] M9: File/video transfer demo with telemetry dashboard

Current status note, 2026-05-03:
- M8 is narrowed but not accepted yet. `SW6` proves W5500 B can transmit a known FPGA-generated frame to PC2, and `SW5` proves W5500 A can receive PC1 traffic. SignalTap plus `sw7-0004.pcapng` now prove `SW7` can forward at least some real Mac-origin frames through A -> FPGA -> B -> PC2. The intended demo markers still need a clean retest:
  - `SW7` raw A-to-B bypass: command-line SignalTap shows B TX buffer writes/SEND clears with no timeout; PC2 pcap includes matching Mac-origin multicast frames.
  - Old demo sender commands used spoofed source MAC `00:11:22:33:44:55`; the senders now default to PC1's real interface MAC.
  - `SW8` generated rule-demo mode: latest hardware report shows `SW[3:1]=101` stuck at `0000`, so the generated TX trigger is not firing.
- The next milestone is a real-MAC rule-demo retest plus SignalTap capture if the markers still do not arrive.

Current status note, 2026-05-05 (rounds 4-8 condensed):
- Demo UDP/80 frames are confirmed leaving PC1's en0 by tcpdump (5 packets captured).
- W5500 A PHY is confirmed linked at 100M FDX (`stp_phy_cfgr = 0xBF`).
- PHY is fine, sender is fine, cables are direct point-to-point.
- The chip's RX buffer is being filled mostly by the Mac's `mDNSResponder` link-up flood, and the previous adapter discard path was flushing the *entire* buffer on a single corrupted length header, taking demo frames with it. Round 8 RTL fix caps each discard to 1520 bytes (one max Ethernet frame). Later rounds showed this helped visibility but did not make MACRAW deliver demo UDP/80.
- Bench protocol now requires waiting 30 seconds after every reflash before triggering SignalTap, so the post-link-up Bonjour burst settles before we capture.

Current status note, 2026-05-05 (rounds 9-19 condensed):
- The bounded-discard, faster A SPI drain, repeated bad-length resync, MFEN on/off, multicast/broadcast/raw Scapy sender variants, and normal UDP socket sender variants were all tested.
- PC1 is definitively putting the demo packet on the direct W5500 A wire: `1c:f6:4c:44:ff:46 > 02:00:00:de:ad:0a`, IPv4, `192.168.1.10:4660 > 192.168.1.1:80`, 10/10 tcpdump captures, zero kernel drops.
- W5500 A readbacks are definitive: `PHYCFGR=0xBF`, `S0_MR=0x84`, `SHAR=02:00:00:DE:AD:0A`, `SIPR=192.168.1.1`.
- Even with correct PC1 packets and correct W5500 A MAC/IP configuration, MACRAW A ingress never surfaced UDP/80 in SignalTap (`frames_udp_dport80=0`, `frames_demo_match=0`). It only surfaced broadcast/multicast Mac background frames such as UDP/5353.
- Decision: A-side MACRAW is no longer the main demo path. Move to W5500 A normal UDP socket receive mode, then reconstruct/synthesize the Ethernet/IP/UDP stream inside the FPGA and feed the existing firewall/forwarder/B-TX path.

Current status note, 2026-05-05 (rounds 20-22 condensed):
- Implemented W5500 A UDP socket RX, internal Ethernet/IP/UDP reconstruction, periodic PHY/socket-status refresh, and wait-for-link before opening socket 0.
- Questa passed for `w5500_udp_rx_adapter_tb`, `de1_soc_top_udp_socket_forward_tb`, `de1_soc_top_bypass_tb`, `de1_soc_top_rule_regen_tb`, `adapter_firewall_integration_tb`, `eth_controller_adapter_tb`, and `two_port_bypass_tb`.
- Round-22 hardware capture proves the core path: `S0_SR=0x22`, `PHYCFGR=0xBF`, `frames_udp_dport80=frames_demo_match=0x74`, `b_tx_count=0x74`, `b_send_timeouts=0`, and matching A RX/B TX first bytes.
- PC2 dashboard/Wireshark visibility was confirmed by the user after round 22. The remaining final-demo work is to package this as a UDP policy gateway with multi-service rules, rule histograms, and a small streaming signature matcher.

Current status note, 2026-05-05 (final-demo pivot):
- Stop treating W5500 A MACRAW as the product path. It remains valuable diagnostic history, but the final demo path is W5500 UDP socket ingress, FPGA stream policy/signature classification, and W5500 B transmit.
- Implemented the A+C capstone direction: UDP/80 allow, UDP/5001 file/sine/data allow, UDP/5002 decoy drop, and content-block override with `FW-BLOCK` / `FW-DEMO-DROP`.
- Added per-rule counters and UART telemetry fields for dashboard histograms: `U80`, `U51`, `D52`, `SIG`, `DEF`, `FIL`, and `SIN`.
- That pivot image compiled and flashed successfully with SOF checksum `0x085DC65F`.
- Post-flash idle SignalTap capture confirmed W5500 A UDP socket status `0x22` and zero B SEND timeouts.
- UART dashboard wiring is now documented: `GPIO_0_D6` -> USB-UART `RXD`, ground -> ground, `115200 8N1`, dashboard `--uart COMx`. The dashboard rate graph now uses a wall-clock rolling window so it continues moving when traffic stops.
- File receiver now has a visual browser dashboard with chunk map, SHA-256 status, leak count, and completed-file preview. Sine dashboard now plots sample dots on a rolling time axis so packet gaps remain visible.

Current status note, 2026-05-07 (file-demo hardware fix):
- Latest flashed image checksum is `0x085D8724`.
- Fixed the UDP/5001 file-demo hardware failure by widening `firewall_forwarder` byte-index registers from 8 bits to 16 bits. The old index wrapped after byte 255 in 348-byte synthesized file frames and corrupted the saved header fields before the EOP decision.
- Questa passed for `w5500_udp_rx_adapter_tb`, `de1_soc_top_udp_socket_forward_tb`, `firewall_forwarder_tb`, `adapter_firewall_integration_tb`, `de1_soc_top_bypass_tb`, and `de1_soc_top_rule_regen_tb`.
- Post-fix SignalTap proved the file path: UDP/5001 observed, `last_frame_len=b_last_pkt_len=0x015C`, `b_buf_writes=b_send_issued=b_send_cleared=b_tx_count=0x7D`, `b_send_timeouts=0`.
- PC2 Npcap sniff captured UDP/5001 `FWFILE1\0` chunks with 306-byte payloads, so W5500 B visibility is proven for the file-demo frame size.
- User stress-tested the file sender at `--interval 0.001`; 60 allowed chunks were missed out of 3913, so SHA-256 and preview intentionally did not complete. This is expected for raw UDP under stress and is not a dashboard bug.
- The final clean proof still needs a safe-rate full transfer (`--decoys 1 --interval 0.10`) with SHA-256 match and no UDP/5002/content-block leaks.
- File receiver now auto-renames completed media from the default `.bin` path to `.mp4`, `.jpg`, `.png`, `.gif`, or `.mp3` when bytes identify the type, and it can advance through multiple `file_id`s for photo-by-photo demos.
- Added `photo_stream_sender.py` for a simple JPEG/PNG still-frame stream over the same UDP/5001 FPGA path.

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
- [x] Program and validate the `SW9` byte/state debug image:
  - A RX first bytes should match the PC1 demo frame destination/source/ethertype.
  - B TX first bytes should match the frame intended for PC2.
  - B TX progress pages should show whether TX-buffer write, SEND issue, SEND clear, or timeout happened.
- [ ] Re-test the rule demo with the updated real-MAC sender default:
  - PC1: `sudo python3 scripts/rule_demo_sender.py --iface enX`
  - PC2: dashboard plus no-filter Wireshark capture.
  - If needed, summarize the capture with `scripts/pcap_summary.py`.
- [x] Add the first stream-level forwarding wrapper for allow/drop forwarding tests
- [x] Reserve the second W5500 logical wiring on `GPIO_1[0..5]`
- [x] Add a standalone W5500 TX engine and simulation model for TX-buffer/SEND coverage
- [x] Add a transmit-only UART telemetry module on `GPIO_0_D6`
- [x] Add PC-side chunked file sender/receiver scripts for the final demo concept
- [x] Add continuous payload-waveform sender and PC2 browser receiver dashboard
- [x] Extend the dashboard with a two-port file-demo preview panel
- [ ] Make `firewall_forwarder_tb` pass reliably under XSim
- [ ] Make `w5500_tx_engine_tb` pass under XSim
- [x] Integrate W5500 A RX -> rules -> W5500 B TX in a single hardware top
- [x] Replace W5500 B byte-at-a-time TX payload writes with burst TX-buffer writes
- [x] Use PC2 receiver/Wireshark plus board HEX pages as the first no-UART two-port telemetry path
- [x] Add a PC/dashboard UART reader later as an optional live FPGA counter source
- [ ] Validate W5500 B alone on hardware: reset, `VERSIONR`, MACRAW init
- [ ] Prove a fixed test frame transmitted from FPGA to PC2
- [x] Prove one allowed PC1-to-PC2 forwarded packet on the UDP socket path
- [ ] Prove one dropped packet with the final UDP/5002 or content-block policy image
- [ ] Run the final visual file transfer dashboard and verify PC2 SHA-256 match while decoys are dropped

## Current Debug Tasks

- [x] Add HEX-visible first-byte diagnostics for W5500 A RX (now `SW9=1, SW5=0, SW4=0`).
- [x] Add HEX-visible first-byte diagnostics for the frame submitted to W5500 B TX (now `SW9=1, SW5=0, SW4=1`).
- [x] Add a TX-completion/error page that distinguishes buf-write start/done, `S0_TX_WR` update, `SEND` written, `S0_CR` cleared, and timeout (now `SW9=1, SW5=1, SW4=0` pages 010-101).
- [x] Add SignalTap II probes for the same signals (`stp_a_rx_first16`, `stp_b_tx_first16`, `stp_b_buf_writes`, `stp_b_send_issued/cleared/timeouts`, `stp_b_tx_count`, etc.) so we can read them via JTAG without depending on the seven-segment display.
- [x] Add IPv4-only RX shadow `stp_a_rx_ipv4_first16` and per-ethertype frame counters so background IPv6 traffic can no longer hide what's actually arriving.
- [x] Add `stp_phy_cfgr` SignalTap probe so we can read the W5500 PHY's link/speed/duplex bits (LNK, SPD, DPX). Round 7 capture confirmed PHY is at 100M FDX.
- [x] Add round 4 chip-state hardening: `SHAR` write at init, `S0_CR` clear poll after `RECV`, `S0_IR` clear after RECV. Did not change observed counters.
- [x] Round 8 RTL fix: bounded the bad-length discard to 1520 bytes so a single corrupted length header no longer flushes legitimate frames buffered behind it. Later hardware verified MACRAW still misses demo UDP/80, so this is retained as hardening rather than the final fix.
- [x] Prove PC1 normal UDP/static-ARP sender is clean with tcpdump on current hardware.
- [x] Read back W5500 A `S0_MR`, `SHAR`, and `SIPR` from hardware over SPI and expose them in SignalTap.
- [x] Falsify A-side MACRAW for the current demo packet after correct sender, PHY, SHAR, SIPR, and MFEN readbacks.
- [x] Add first-pass W5500 A UDP socket receive mode for demo ingress (`w5500_udp_rx_adapter`).
- [x] Reconstruct an internal Ethernet/IP/UDP byte stream from the UDP socket header/payload so the existing firewall/forwarder/B-TX path can be reused.
- [x] Run the new Questa coverage: `w5500_udp_rx_adapter_tb`, `de1_soc_top_udp_socket_forward_tb`, `adapter_firewall_integration_tb`, `de1_soc_top_bypass_tb`, and `de1_soc_top_rule_regen_tb`.
- [x] Recompile Quartus, flash, and repeat the SignalTap force-export capture with the normal UDP socket sender.
- [x] Add wait-for-link before opening W5500 A UDP socket 0; round 22 is the first hardware-success capture.
- [ ] Re-test `SW6` after every TX adapter edit as the known-good B-side baseline.
- [ ] Re-test `SW5=1` raw ingress after every RX adapter edit as the known-good A-side baseline.
- [x] Do not continue the file/video or sine-wave demos until a PC1-triggered frame is visible on PC2. Completed after round 22; PC2 dashboard/Wireshark now see forwarded packets.
- [x] Compile and flash the multi-socket UDP policy/signature image.
- [x] Bench-test the multi-socket UDP policy/signature image for UDP/80 and UDP/5001 allowed traffic with active PC1 sender and PC2 dashboard/sniff.
- [ ] Capture final SignalTap/UART evidence for UDP/80 allow, UDP/5001 allow, UDP/5002 drop, content-block drop, and zero B SEND timeouts.
- [ ] Run the final safe-rate file proof (`--decoys 1 --interval 0.10`) and verify SHA-256 match on PC2.

## Bench protocol checklist (2026-05-05)

The MACRAW hardware-loop iteration that produced the final diagnosis was:

1. PC1 (Mac, en0) <-> direct cable <-> W5500 A.
2. W5500 B <-> direct cable <-> PC2 (Win NIC for dashboard / Wireshark).
3. No switches, hubs, or other devices on either link.
4. Reflash the SOF, press reset (`KEY[0]`), wait for `LEDR0=1`.
5. **Wait 30 seconds** for the Mac's `mDNSResponder` link-up Bonjour burst to settle.
6. Configure PC1 for the normal socket sender:
   - `sudo ifconfig en0 inet 192.168.1.10 netmask 255.255.255.0 up`
   - `sudo arp -d 192.168.1.1 2>/dev/null || true`
   - `sudo arp -s 192.168.1.1 02:00:00:de:ad:0a`
7. Start the sender on PC1: `python3 scripts/rule_demo_udp_socket_sender.py --iface en0 --rate 2 --verbose-each`.
8. Verify with `sudo tcpdump -i en0 -nn -e -c 10 'udp port 80 or arp'` that frames are leaving en0 as `1c:f6:4c:44:ff:46 > 02:00:00:de:ad:0a`, `192.168.1.10:4660 > 192.168.1.1:80`.
9. Capture with `quartus_stp.exe -t scripts/signaltap_capture.tcl quartus/de1_soc_w5500.stp captures/stp/<tag>.csv 30`.
10. Decode with `py -3 scripts/inspect_signaltap_csv.py captures/stp/<tag>.csv`.
11. For the MACRAW images, the final expected-but-never-observed acceptance was `frames_udp_dport80 > 0` and `b_tx_count > 0`.
12. For the next UDP-socket ingress image, acceptance is a PC1-triggered receive event at W5500 A, then B TX completion with zero timeouts.

## Things adding new SignalTap probes requires

Adding a new `stp_*` register to `rtl/top/de1_soc_w5500_top.v` is **not** enough on its own. The SignalTap II IP is instrumented at fit time. After RTL changes:

1. Open `quartus/de1_soc_w5500.stp` in Quartus Prime SignalTap II.
2. Add the new signals via Node Finder (filter on `stp_`).
3. Save the .stp.
4. Re-run the full Quartus compile so the new sample widths are baked into the SOF.
5. Reflash.

If you just edit the `.stp` after the SOF was already built, the live probe set on the chip will not match what the .stp claims, and `quartus_stp` will refuse to capture with the error "Instance, signal set, or trigger does not exist."
