# PC Traffic Strategy

## Goal

Use the connected PC as a controlled traffic source during bring-up without requiring a large custom application.

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

## Phase B: Deterministic raw packets

After SPI reads, initialization, and RX are stable, use [send_test_packets.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/send_test_packets.py).

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

## Phase D: Browser traffic dashboard

Use [traffic_dashboard.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/traffic_dashboard.py) for a visual view of deterministic test traffic:

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

## Phase E: Two-port file-transfer demo

The real inline-firewall demo target is:

```text
PC1 sender -> W5500 A -> FPGA rules/forwarder -> W5500 B -> PC2 receiver
```

PC1 sends allowed file chunks on UDP destination port `5001`, mixed with policy-blocked decoy/error frames such as TCP destination port `23`. PC2 reconstructs only the forwarded allowed chunks and verifies SHA-256.

Sender on PC1:

```powershell
py -3.9 .\scripts\file_sender.py --iface "Ethernet" --file .\demo.mp4
```

Receiver on PC2:

```powershell
py -3.9 .\scripts\file_receiver.py --iface "Ethernet" --output .\received_demo.mp4
```

The receiver script reports:
- chunk progress,
- missing chunks,
- reconstructed file size,
- expected and actual SHA-256,
- final pass/fail.

The video version is chunked file transfer, not live streaming. The intentionally dropped frames are decoy/error traffic, not required media chunks, so the received video should play if every allowed chunk arrives.

## Phase F: Continuous sine-wave demo

For the live presentation, use the continuous sine-wave demo before or beside the file-transfer proof.

Topology:

```text
PC1 sine sender -> W5500 A -> FPGA allow/drop -> W5500 B -> PC2 browser dashboard
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

The current default is tuned for consistency on the FPGA TX path: `1 Hz` sine, `200 Hz` sample rate, `16` samples per packet, and `5` allowed packets/sec. The sender saves `.sine_sender_state.json` by default, so stopping and restarting it continues the same run ID, sequence, and waveform phase. Use `--fresh-run` only when you intentionally want a new run.

Expected result:
- PC2 shows a continuously moving sine wave,
- allowed packet count increases,
- the packet strip shows green allowed arrivals and faded red expected decoy drops,
- packets/sec is nonzero,
- missing sequence count stays low,
- leak count stays `0`.

The **Restart dashboard** button clears the PC2-side view without restarting the sniffer process. Use it right before a recorded demo take or after changing sender settings. By default the dashboard locks onto the first `FWSINE2` run it sees and ignores older `FWSINE1` packets or packets from a different run ID. This prevents mixed sender processes from repeatedly resetting the waveform.

If the button is not visible, stop and restart the dashboard script once. The page is embedded in the running Python process, so browser refresh alone cannot load code changes made after the process started.

For the cleanest take, stop all old PC1 sender processes before starting a new one. On macOS/Linux:

```bash
pkill -f sine_sender.py
```

If you want to reset the continuous demo from sequence `0`, delete `.sine_sender_state.json` on PC1 or start the sender with `--fresh-run`.

The sender continuously interleaves blocked decoys:
- TCP destination port `23`
- UDP destination port `5002`

The allowed stream uses UDP destination port `5001`, matching the file-transfer allow rule.

If the sine wave is too dense or too slow, tune PC1:

```powershell
py -3.9 .\scripts\sine_sender.py --iface "Ethernet" --sine-hz 1 --packets-per-second 3 --samples-per-packet 16
```

Increase `--packets-per-second` gradually after the stable case works. W5500 B TX now uses burst TX-buffer writes in RTL, which removes the old byte-at-a-time payload-write bottleneck. The PC2 receiver can still show gaps if PC1 is sending multiple streams, if the sender rate is too high for the current full path, or if packet capture misses frames.

For presentation, keep one sender process active. Start at `5` packets/sec, then try `10`, `15`, and `20` packets/sec after the dashboard shows a clean run with `Leaks = 0`.

If the expected-drop markers do not line up, use the same `--decoy-every` value on both sides:

```powershell
py -3.9 .\scripts\sine_receiver_dashboard.py --iface "Ethernet" --decoy-every 4
py -3.9 .\scripts\sine_sender.py --iface "Ethernet" --decoy-every 4
```

## No-UART telemetry option

A USB-UART adapter is useful later, but it is not required for the next two-PC demo.

Without UART, use three evidence sources:
- PC1 sender counters from [file_sender.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/file_sender.py)
- PC2 receiver counters, missing-chunk report, and SHA-256 result from [file_receiver.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/file_receiver.py)
- FPGA board `HEX3..HEX0` and `LEDR` counters for RX/allow/drop state

Wireshark on PC2 is the backup proof:

```text
udp.port == 5001
```

Blocked decoys should be absent on PC2:

```text
tcp.port == 23
```

```text
frame contains "FW-DECOY-DROP"
```

This is enough for the first real enforcement demo. UART remains a later convenience for making the browser dashboard read FPGA counters directly.

## Recommended sequence on bring-up day

1. Open Wireshark on the PC NIC connected to the W5500 side.
2. Generate ordinary traffic first with existing tools.
3. Once the adapter can read packets reliably, switch to deterministic Scapy-generated packets.
4. Use either the terminal live viewer or the browser dashboard to watch the deterministic packets.
5. Compare each sent frame against the FPGA-observed behavior before trying higher traffic rates.

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
