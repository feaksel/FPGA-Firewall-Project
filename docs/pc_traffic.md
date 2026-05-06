# PC Traffic Strategy

## Goal

Use the connected PC as a controlled traffic source during bring-up without requiring a large custom application.

## Current final demo path, 2026-05-05

The hardware demo now uses W5500 A in normal UDP-socket receive mode, not A-side MACRAW. Treat the raw Scapy/TCP phases below as legacy bring-up tools. The final presentation path is:

```text
PC1 normal UDP sender -> W5500 A UDP sockets -> FPGA policy/signature pipeline -> W5500 B MACRAW TX -> PC2 dashboard/Wireshark
```

Canonical profiles:
- UDP `80` allow (`FW-DEMO-ALLOW80`)
- UDP `5001` allow for file/sine/data (`FWFILE1` / `FWSINE2`)
- UDP `5002` drop (`FW-DEMO-DROP-UDP5002`)
- content signature drop (`FW-BLOCK`) even on an otherwise allowed UDP service

Start the PC2 dashboard:

```powershell
py -3.9 .\scripts\rule_demo_receiver_dashboard.py --iface "Ethernet" --uart COM7 --port 8091
```

Omit `--uart COM7` if FPGA UART is not connected; PC2 packet evidence will still work, but the histogram will not show live FPGA counters.

UART requires a separate 3.3 V TTL USB-UART adapter:

```text
DE1-SoC GPIO_0_D6 / GPIO_0[6]  ->  USB-UART RXD
DE1-SoC GND                    ->  USB-UART GND
```

Use `115200 8N1`, no flow control. Do not connect adapter `5V`, and do not use
RS-232 voltage levels. The dashboard's Live Result graph is time-based: it
samples every `0.5 s` over a rolling `30 s` window, so the x-axis keeps moving
even when no packets arrive.

Start the PC1 sender:

```bash
sudo python3 scripts/rule_demo_udp_socket_sender.py --iface en0 --rate 1 --verbose-each
```

Expected PC2 result: UDP `80` and `5001` packets arrive, UDP `5002` and `FW-BLOCK` payloads do not. Expected FPGA result: UART histogram counters `U80`, `U51`, `D52`, and `SIG` rise.

## Phase A: Standard tools first

Use existing tools to prove link activity and packet arrival:
- Wireshark for capture
- `ping` for simple ICMP traffic
- `netcat` or `ncat` for TCP or UDP traffic
- `iperf` for repeated traffic once basic reception is stable

This phase is for confirming:
- packet arrival at the W5500
- frame-length reads
- visible packet bytes in debug
- basic counter movement in the FPGA

## Phase B: Legacy deterministic raw packets

After SPI reads, initialization, and RX are stable, use [send_test_packets.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/send_test_packets.py) only for simulation-shaped/raw-packet diagnostics.

That script generates exact frames matching the simulation intent:
- `udp_allow`
- `tcp_drop`
- `tcp_allow_ssh`

Use it to compare:
- Wireshark capture contents
- parsed firewall fields
- allow/drop counter results

## Phase C: Live PC-side view

Use [live_traffic_view.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/live_traffic_view.py) to watch deterministic test packets as they appear on the PC interface:

```powershell
py -3.9 .\scripts\live_traffic_view.py --iface "Ethernet"
```

In another terminal, send test packets:

```powershell
py -3.9 .\scripts\send_test_packets.py --iface "Ethernet" --packet udp_allow --count 3 --interval 0.25
py -3.9 .\scripts\send_test_packets.py --iface "Ethernet" --packet tcp_drop --count 3 --interval 0.25
py -3.9 .\scripts\send_test_packets.py --iface "Ethernet" --packet tcp_allow_ssh --count 3 --interval 0.25
```

The live viewer is PC-side evidence only. The FPGA decision evidence is still the board LEDs and `HEX3..HEX0` debug pages.

## Phase D: Legacy browser traffic dashboard

Use [traffic_dashboard.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/traffic_dashboard.py) for old one-PC deterministic raw traffic tests:

```powershell
py -3.9 .\scripts\traffic_dashboard.py --iface "Ethernet" --port 8080
```

Then open:

```text
http://127.0.0.1:8080
```

The dashboard provides:
- buttons to send `udp_allow`, `tcp_drop`, and `tcp_allow_ssh`,
- per-profile sent counts,
- per-profile PC-captured counts,
- a missing/not-yet-captured count,
- background-frame activity,
- a recent event timeline.
- a compact packet-flow visualization with recent event bars,
- a toggleable board-display manual for `SW[3:1]`, `HEX3..HEX0`, rule IDs, LED meanings, and test flow.

For the current one-port setup, the dashboard can only compare what the PC sent and captured on its own interface. It cannot directly read the FPGA's internal allow/drop counters yet. Use the board `HEX3..HEX0` pages as the FPGA-side truth.

The dashboard now also includes a two-port file-demo preview panel. It is a UX placeholder until the FPGA can transmit on W5500 B and stream UART telemetry.

## Phase E: Two-port UDP file-transfer demo

The real inline-firewall demo target is:

```text
PC1 sender -> W5500 A -> FPGA rules/forwarder -> W5500 B -> PC2 receiver
```

PC1 sends allowed file chunks on UDP destination port `5001`, mixed with policy-blocked UDP `5002` and `FW-BLOCK` decoys. PC2 reconstructs only the forwarded allowed chunks and verifies SHA-256.

Sender on PC1:

```powershell
py -3.9 .\scripts\file_sender.py --iface "Ethernet" --file .\demo.mp4
```

The sender default is `--chunk-size 256`. Keep that default for the live demo.
The file-demo payload has a 50-byte `FWFILE1` header, and the FPGA creates a
42-byte Ethernet/IP/UDP wrapper before policy forwarding. A 512-byte file chunk
therefore becomes a 604-byte internal frame. On any image/path still limited to
512-byte frames, those full chunks are committed/dropped before the rule engine
and only the final short chunk reaches PC2. If you override the chunk size on a
conservative image, stay at `--chunk-size 420` or smaller.

The sender default interval is now `0.10 s` per datagram. The earlier `0.01 s`
setting can overrun the two-W5500 path during full file+decoy transfers. Use a
two-stage test:

```bash
sudo python3 scripts/file_sender.py --iface en0 --file demo.mp4 --decoys 0 --limit-chunks 4 --interval 0.10
```

Expected: PC2 shows four chunks and no leaks. SHA will not pass because this is
only an allow-path probe.

For SignalTap or UART debugging, keep the same probe alive continuously:

```bash
sudo python3 scripts/file_sender.py --iface en0 --file demo.mp4 --decoys 0 --limit-chunks 4 --interval 0.10 --repeat 0
```

No-UART hardware check:

Use normal mode first: `SW0=1`, `SW5=0`, `SW7=0`, `SW8=0`, `SW9=0`.

| `SW[3:1]` | `HEX3..HEX0` | Expected during continuous 4-chunk probe |
| --- | --- | --- |
| `001` | `rx_count[15:0]` | rises if packets reach parser/forwarder |
| `010` | `allow_count[15:0]` | rises for UDP/5001 allow |
| `011` | `drop_count[15:0]` | stays flat for `--decoys 0` |
| `101` | `tx_count_b[15:0]` | rises if W5500 B SEND completes |
| `110` | last A RX size | `013A` for default file chunks |
| `111` | last synthesized frame length | `015C` for default file chunks |

If all normal-mode counters stay flat, switch briefly to A-ingress drain mode:
`SW5=1`, `SW9=0`. This disables forwarding, so PC2 will not receive packets;
use it only to prove W5500 A/socket 1 ingress.

| `SW[3:1]` | `HEX3..HEX0` | Expected |
| --- | --- | --- |
| `001` | A streamed byte count | rises if A streams packet bytes |
| `010` | A RX commit count | rises if socket packets are committed |
| `011` | last RX size | `013A` |
| `100` | last frame length | `015C` |

Interpretation:
- A-ingress drain counts stay flat: socket 1/UDP5001 is not receiving or not being polled.
- A-ingress rises but normal `rx_count` stays flat: FIFO/forwarder ingress issue.
- Normal `rx_count` and `allow_count` rise but `tx_count_b` stays flat: B TX handoff/SEND issue.
- `tx_count_b` rises but PC2 sees nothing: PC2 interface/filter/cable or W5500-B PHY side.

Then run the full proof:

```bash
sudo python3 scripts/file_sender.py --iface en0 --file demo.mp4 --decoys 1 --interval 0.10
```

Expected: PC2 reconstructs the full file, SHA-256 passes, and UDP/5002 /
`FW-BLOCK` decoys do not leak.

Receiver on PC2:

```powershell
py -3.9 .\scripts\file_receiver.py --iface "Ethernet" --output .\received_demo.mp4 --port 8092
```

Open:

```text
http://127.0.0.1:8092
```

The receiver dashboard reports:
- chunk progress,
- a live chunk-map visualization,
- missing chunks,
- decoy/content-block leaks,
- reconstructed file size,
- expected and actual SHA-256,
- final pass/fail,
- and a browser preview for completed image/video/audio/text files when the MIME type is supported.

The video version is chunked file transfer, not live streaming. The intentionally dropped frames are decoy/error traffic, not required media chunks, so the received video should play if every allowed chunk arrives.

## Phase F: Continuous payload-waveform demo

For the live presentation, use the continuous payload-waveform demo before or beside the file-transfer proof.

## Phase F0: Simple continuous rule demo

Use this demo first when hardware bring-up feels confusing. It avoids waveform/state complexity and is intended to prove packet forwarding plus rule enforcement.

Current status, 2026-05-05:
- The PC1 -> W5500 A UDP socket -> FPGA -> W5500 B -> PC2 path is proven.
- The demo has been reframed as a UDP policy gateway, not a transparent TCP/L2 firewall.
- The current work adds three W5500 A UDP services, per-rule FPGA counters, and payload signature blocking.

Topology:

```text
PC1 rule sender -> W5500 A -> FPGA allow/drop -> W5500 B -> PC2 rule dashboard
```

Start PC2 first:

```powershell
py -3.9 .\scripts\rule_demo_receiver_dashboard.py --iface "Ethernet" --port 8091
```

If the page stays empty, stop the Python process and list the exact Scapy/Npcap names:

```powershell
py -3.9 .\scripts\rule_demo_receiver_dashboard.py --list-ifaces
```

Then restart with the matching interface. The dashboard includes `All frames seen` and `Demo frames seen` counters. If `All frames seen` remains `0`, the dashboard is sniffing the wrong Windows interface. If `All frames seen` rises but `Demo frames seen` stays `0`, the interface is right but forwarded demo packets are not arriving.

Open:

```text
http://127.0.0.1:8091
```

Start PC1:

```bash
sudo python3 scripts/rule_demo_udp_socket_sender.py --iface enX --rate 1 --verbose-each
```

The sender defaults are intentionally conservative for hardware reliability. It sends UDP/80 allow, UDP/5001 allow, UDP/5002 drop, and a `FW-BLOCK` content drop. It uses normal UDP sockets plus static ARP to the W5500 A IP/MAC.

Expected result:
- `UDP allow received` increases because UDP destination port `80` from `192.168.1.10` is forwarded.
- `UDP/5001` received increases because the data/file service is forwarded.
- The FPGA UART histogram shows `D52` and `SIG` increasing for dropped profiles.
- `Drop leaks` stays `0`.
- FPGA `SW[3:1]=001` RX count, `010` allow count, `011` drop count should increase while the sender runs.

If using the latest debug FPGA image, use these switch modes:

- `SW5=1`: raw W5500 A ingress drain. This disables forwarding and proves PC1 -> W5500 A -> FPGA RX.
- `SW6=1`: direct W5500 B self-test. This ignores PC1 and periodically sends a known-good `FW-DEMO-ALLOW-SSH` frame to PC2.
- `SW7=1`: raw A-to-B bypass. SignalTap plus `sw7-0004.pcapng` prove this can forward at least some real Mac-origin multicast frames; the rule-demo marker path still needs a clean real-MAC retest.
- `SW8=1`: generated rule-demo mode. This should use A-side allowed/drop packets as triggers and send a known-good B-side allow frame, but the latest hardware result was `SW[3:1]=101 = 0000`, so it still needs debugging.

Only one of `SW5`, `SW6`, `SW7`, and `SW8` should be enabled during a test.

For the final UDP policy gateway demo, use the socket sender instead of the
legacy raw Scapy sender:

```bash
python3 scripts/rule_demo_udp_socket_sender.py --iface enX --rate 1 --verbose-each
```

Use `scripts/rule_demo_sender.py` only when intentionally reproducing older
MACRAW/raw-Ethernet diagnostics.

If forwarding works briefly and then appears to stop, treat that as an overrun/recovery case first: stop PC1 sender, reset/start the FPGA with `SW5=0`, restart the PC2 dashboard, and run the safe default sender again. Use `SW5=1` only for raw ingress-drain debugging; it intentionally disables forwarding to PC2.

If `SW[3:1]=001` stays stuck, the FPGA is not seeing new ingress packets on W5500 A. Recheck that PC1 is sending on the Mac Ethernet interface connected to W5500 A, `SW0` is high/start-init, `LEDR0=1`, and `LEDR1=0`.

Hardware debug shortcut: set `SW5=1` and `SW[3:1]=001`. In this mode, `HEX3..HEX0` shows a raw W5500 A ingress-drain count, independent of the firewall forwarder and W5500 B TX path. If this raw count increases, PC1 -> W5500 A is alive and the issue is downstream. Set `SW5=0` for normal firewall forwarding/counting.

Current known capture interpretation:
- If PC2 capture contains `FW-DEMO-ALLOW-SSH` or `FW-DEMO-DROP-TCP23`, PC2 is seeing the demo frames. `DROP` markers should not appear during enforced forwarding.
- If PC2 capture contains the Mac's real source MAC, such as `1c:f6:4c:44:ff:46`, the raw SW7 path is forwarding at least some PC1-origin traffic.
- If PC2 capture only contains the Windows NIC source MAC and multicast destinations, the dashboard is mostly seeing PC2 background traffic.
- If board `SW[3:1]=101` rises while PC2 sees no demo frames, the FPGA/W5500 control path believes TX completed but the emitted frame is not visible or not valid. This is not proof of forwarding.

Use this helper for a quick capture summary:

```powershell
py -3 .\scripts\pcap_summary.py C:\Users\furka\Desktop\capture.pcapng
```

Topology:

```text
PC1 sample sender -> W5500 A -> FPGA allow/drop -> W5500 B -> PC2 browser dashboard
```

Start PC2 first:

```powershell
py -3.9 .\scripts\sine_receiver_dashboard.py --iface "Ethernet" --port 8090
```

Open:

```text
http://127.0.0.1:8090
```

Start PC1:

```powershell
py -3.9 .\scripts\sine_sender.py --iface "Ethernet"
```

The current default is tuned for consistency on the FPGA TX path: `1 Hz` sine-shaped sample values, `16` samples per packet, and `5` allowed packets/sec. The sender derives the default payload sample rate from the actual outgoing sample cadence, so the default is `80 Hz`. The sender saves `.sine_sender_state.json` by default, so stopping and restarting it continues the same run ID, sequence, and waveform phase. Use `--fresh-run` only when you intentionally want a new run.

Expected result:
- PC2 shows received signed int16 payload samples as dots on a continuously moving time axis,
- allowed packet count increases,
- the packet strip shows green allowed arrivals and faded red expected decoy drops,
- packets/sec is nonzero,
- missing sequence count stays low,
- leak count stays `0`.

The waveform graph is intentionally point-based rather than line-connected. If an
allowed packet is missed, that time interval has no dots. When packets resume,
new dots appear at their later reconstructed stream time, so gaps stay visible
instead of being hidden by a line drawn across the missing samples.

This dashboard is not locally drawing a sine function. It plots only the signed
16-bit values carried by received UDP/5001 payloads. The sender can therefore
produce different shapes without changing the receiver:

```bash
sudo python3 scripts/sine_sender.py --iface enX --wave sine --wave-hz 1 --packets-per-second 5
sudo python3 scripts/sine_sender.py --iface enX --wave square --wave-hz 1 --packets-per-second 5
sudo python3 scripts/sine_sender.py --iface enX --wave triangle --wave-hz 1 --packets-per-second 5
sudo python3 scripts/sine_sender.py --iface enX --wave saw --wave-hz 1 --packets-per-second 5
sudo python3 scripts/sine_sender.py --iface enX --wave step --wave-hz 1 --packets-per-second 5
sudo python3 scripts/sine_sender.py --iface enX --wave values --values "-28000 -28000 28000 28000 0 12000 24000 12000" --packets-per-second 5
sudo python3 scripts/sine_sender.py --iface enX --wave text --text "FPGA UDP" --sample-rate 210 --samples-per-packet 21 --packets-per-second 10
```

`--wave values` repeats the literal int16 sequence from `--values` or
`--values-file`, so the demo can send arbitrary sample streams. `--wave text`
encodes a 5x7 message as sample positions on the same value graph; it is still
just signed int16 payload data, not a special receiver drawing mode. A later
hardware threshold rule can scan these payload bytes before forwarding and drop
packets containing samples above a configured value. In the browser this would
show as real missing packet intervals, not a dashboard-side visual trick.

The receiver's default `--time-mode arrival` uses real packet arrival cadence
for the x-axis. One vertical grid column is one second, so a sample dot takes
exactly one wall-clock second to move by one grid column. `--time-mode payload`
is available for debugging payload metadata, but the live demo should use the
default arrival mode because it stays visually correct even when packet rate and
declared sample rate are not perfectly matched.

The **Restart dashboard** button clears the PC2-side view without restarting the sniffer process. Use it right before a recorded demo take or after changing sender settings. By default the dashboard locks onto the first `FWSINE2` run it sees and ignores older `FWSINE1` packets or packets from a different run ID. This prevents mixed sender processes from repeatedly resetting the waveform.

If the button is not visible, stop and restart the dashboard script once. The page is embedded in the running Python process, so browser refresh alone cannot load code changes made after the process started.

For the cleanest take, stop all old PC1 sender processes before starting a new one. On macOS/Linux:

```bash
pkill -f sine_sender.py
```

If you want to reset the continuous demo from sequence `0`, delete `.sine_sender_state.json` on PC1 or start the sender with `--fresh-run`.

For a presentation where old sender processes may still be on the network, hard-lock the receiver and sender to one run ID:

```powershell
py -3.9 .\scripts\sine_receiver_dashboard.py --iface "Ethernet" --port 8090 --lock-run-id 0x4321
```

```bash
sudo python3 scripts/sine_sender.py --iface enX --run-id 0x4321 --wave sine --wave-hz 1 --packets-per-second 5 --samples-per-packet 16
```

With `--lock-run-id`, the dashboard ignores every other stream, including old `FWSINE1` packets and accidental extra senders.

The sender continuously interleaves blocked decoys:
- TCP destination port `23`
- UDP destination port `5002`

The allowed stream uses UDP destination port `5001`, matching the file-transfer allow rule.

If the waveform is too dense or too slow, tune PC1:

```powershell
py -3.9 .\scripts\sine_sender.py --iface "Ethernet" --wave sine --wave-hz 1 --packets-per-second 3 --samples-per-packet 16
```

Increase `--packets-per-second` gradually after the stable case works. W5500 B TX now uses burst TX-buffer writes in RTL, which removes the old byte-at-a-time payload-write bottleneck. The PC2 receiver can still show gaps if PC1 is sending multiple streams, if the sender rate is too high for the current full path, or if packet capture misses frames.

For presentation, keep one sender process active. Start at `5` packets/sec, then try `10`, `15`, and `20` packets/sec after the dashboard shows a clean run with `Leaks = 0`.

If the expected-drop markers do not line up, use the same `--decoy-every` value on both sides:

```powershell
py -3.9 .\scripts\sine_receiver_dashboard.py --iface "Ethernet" --decoy-every 4
py -3.9 .\scripts\sine_sender.py --iface "Ethernet" --decoy-every 4
```

## No-UART telemetry option

A USB-UART adapter is useful for the final rule histogram, but it is not
required for packet-only proof.

Without UART, use three evidence sources:
- PC1 sender counters from [file_sender.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/file_sender.py)
- PC2 receiver counters, missing-chunk report, and SHA-256 result from [file_receiver.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/file_receiver.py)
- FPGA board `HEX3..HEX0` and `LEDR` counters for RX/allow/drop state
- SignalTap over USB-Blaster for internal W5500/socket/forwarder counters

Wireshark on PC2 is the backup proof:

```text
udp.port == 5001
```

Blocked decoys should be absent on PC2:

```text
udp.port == 5002
```

```text
frame contains "FW-BLOCK" || frame contains "FW-DEMO-DROP"
```

This is enough for a packet-visible enforcement demo. Without UART, SignalTap is
the FPGA-side proof that UDP/5002 and content-blocked packets were classified
and dropped inside the FPGA:

```powershell
cd C:\Users\furka\Projects\ELE432_ethernet
& 'C:\altera_lite\25.1std\quartus\bin64\quartus_stp.exe' `
  -t scripts\signaltap_capture_force.tcl `
  quartus\de1_soc_w5500.stp `
  captures\stp\file_probe_no_uart.csv 5
py -3 scripts\inspect_signaltap_csv.py captures\stp\file_probe_no_uart.csv
```

The currently-fitted `.stp` already includes the essential no-UART debug nodes:
`stp_last_rx_size`, `stp_last_frame_len`, `stp_rx_commit_count`,
`stp_rx_stream_byte_count`, `stp_phy_cfgr`, and the B TX counters. If the newer
`stp_rule_*` counters are added in the SignalTap GUI, rebuild Quartus and flash
that matching SOF before capturing; SignalTap node membership is baked into the
compiled image.

## Recommended sequence on bring-up day

1. Open Wireshark on the PC NIC connected to the W5500 side.
2. Generate ordinary traffic first with existing tools.
3. Once the adapter can read packets reliably, switch to deterministic Scapy-generated packets.
4. Use either the terminal live viewer or the browser dashboard to watch the deterministic packets.
5. Compare each sent frame against the FPGA-observed behavior before trying higher traffic rates.

## Current script map

- [rule_demo_udp_socket_sender.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/rule_demo_udp_socket_sender.py): canonical PC1 final-demo sender. Uses normal UDP sockets plus static ARP and cycles through UDP/80 allow, UDP/5001 allow, UDP/5002 drop, and content-block payload profiles.
- [rule_demo_receiver_dashboard.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/rule_demo_receiver_dashboard.py): PC2 dashboard for allowed packets, blocked-packet leak warnings, FPGA UART histograms, and `.pcapng` inspection with `--pcap`.
- [file_sender.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/file_sender.py) and [file_receiver.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/file_receiver.py): chunked UDP/5001 file proof with visual browser dashboard, SHA-256 verification, completed-file preview, and interleaved decoys.
- [sine_sender.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/sine_sender.py) and [sine_receiver_dashboard.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/sine_receiver_dashboard.py): live UDP/5001 payload-sample visualization with sine/square/triangle/saw/step/noise/custom-value/text modes, wall-clock sample dots, visible drop gaps, UDP/5002 decoys, and content-block decoys.
- [pcap_summary.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/pcap_summary.py): current pcap summary tool for UDP gateway markers.
- [inspect_capture.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/inspect_capture.py): older quick pcap summary tool retained for bring-up/debug captures.
- [rule_demo_sender.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/rule_demo_sender.py): legacy raw-Ethernet/MACRAW diagnostic sender. It is not the final hardware demo path.

## 2026-05-01 observed result

The first physical DE1-SoC + W5500 receive test used the Windows interface named `Ethernet`.

Confirmed in `wiresharkcapture.pcapng`:
- 3 `udp_allow` packets
- 3 `tcp_drop` packets
- 3 `tcp_allow_ssh` packets
- source MAC `00:11:22:33:44:55`
- payload markers:
  - `FW-UDP-ALLOW`
  - `FW-TCP-DROP`
  - `FW-TCP-ALLOW-SSH`

Useful Wireshark filters:

```text
eth.src == 00:11:22:33:44:55
```

```text
frame contains "FW-"
```

Background traffic note:
- Windows sends multicast and broadcast traffic even when the Scapy sender is idle.
- The W5500 can receive that background traffic, so board receive/debug LEDs may continue changing between explicit test sends.
