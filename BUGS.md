# BUGS

## Open Bugs

- **B-2026-05-06-01: File demo forwards only the final short chunk, then no safe-size chunks, before forwarder byte-index fix.**
  - Status: resolved in RTL and hardware on 2026-05-07.
  - Evidence:
    - PC1 tcpdump during the transfer showed the sender correctly emitted `84` UDP packets: `63` to UDP/5001 and `21` to UDP/5002.
    - PC2 capture `C:\Users\furka\Desktop\filesending1chunk.pcapng` contains only one UDP/5001 `FWFILE1\0` packet from the demo path.
    - Decoding that packet shows `file_id=2`, `chunk=41`, `total=42`, `file_size=21063`, and `data_len=71`, so the only forwarded chunk was the final short chunk.
  - Root cause:
    - `scripts/file_sender.py` previously defaulted to `--chunk-size 512`.
    - Each allowed file datagram carries a 50-byte `FWFILE1` demo header.
    - W5500 UDP socket ingress synthesizes a 42-byte Ethernet/IPv4/UDP wrapper before the rule engine.
    - A full file chunk therefore becomes `42 + 50 + 512 = 604` FPGA-internal frame bytes.
    - Any flashed image or intermediate path still enforcing a conservative 512-byte frame guard treats those full chunks as oversized and commits/discards them before forwarding. The final short chunk is only `42 + 50 + 71 = 163` bytes, so it passes.
  - Mitigation:
    - Changed the sender default to `--chunk-size 256`, producing `348`-byte internal frames.
    - Added a sender warning when the selected chunk size exceeds the conservative 512-byte internal-frame budget.
    - Documented that `--chunk-size 420` is the largest safe file data size for a 512-byte internal-frame guard (`512 - 42 - 50`).
  - Next validation:
    - Re-run PC2 `file_receiver.py`, then PC1 `file_sender.py` with the new default or explicit `--chunk-size 256`.
    - Start with `--decoys 0 --limit-chunks 4 --interval 0.10` to prove the allowed UDP/5001 path without burst pressure.
    - Then run the full `--decoys 1 --interval 0.10` proof. Avoid the old `--interval 0.01` until the full path is shown stable.
    - Expected PC2 result: all chunks arrive, SHA-256 passes, UDP/5002 and `FW-BLOCK` decoys still do not leak.
    - If 512-byte chunks are desired for the final image, recompile/flash a proven 2048-byte ingress/FIFO/forwarder path and capture SignalTap counters for `last_frame_len`, `rx_commit_count`, `rule_allow5001`, and `b_tx_count`.
  - 2026-05-06 follow-up:
    - User confirmed the new sender emits 348-byte UDP/5001 frames and short UDP/5002/content-block decoys on PC1 `en0`, but the slow `--decoys 0 --limit-chunks 4` PC2 probe still shows no UDP at all.
    - This rules out PC1 egress, oversized 604-byte chunks, and decoy/content-block side effects for the no-PC2 symptom.
    - Next split is hardware-internal: socket 1/UDP5001 A ingress versus parser/rule/forwarder/B-TX. Run continuous `file_sender.py --decoys 0 --limit-chunks 4 --interval 0.10 --repeat 0` and inspect UART/SignalTap counters.
  - 2026-05-07 hardware root cause and fix:
    - Clean post-reflash SignalTap before the fix showed W5500 A receiving the safe-size file chunks (`stp_regen_dst_port=0x1389`, `stp_last_frame_len=0x015C`, `rx_commit_count=0x81`) while W5500 B stayed at `b_buf_writes=b_send_issued=b_tx_count=0`.
    - The break was inside `firewall_forwarder`: its rule-decision byte index was only 8 bits wide. A 348-byte synthesized file frame wraps that index after byte 255, so later payload bytes overwrite the saved Ethernet/IP/UDP header fields and the EOP decision drops an otherwise allowed UDP/5001 packet.
    - Widened `fwd_byte_idx` and `fwd_current_idx` to 16 bits in `rtl/firewall/firewall_forwarder.v`.
    - Expanded `w5500_udp_rx_adapter_tb` and `de1_soc_top_udp_socket_forward_tb` to the real file-demo payload size: `306` UDP payload bytes, `348` synthesized frame bytes.
    - Recompiled and flashed SOF checksum `0x085D8724`.
    - Post-fix SignalTap `captures/stp/file_probe_after_index_fix.csv` proved forwarding: `b_buf_writes=b_send_issued=b_send_cleared=b_tx_count=0x7D`, `b_send_timeouts=0`, `b_last_pkt_len=stp_last_frame_len=0x015C`, and A/B first 16 bytes matched.
    - PC2-side Scapy/Npcap sniff on `Ethernet` captured `30` UDP/5001 packets in `12 s`, each with `306` payload bytes and the `FWFILE1\0` marker. This confirms the fixed image reaches PC2, not only W5500 B's internal SEND counter.
  - Remaining validation:
    - The continuous probe currently repeats the first selected chunks, so full SHA-256 completion still requires restarting PC1 with the full sender profile.
    - Run the full `file_sender.py --decoys 1 --interval 0.10` proof and confirm PC2 reconstructs every allowed chunk while UDP/5002 and `FW-BLOCK` decoys do not leak.

- **B-2026-05-03-01: A-triggered W5500 B transmit does not reliably show the intended demo frames on PC2.**
  - Status: resolved for the final demo architecture. MACRAW A ingress is legacy diagnostic evidence; the accepted hardware path is W5500 A UDP sockets -> FPGA policy/signature stream processing -> W5500 B TX. User bench confirmation after round 22 showed the PC2 dashboard and Wireshark receiving forwarded packets.
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
  - 2026-05-04 round 3 (broadcast sender confirmed via tcpdump): all five SignalTap captures over a 30-second window show frozen counters `frames_ipv4=3, frames_ipv6=2, frames_udp_dport80=0, b_tx_count=3`. The exact 3+2 pattern reproduces on every fresh SOF flash, strongly suggesting the W5500 receives a fixed mDNS announce burst at every link-up event and goes silent afterwards.
  - 2026-05-04 round 4 RTL hardening (suspecting W5500-side state stall):
    - Added SHAR write to `02:00:00:DE:AD:0A` during RX adapter init (some W5500 firmware needs SHAR to be valid even in MACRAW with `MFEN=0`).
    - Added `S0_CR` clear poll after every `RECV` command (`ST_WAIT_RECV` state) so we don't read `RSR` while a command is in flight.
    - Mirrored SHAR write on the TX adapter (`02:00:00:DE:AD:0B`).
    - Hardware result: counters still frozen at exact same `3/2/0` numbers. SHAR + RECV-clear did not change behaviour.
  - 2026-05-04 round 5 RTL hardening (suspecting unhandled `Sn_IR.RECV` interrupt stall):
    - Extended `ST_WAIT_RECV` to also write `S0_IR=0xFF` after `RECV` clears, clearing every socket interrupt bit.
    - Hardware result: still the same `3/2/0` numbers. Sn_IR clear did not change behaviour either.
  - 2026-05-04 round 6 visibility (in-flight): added SignalTap probes `stp_last_rx_size`, `stp_last_frame_len`, `stp_rx_commit_count`, `stp_rx_stream_byte_count` to distinguish three remaining possibilities:
    - Chip reports `RSR=0` continuously after the initial burst -> chip-MAC-level RX is silent (PHY auto-neg quirk, unidirectional cable, or chip stuck).
    - Chip reports `RSR>0` but our adapter never processes -> RX adapter bug.
    - Adapter processes more frames than counters reflect -> probe wiring bug.
  - 2026-05-04 PC1-side verification (cable was PC1 -> W5500 A): `sudo tcpdump -i en0 -nn -e -c 5 udp port 80` captured **5 broadcast UDP/80 packets** with src MAC `1c:f6:4c:44:ff:46`, dst MAC `ff:ff:ff:ff:ff:ff`, dst port 80, payload 23 bytes (matches "FW-DEMO-ALLOW seq=N"). The Mac IS putting the demo on the wire heading into the W5500. Bug is not Mac-side.
  - 2026-05-04 round 7 RTL (PHY visibility): added `ST_READ_PHY` state and `phy_cfgr_value` / `phy_read_count` outputs from the RX adapter, plus matching `stp_phy_cfgr` / `stp_phy_read_count` SignalTap probes.
    - Capture shows `stp_phy_cfgr = 0xBF` -> `LNK=1, SPD=1 (100M), DPX=1 (full)`. The W5500 PHY is fully linked at 100 Mbps full-duplex. PHY-layer is not the issue.
    - Same capture revealed the smoking-gun anomaly: `rx_commit_count = 0x9F = 159` while `frames_ipv4 + frames_ipv6 = 2` and `rx_stream_byte_count = 0xC7 = 199`. So **157 of 159 commit cycles were "bad-length" discards**, only 2 were real frames. `last_frame_len = 0x3333` matches the first two bytes of an IPv6-multicast destination MAC (`33:33:XX:XX:XX:XX`), which means the adapter occasionally read **frame data** as if it were the W5500's 2-byte length prefix. Misalignment was being amplified by the discard logic flushing the entire RX buffer.
  - 2026-05-05 round 8 RTL fix (bounded discard): replaced "flush entire RX buffer on bad length" with `next_rx_read_ptr <= rx_read_ptr + min(rx_size_bytes, 1520)`. A single corrupted length header now costs at most one Ethernet frame's worth of buffer, instead of throwing away every valid frame queued behind it.
  - 2026-05-05 bench protocol change: every reflash power-cycles the W5500 PHY, which makes the Mac's `mDNSResponder` flood ~150 Bonjour announces in the first ~2 seconds. **Wait at least 30 seconds after reset/flash before triggering SignalTap** so the burst has settled; the demo at 2 pps will then dominate the rx_frame stream.
  - Topology confirmed (2026-05-05): PC1 and PC2 are connected directly to W5500 A and W5500 B respectively, with no shared switch or hub. Background broadcast traffic on the W5500 A cable comes only from the Mac's own kernel network stack (mDNS, NDP, ARP).
  - 2026-05-05 rounds 9-16 (MACRAW sender/config matrix):
    - MFEN-on (`S0_MR=0x84`) reduced garbage but did not admit multicast/broadcast demo UDP/80.
    - A-side SPI drain was raised from divider 50 to 8, then 4; this reduced some churn but did not make UDP/80 appear.
    - Added repeated-bad-length resync and last-IPv4 parser-field latches. Captures still showed only Mac-origin mDNS/Bonjour style IPv4 (`UDP/5353`) and no `UDP/80`.
    - Added `--allow-dst-ip/--dst-ip` to `scripts/rule_demo_sender.py` and fixed its stale destination-MAC help text.
    - Added `scripts/rule_demo_udp_socket_sender.py`, which uses a normal UDP socket plus static ARP so PC1 emits real unicast Ethernet frames to W5500 A's SHAR.
    - PC1 verified twice with `tcpdump`: `1c:f6:4c:44:ff:46 > 02:00:00:de:ad:0a`, IPv4, `192.168.1.10:4660 > 192.168.1.1:80`, 10/10 captured, zero kernel drops.
    - SignalTap still showed `frames_udp_dport80=0`, `frames_demo_match=0`; W5500 A continued to surface broadcast/multicast Mac background traffic but not the verified unicast UDP/80 demo packet.
  - 2026-05-05 rounds 17-19 (chip readback and final MACRAW falsification):
    - Added W5500 A readback probes for `S0_MR`, `SHAR`, and later `SIPR`; packed them into existing SignalTap columns to avoid another `.stp` node-list edit.
    - Round 17 readback with MFEN off proved `S0_MR=0x04`, `SHAR=02:00:00:DE:AD:0A`, `PHYCFGR=0xBF`.
    - Round 18 readback with MFEN on proved `S0_MR=0x84`, `SHAR=02:00:00:DE:AD:0A`, `PHYCFGR=0xBF`.
    - Round 19 additionally programmed/read back `SIPR=192.168.1.1` and `SUBR=255.255.255.0`; capture proved `S0_MR=0x84`, `SHAR=02:00:00:DE:AD:0A`, `SIPR=C0A80101`, `PHYCFGR=0xBF`.
    - Even with correct MAC, IP, PHY, and verified PC1 unicast UDP/80 on the wire, MACRAW A ingress still reported `frames_udp_dport80=0` and only surfaced mDNS/background frames.
  - Current conclusion:
    - W5500 MACRAW on A is not a reliable ingress mode for this project's PC1 demo packet on the current hardware/Mac direct-link setup.
    - The practical fix is W5500 A normal UDP socket receive mode for the rule-demo ingress. The FPGA synthesizes Ethernet/IP/UDP bytes internally and feeds the existing firewall/forwarder path.
    - Round 20 proved first-pass UDP mode reached `S0_MR=0x02` but had stale PHY visibility and no RX commits.
    - Round 21 added periodic PHY/status refresh and proved `S0_SR=0x22`, `PHYCFGR=0xBF`, but still no RX.
    - Round 22 added wait-for-link before opening socket 0 and succeeded: `frames_ipv4=frames_udp_dport80=frames_demo_match=0x74`, `b_tx_count=0x74`, `b_send_timeouts=0`, and A RX/B TX first bytes both `FFFFFFFFFFFF00112233445508004500`.
    - User bench confirmation after round 22: PC2 dashboard and Wireshark showed packets arriving from the UDP socket path. The remaining work is no longer "make MACRAW work"; it is to ship the UDP policy gateway framing and add FPGA-visible rule/signature features for the final demo.
    - 2026-05-05 final implementation direction: extended UDP socket ingress to ports 80, 5001, and 5002; added per-rule counters; added a small streaming payload matcher for `FWFILE1\0`, `FWSINE2\0`, `FW-BLOCK`, and `FW-DEMO-DROP`; and updated the demo scripts/dashboard/docs around the UDP policy gateway.
    - Hardware acceptance for the new image: PC2 sees allowed UDP/80 and UDP/5001; PC2 sees no UDP/5002 or content-blocked payloads; UART/SignalTap counters prove the blocked packets were classified and dropped inside the FPGA.

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
- 2026-05-04: Round-2 capture & fixes: fixed scripts/inspect_signaltap_csv.py trailing-X logic; added scripts/signaltap_capture_force.tcl and scripts/make_anytrig_stp.py (force/relaxed-capture helpers); defaulted scripts/rule_demo_sender.py to broadcast (192.168.1.255) to avoid macOS multicast routing; added SHAR writes and RECV S0_CR clear-poll in rtl/eth_if/ethernet_controller_adapter.v and mirrored SHAR in rtl/eth_if/w5500_macraw_tx_adapter.v; Questa regression passed for affected tests; Quartus full compile started; conclusion: FPGA pipeline forwards IPv4 end-to-end; remaining blocker is PC1-side delivery of demo UDP/80 (investigate macOS multicast, PF, or interface binding).
