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
- an embedded board-display manual for `SW[3:1]`, `HEX3..HEX0`, rule IDs, and LED meanings.

For the current one-port setup, the dashboard can only compare what the PC sent and captured on its own interface. It cannot directly read the FPGA's internal allow/drop counters yet. Use the board `HEX3..HEX0` pages as the FPGA-side truth.

For a future two-port setup, the same dashboard concept should expand to show:
- ingress-port packets,
- FPGA firewall decisions,
- egress-port packets,
- dropped/lost/error packets,
- throughput over time.

That future version needs either two PC Ethernet interfaces, two PCs, or a telemetry path from the FPGA such as UART, JTAG debug, HPS bridge, or Ethernet TX.

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
