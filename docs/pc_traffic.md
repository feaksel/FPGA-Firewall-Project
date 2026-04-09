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

## Recommended sequence on bring-up day

1. Open Wireshark on the PC NIC connected to the W5500 side.
2. Generate ordinary traffic first with existing tools.
3. Once the adapter can read packets reliably, switch to deterministic Scapy-generated packets.
4. Compare each sent frame against the FPGA-observed behavior before trying higher traffic rates.
