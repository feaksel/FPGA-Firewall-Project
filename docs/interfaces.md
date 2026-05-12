# Interfaces

This page records the project boundaries that matter most when reading or
changing the RTL.

## Internal Frame Stream

The shared packet interface is a byte stream:

| Signal | Meaning |
| --- | --- |
| `frame_valid` | current byte is valid |
| `frame_data[7:0]` | current packet byte |
| `frame_sop` | first byte of a packet |
| `frame_eop` | last byte of a packet |
| `frame_ready` | downstream block can accept this byte |
| `frame_src_port` | source-side tag for future multi-port logic |

This interface is used by the simulation sources, the W5500 receive adapter,
the RX FIFO, the parser, and the forwarder. Keeping this boundary stable is what
lets the same policy logic run in simulation and on the real board path.

## Parser Output

`eth_ipv4_parser.v` extracts the fields needed by the simple firewall policy:

| Signal | Meaning |
| --- | --- |
| `hdr_valid` | parsed fields are available |
| `is_ipv4` | packet is Ethernet II IPv4 |
| `protocol[7:0]` | IPv4 protocol value |
| `src_ip[31:0]` | source IPv4 address |
| `dst_ip[31:0]` | destination IPv4 address |
| `src_port[15:0]` | TCP/UDP source port |
| `dst_port[15:0]` | TCP/UDP destination port |
| `parse_error` | unsupported or too-short packet |

Current parser assumptions:
- Ethernet II framing.
- IPv4 only.
- TCP and UDP port extraction.
- No IPv4 options in the MVP path.

## Rule Engine

Each rule contains:
- valid bit
- source IP and mask
- destination IP and mask
- protocol
- source port range
- destination port range
- allow/drop action

Conventions:
- first matching rule wins
- all-zero IP mask means wildcard
- protocol `8'h00` means wildcard
- no match means default drop

The main outputs are `decision_valid`, `action_allow`, and `matched_rule_id`.

## W5500 A Receive Boundary

The current final ingress path is `w5500_udp_rx_adapter.v`.

It opens and polls UDP services used by the demo:

| Socket profile | UDP port | Use |
| --- | --- | --- |
| service 0 | `80` | basic allow profile |
| service 1 | `5001` | file/waveform data |
| service 2 | `5002` | blocked decoy traffic |

The adapter synthesizes a normal Ethernet/IPv4/UDP-looking stream before handing
the packet to the policy path.

## W5500 B Transmit Boundary

The TX side receives allowed packet bytes, writes them into the W5500 B TX
buffer, updates the write pointer, and issues SEND.

The proof that this boundary worked is not only an FPGA counter. For acceptance,
PC2 must also see the forwarded UDP packet in Wireshark or one of the receiver
dashboards.

## Telemetry

The board and dashboards use these main counters:

| Counter | Meaning |
| --- | --- |
| `rx_count` | packets entering the policy path |
| `allow_count` | packets allowed by policy |
| `drop_count` | packets dropped by policy |
| `rule_allow80_count` | UDP/80 allow hits |
| `rule_allow5001_count` | UDP/5001 allow hits |
| `rule_drop5002_count` | UDP/5002 drop hits |
| `signature_block_count` | payload signature drops |
| `file_marker_count` | `FWFILE1\0` payload hits |
| `sine_marker_count` | `FWSINE2\0` payload hits |

Optional UART telemetry is transmit-only from FPGA to PC2 at `115200 8N1`.
