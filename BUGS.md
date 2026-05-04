# BUGS

## Open Bugs

- **B-2026-05-03-01: A-triggered W5500 B transmit does not reliably show the intended demo frames on PC2.**
  - Status: open, narrowed by SignalTap; no longer considered a totally dead SW7 path.
  - Evidence:
    - `SW6=1` direct B transmit test works; PC2/Wireshark sees the internally generated `FW-DEMO-ALLOW-SSH` frame.
    - `SW5=1` raw A ingress debug works; A-side raw byte/commit counts rise and last frame length is around `0x50` to `0x52`.
    - Direct PC1-to-PC2 cable capture works; `wire_rawPc1traffic.pcapng` contains 18 demo frames from source MAC `00:11:22:33:44:55`.
    - `SW7=1` raw bypass did not show demo frames on PC2. Captures such as `sw7simple.pcapng` and `sw7-0004.pcapng` originally looked like only local/background PC2 traffic, even when FPGA TX count reached values like `0004` or `0006`.
    - `SW8=1` generated rule-demo mode was added, but the latest hardware observation was `SW[3:1]=101 = 0000`, so the generated TX path did not trigger.
    - First SignalTap capture in `SW7=1` showed `stp_b_buf_writes=1`, `stp_b_send_issued=1`, `stp_b_send_cleared=1`, `stp_b_send_timeouts=0`, `stp_b_tx_count=1`, `stp_b_last_pkt_len=0x004E`, and `stp_b_tx_first16=FFFFFFFFFFFF00112233445508004500`.
    - SEND-window SignalTap capture in `SW7=1` showed B TX state moving from `0x0E` (`ST_SEND`) to `0x10` (`ST_WAIT_SEND`), `stp_b_send_issued` rising to `1`, active B SPI, and no timeout inside the short 2K sample window.
    - Command-line SignalTap capture in `SW7=1` showed `stp_b_buf_writes=3`, `stp_b_send_issued=3`, `stp_b_send_cleared=3`, `stp_b_send_timeouts=0`, and matching A RX/B TX first bytes `3333000000FB1CF64C44FF4686DD6008`.
    - `scripts/pcap_summary.py C:\Users\furka\Desktop\sw7-0004.pcapng` shows three frames from the Mac source MAC `1c:f6:4c:44:ff:46`, matching the SignalTap multicast frame. This proves at least some real Mac-origin frames crossed A -> FPGA -> B -> PC2 in SW7.
  - Current interpretation:
    - W5500 A receive and W5500 B direct transmit are individually proven.
    - The `SW7` path is now proven to reach W5500 B TX and PC2 for at least some Mac-origin frames.
    - The intended rule-demo packets used a spoofed Ethernet source MAC `00:11:22:33:44:55`. Because forwarded real-Mac background frames appear while spoofed demo markers are absent, the next fix is to run demo senders with PC1's real interface MAC by default.
  - Next debug:
    - Re-test `scripts/rule_demo_sender.py --iface enX` after the sender source/destination MAC default change. The script now prints both MACs it will use.
    - The updated sender sends UDP/80 allow by default and uses destination MAC `01:00:5e:00:00:fb`, matching the multicast path already proven by SignalTap and `sw7-0004.pcapng`.
    - Capture PC2 with no Wireshark filter first, then use marker filters such as `frame contains "FW-DEMO"` instead of relying on the old spoofed source MAC.
    - 2026-05-04 capture `captures/stp/after_reflash_sender_running.csv` (normal-mode SW0=1 only, sender running) showed `stp_a_rx_first16 = 0F33000000161CF64C44FF4686DD6000` -> IPv6 background frame, `stp_b_tx_count = 0`, all B counters zero. The single rolling shadow could not tell whether the demo IPv4 frame ever arrived: background IPv6 from the Mac is constantly overwriting it.
    - 2026-05-04 RTL update: added IPv4-only shadow `stp_a_rx_ipv4_first16` and per-ethertype frame counters `stp_frames_ipv4 / ipv6 / arp / other / udp_dport80 / demo_match`. After reflash, `scripts/inspect_signaltap_csv.py` prints a Diagnosis line that selects between five outcomes:
      - `frames_ipv4 == 0` and `frames_ipv6 > 0`: PC1 demo IPv4 frames are not reaching the W5500. Action shifts to PC1 (`tcpdump` on `en0` to confirm Scapy is sending and binding the right NIC; verify the cable goes to W5500 A).
      - `frames_ipv4 > 0` and `frames_demo_match == 0`: IPv4 reaches A but does not match UDP dst=80. Action: re-check sender params and W5500 byte alignment.
      - `frames_demo_match > 0` and `b_buf_writes == 0`: bytes arrive at A but the gap is in fifo / forwarder / packet_buffer. Trigger SignalTap on `tx_to_b_valid` rising edge.
      - `b_buf_writes > 0` and `b_tx_count == 0`: B starts the buffer write but SEND never completes. Trigger on `adapter_b_debug_state == 14 (ST_SEND)` and inspect `S0_CR` clear.
      - `b_tx_count > 0` and PC2 still sees nothing: suspect PC2 NIC IPv4 multicast filter (224.0.0.251 needs an IGMP join), Wireshark filter, or W5500-B PHY/cable. PC2-side packet capture with `udp dst port 80` filter required.
    - User must add the new `stp_a_rx_ipv4_first16` and `stp_frames_*` probes to `quartus/de1_soc_w5500.stp` once via the SignalTap GUI (Node Finder, type `stp_*`), save, and recompile. After that, the existing `scripts/signaltap_capture.tcl` flow keeps working.
  - 2026-05-04 round 2 capture (`captures/stp/round2_force.csv`, normal mode SW0=1, sender supposedly running, force-trigger via `signaltap_capture_force.tcl`):
    - `frames_ipv4 = 3`, `frames_ipv6 = 2`, `frames_udp_dport80 = 0`, `frames_demo_match = 0`.
    - `stp_a_rx_first16 = stp_a_rx_ipv4_first16 = stp_b_tx_first16 = 01005E0000FB1CF64C44FF4608004500`.
      - Decoded: `dst=01:00:5E:00:00:FB src=1C:F6:4C:44:FF:46 ethertype=0800 next=45 00`.
      - Same bytes on A and B confirm the FPGA pipeline forwards every IPv4 frame end-to-end.
    - `b_buf_writes = b_send_issued = b_send_cleared = b_tx_count = 3`, `b_send_timeouts = 0` -> three real transmissions, no errors.
    - `regen_dst_port = 0x14E9 = 5353` (mDNS), so the IPv4 frames seen by A were Mac mDNS background, not the demo's UDP/80.
    - A second capture 30 seconds later showed identical counters -> no new traffic at all between captures.
  - Conclusion: the FPGA is doing its job. The remaining bug is **PC1-side**. The Mac's outbound UDP/80 multicast frames are not reaching `en0` (or aren't being put on the wire). Hypothesis: macOS multicast routing steers `224.0.0.251` traffic to `lo0` for non-mDNS ports, or PF/firewall blocks Scapy's raw UDP/80 inject.
  - Mitigation applied 2026-05-04: changed `scripts/rule_demo_sender.py` default to broadcast (`ff:ff:ff:ff:ff:ff`, dst IP `192.168.1.255`). Broadcast bypasses all multicast routing logic. User must:
    1. Pull/copy the updated repo to PC1.
    2. Stop the old sender (`Ctrl+C`).
    3. Restart with `sudo python3 scripts/rule_demo_sender.py --iface en0 --rate 2 --packet-gap 0.05 --no-ssh-allow --no-tcp-drop --verbose-each`.
    4. Confirm the printed `dst_mac=ff:ff:ff:ff:ff:ff`.
    5. Recapture with `quartus_stp.exe -t scripts/signaltap_capture_force.tcl quartus/de1_soc_w5500.stp captures/stp/round3.csv 5`.
    6. Run `py -3 scripts/inspect_signaltap_csv.py captures/stp/round3.csv` and watch for `frames_demo_match > 0` and `stp_a_rx_first16` starting with `FFFFFFFFFFFF...`.
  - Independent check on PC1: `sudo tcpdump -i en0 -nn -e -c 5 udp port 80` while the sender runs. If tcpdump prints zero matches, Scapy's L2 inject is being silently dropped on the Mac side.

- **B-2026-05-03-02: W5500 simulation models are not strong enough evidence for the two-port hardware path.**
  - Status: open.
  - Evidence:
    - `two_port_bypass_tb`, `de1_soc_top_bypass_tb`, and `de1_soc_top_rule_regen_tb` can pass while hardware still fails.
  - Current interpretation:
    - The models are useful for RTL syntax and high-level sequencing, but they do not yet model enough real W5500 timing, buffering, command completion, link behavior, or malformed-frame behavior to predict hardware success.
  - Next debug:
    - Strengthen models only after collecting hardware byte/state evidence, so the model changes reflect real failure modes instead of guesses.

- Quartus timing analysis still reports the design as not fully constrained because the external W5500 timing model has not yet been turned into board-accurate I/O timing constraints. Current pre-hardware flow uses false paths for human/asynchronous inputs instead of invented external timing numbers.

---

## Resolved Bugs

- Removed Quartus SPI truncation warnings in `rtl/spi/spi_master.v` by making `CPOL` and `CPHA` explicitly 1-bit in the implementation.
- Removed the `KEY[0]` non-dedicated/global clock warning by synchronizing reset release at the DE1-SoC top-level boundary instead of using the raw pushbutton directly across the design.
- Fixed hardware reset bring-up stalling in `ST_RESET` by widening the W5500 adapter wait counter from 16 bits to 32 bits. The board-level reset delays are now large enough for real hardware and still count to completion.
- Fixed W5500 SPI read/write control-byte polarity. The original adapter treated `RWB=1` as read, but W5500 uses `RWB=0` for read and `RWB=1` for write. The hardware symptom was `VERSIONR` reading back as `0x00` even with correct wiring.
- Fixed the W5500 simulation model so it uses the same corrected SPI control-byte definitions as the hardware adapter.
- Prevented malformed or oversized W5500 RX frames from permanently locking the adapter in `ST_ERROR`; the adapter now advances the RX read pointer and commits/discards the frame.
- Fixed a W5500 B TX adapter backpressure bug where normal `frame_valid && !frame_ready` conditions were treated as fatal errors.
- Changed W5500 B TX free-space handling to wait/retry instead of dropping a pending packet when `S0_TX_FSR` is temporarily too small.
- Added W5500 `S0_CR` command-clear polling after `SEND`, so TX count now represents command completion instead of merely writing the `SEND` command.
