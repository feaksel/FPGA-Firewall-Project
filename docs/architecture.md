# Architecture

The clean mental model for the current project is:

```text
W5500 A UDP socket RX
    -> synthesized Ethernet/IPv4/UDP frame stream
    -> parser and policy forwarder
    -> W5500 B TX buffer writer
    -> PC2
```

The FPGA still works on byte streams. The W5500 receives real Ethernet traffic,
but in the final hardware path it gives the FPGA UDP socket records instead of a
transparent raw Ethernet feed. The adapter rebuilds those records into a simple
internal frame format so the parser and policy logic can stay close to the
original firewall design.

## Main Blocks

`w5500_udp_rx_adapter.v` controls W5500 A. It resets the module, opens UDP
sockets, polls receive data, reads W5500 UDP records, and emits a byte stream
with SOP/EOP markers.

`firewall_forwarder.v` is the main policy datapath for the demo. It watches the
stream, saves header fields, matches UDP services, scans payload markers, counts
rules, and either forwards the packet or drops it.

`w5500_macraw_tx_adapter.v` controls W5500 B. It writes allowed packets into the
W5500 transmit buffer and issues SEND.

`eth_ipv4_parser.v`, `rule_engine.v`, `firewall_core.v`, `packet_buffer.v`, and
`frame_rx_fifo.v` are the reusable pieces from the original firewall design.
They are still useful for simulation, integration, and keeping the policy logic
separated from the Ethernet controller details.

## Policy Shape

The current demo policy is intentionally small:

| Traffic | Result | Purpose |
| --- | --- | --- |
| UDP destination port `80` | allow | basic service allow demo |
| UDP destination port `5001` | allow | file and waveform data path |
| UDP destination port `5002` | drop | visible blocked-service demo |
| payload contains `FW-BLOCK` or `FW-DEMO-DROP` | drop | content override demo |
| payload contains `FWFILE1\0` | count as file traffic | file-transfer visibility |
| payload contains `FWSINE2\0` | count as waveform traffic | live waveform visibility |

The hardware exposes aggregate allow/drop counts and per-rule counts through
HEX pages, SignalTap probes, and optional UART telemetry.

## Why UDP Socket Mode

The project originally tried to use W5500 MACRAW receive as a more transparent
Ethernet path. That work is archived because the bench evidence showed that the
verified PC1 demo packet did not reliably surface through A-side MACRAW in this
setup.

UDP socket mode is less general, but it is the path that worked repeatedly with
the available hardware. It still leaves the interesting FPGA work in hardware:
streaming packet reconstruction, header parsing, payload signature checks,
counter visibility, buffering, and allow/drop forwarding.

## What This Is Not

This design is not a full commercial firewall. It does not inspect arbitrary TCP
sessions, does not do bidirectional transparent bridging, and does not implement
reliable transport. Those would need either a true FPGA Ethernet MAC/PHY path or
a larger proxy-style architecture.

For this course project, the important result is a testable FPGA datapath that
enforces a small policy on real packets and proves the result on PC2.
