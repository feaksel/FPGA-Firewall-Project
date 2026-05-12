# RTL Guide

This page explains the Verilog code in `rtl/` in a way that is meant for
learning the project, not just finding a filename. It also marks which modules
are part of the current demo and which ones are older diagnostic pieces.

## Status Key

| Status | Meaning |
| --- | --- |
| Current | Used in the final UDP policy gateway demo path. |
| Reusable | Still useful and tested, but not always directly on the final board path. |
| Debug/support | Helps visibility, display, telemetry, or low-level communication. |
| Legacy/diagnostic | Kept because it was important during bring-up, but not the final demo architecture. |

The current final hardware path is:

```text
de1_soc_w5500_top
  -> w5500_udp_rx_adapter
  -> frame_rx_fifo
  -> firewall_forwarder
  -> w5500_macraw_tx_adapter
```

That path receives UDP socket data from W5500 A, rebuilds a packet-like byte
stream, applies policy, and sends allowed packets through W5500 B.

## Top-Level Modules

### `rtl/top/de1_soc_w5500_top.v`

Status: current.

This is the real DE1-SoC board wrapper. If you want to understand what the FPGA
image actually does on the board, start here after reading the architecture
page.

It connects:
- `CLOCK_50`, `KEY`, `SW`, `LEDR`, and `HEX` board I/O
- W5500 A pins on `GPIO_0`
- W5500 B pins on `GPIO_1`
- optional UART telemetry on `GPIO_0[6]`
- SignalTap debug registers
- the current UDP receive, policy, and transmit modules

The important instantiated modules are:
- `firewall_telemetry_uart`
- `w5500_udp_rx_adapter`
- `frame_rx_fifo`
- `firewall_forwarder`
- `w5500_macraw_tx_adapter`

Why it is large:
- it has the final datapath
- it has board display logic
- it has debug modes controlled by switches
- it keeps preserved SignalTap probe registers
- it still contains old bench modes used to isolate W5500 A and W5500 B issues

Useful switches:
- `SW0` starts/enables initialization.
- `SW5` is raw W5500 A drain/debug mode.
- `SW6` sends a known-good generated test frame from W5500 B.
- `SW7` is legacy raw A-to-B bypass.
- `SW8` is legacy generated rule-demo mode.
- `SW9` changes the HEX/LED display into byte/state debug pages.

Learning note: do not read this file top-to-bottom first. Read the smaller
modules below, then come back to this file to see how they are wired together.

### `rtl/top/firewall_top.v`

Status: reusable, but not the final board demo path.

This is an older, cleaner integration wrapper:

```text
ethernet_controller_adapter -> optional frame_rx_fifo -> firewall_core
```

It was useful when the project was focused on receive-side inspection rather
than two-W5500 forwarding. It is still a good learning file because it shows the
original separation between "Ethernet controller adapter" and "firewall core"
without all the board/debug complexity of `de1_soc_w5500_top.v`.

Why it is not the final demo path:
- it uses the older `ethernet_controller_adapter`
- it only reaches `firewall_core` counters
- it does not include the current UDP socket receive plus B-side forwarding
  pipeline

Keep it because it is simple, testable, and documents the original architecture.

## W5500 and SPI Modules

### `rtl/spi/spi_master.v`

Status: current debug/support.

This is the low-level SPI byte shifter used by the W5500 adapters. It handles:
- SPI clock division
- chip select
- MOSI bit shifting
- MISO sampling
- `busy` and `done` handshakes
- optional held chip-select across multi-byte transfers

The W5500 register protocol is built on top of this module. The SPI master does
not know about W5500 registers, sockets, packets, or policy. It only sends and
receives bytes.

Learning value:
- good example of a small synchronous FSM
- useful for understanding clock division and serial protocols
- much easier to test than the full W5500 adapter

### `rtl/eth_if/w5500_udp_rx_adapter.v`

Status: current.

This is the active W5500 A receive module for the final demo. It uses W5500 UDP
socket mode instead of MACRAW receive.

Its job is:
1. reset W5500 A
2. read the `VERSIONR` register as a sanity check
3. configure common W5500 network registers
4. open UDP sockets for the demo services
5. poll socket receive sizes
6. read W5500 UDP records
7. synthesize an internal Ethernet/IPv4/UDP byte stream
8. emit that stream using `frame_valid`, `frame_data`, `frame_sop`, `frame_eop`,
   and `frame_ready`
9. commit the W5500 receive pointer with `RECV`

The demo sockets are:

| UDP port | Use |
| --- | --- |
| `80` | simple allow service |
| `5001` | file, media, waveform data |
| `5002` | blocked decoy service |

The W5500 UDP receive buffer gives the FPGA a UDP record rather than a raw
Ethernet frame. The adapter therefore creates a 42-byte Ethernet/IPv4/UDP header
before the payload. That lets the parser and policy logic work on a normal
packet-shaped byte stream.

Important state-machine ideas:
- reset delays are long in hardware, short in simulation
- `ST_VERSION` proves SPI and the W5500 are alive
- `ST_SOCKET_OPEN` prepares the UDP services
- `ST_WAIT_LINK` avoids reading before PHY link is usable
- `ST_RX_POLL` checks whether a socket has data
- `ST_READ_UDP_HDR` reads peer IP, peer port, and payload length
- `ST_STREAM_FRAME` emits synthesized header bytes and payload bytes
- `ST_COMMIT_RX` tells the W5500 that the packet was consumed

What it is not:
- not a full Ethernet MAC
- not a transparent bridge
- not a TCP receiver
- not a raw frame sniffer in the final demo

Why this exists:
the older A-side MACRAW receive path did not reliably surface the verified PC1
demo packet on the bench. UDP socket mode was the reliable W5500 ingress path.

### `rtl/eth_if/w5500_macraw_tx_adapter.v`

Status: current, despite the name.

This module is used for W5500 B transmit in the final demo. The name contains
`macraw` because W5500 B is used to emit packet bytes through a MACRAW-style
socket. That does not make the module obsolete.

Its job is:
1. reset W5500 B
2. read `VERSIONR`
3. configure W5500 B common registers
4. open a transmit-capable socket
5. wait for a complete packet from the FPGA
6. read free TX buffer size
7. read the TX write pointer
8. write packet bytes into the W5500 TX buffer
9. update the TX write pointer
10. issue SEND
11. count successful sends or timeouts

The module receives the same stream style used elsewhere:
- `frame_valid`
- `frame_data`
- `frame_sop`
- `frame_eop`
- `frame_ready`

Important debug outputs:
- `tx_count`
- `tx_error`
- `last_pkt_len_dbg`
- `buf_write_start_count`
- `send_issued_count`
- `send_cleared_count`
- `send_timeout_count`

Learning note: this is one of the most useful files for understanding how a
hardware stream becomes a W5500-transmitted packet.

### `rtl/eth_if/w5500_tx_engine.v`

Status: reusable / partly superseded by the integrated TX adapter.

This is a smaller TX-buffer writer and SEND engine. It focuses on the transmit
sequence:

```text
read TX free size -> read write pointer -> write bytes -> update pointer -> SEND
```

It is useful for testing and for understanding the W5500 transmit mechanics in a
smaller file than `w5500_macraw_tx_adapter.v`.

Why it is not the main final top-level TX module:
- the board path currently uses `w5500_macraw_tx_adapter.v`
- this module is more of a focused engine/test component

Keep it because it has a dedicated testbench and isolates W5500 TX behavior.

### `rtl/eth_if/ethernet_controller_adapter.v`

Status: legacy/diagnostic.

This was the older W5500 A MACRAW receive adapter. It resets the W5500, opens a
MACRAW receive socket, reads received frame lengths, streams frame bytes, and
commits receive data.

Why it became legacy:
- the final bench evidence showed W5500 A MACRAW receive did not reliably show
  the verified PC1 demo packet
- the accepted final ingress path moved to `w5500_udp_rx_adapter.v`
- this module is still useful for old tests and for understanding the MACRAW
  attempt

Do not use this file as the main explanation of the final demo. It explains the
older architecture and the debugging path that led to the UDP socket pivot.

## Firewall and Policy Modules

### `rtl/firewall/firewall_forwarder.v`

Status: current.

This is the main policy module in the final demo.

It combines four ideas:
1. store the full packet in `packet_buffer`
2. parse the header with `eth_ipv4_parser`
3. classify it with `rule_engine`
4. scan payload bytes for demo signatures

Then it decides:
- replay the packet to W5500 B if allowed
- discard the packet if blocked

Current policy counters include:
- aggregate receive count
- aggregate allow count
- aggregate drop count
- UDP/80 allow count
- UDP/5001 allow count
- UDP/5002 drop count
- content-block count
- default-drop count
- file marker count
- sine marker count

Important payload markers:

| Marker | Meaning |
| --- | --- |
| `FW-BLOCK` | content-block override |
| `FW-DEMO-DROP` | content-block/drop marker |
| `FWFILE1\0` | file/media/webcam payload marker |
| `FWSINE2\0` | waveform payload marker |

Why a packet buffer is needed:
the module must decide allow/drop after seeing enough header and payload bytes.
If the packet is allowed, it has to replay the packet from the beginning. That
requires saving the packet while the decision is being made.

Important historical bug:
the file demo exposed why byte counters must be wide enough. A file packet
longer than 255 bytes wrapped an 8-bit index and corrupted saved header state.
The forwarder now uses 16-bit packet indices for the longer UDP/5001 frames.

Learning value:
- shows how parsing, buffering, policy, and replay fit together
- shows the difference between streaming inspection and store-then-forward
- shows why debug counters matter in hardware

### `rtl/firewall/firewall_core.v`

Status: reusable / original core.

This is the original simpler firewall core:

```text
byte stream -> eth_ipv4_parser -> rule_engine -> debug_counters
```

It always accepts input (`in_ready = 1`) and only produces counters/last-decision
signals. It does not forward packets to W5500 B.

Why it still matters:
- it is the cleanest example of parser plus rule-engine integration
- it is easier to test than the full forwarder
- it explains the original receive/inspect MVP before the project grew into a
  two-W5500 policy gateway

Why it is not enough for the final demo:
- it cannot replay allowed packets
- it cannot block by preventing TX
- it does not scan payload signatures
- it does not drive W5500 B

### `rtl/parser/eth_ipv4_parser.v`

Status: current reusable core.

This parser watches a packet byte stream and extracts the fields needed by the
rule engine:
- EtherType
- IPv4 protocol
- source IP
- destination IP
- source port
- destination port

It assumes:
- Ethernet II
- IPv4
- TCP or UDP
- no IPv4 options in the MVP path

The parser does not decide allow/drop. It only turns bytes into header fields.

Learning value:
- good example of byte-index-based packet parsing
- shows how network byte order becomes Verilog registers
- keeps parsing separate from policy

Limitations:
- IPv4 options are not supported
- ARP/ICMP are outside the policy demo path
- it is not a general packet parser for every Ethernet frame type

### `rtl/rules/rule_engine.v`

Status: current reusable core.

This module receives parsed header fields and chooses the first matching rule.
It outputs:
- `decision_valid`
- `action_allow`
- `matched_rule_id`

The current parameter rules include:
- UDP/80 allow
- TCP/23 drop from the older firewall demo
- TCP/22 allow from the older firewall demo
- UDP/5001 allow
- UDP/5002 drop

For the final hardware demo, UDP/80, UDP/5001, and UDP/5002 are the important
rules. The TCP rules remain from the original firewall scope and still help
simulation coverage, but they are not the main W5500 UDP socket presentation.

Learning value:
- demonstrates first-match policy
- shows wildcarding with masks/ranges
- keeps rule matching separate from parsing and forwarding

Future improvement:
replace fixed parameters with a small BRAM/register-backed rule table. That
would make rules changeable without recompiling the FPGA image.

## Buffer Modules

### `rtl/buffer/packet_buffer.v`

Status: current support.

This stores one packet and can replay it later. It is used inside
`firewall_forwarder.v`.

Inputs:
- packet byte stream
- SOP/EOP markers
- source-port tag

Control signals:
- `rd_start` starts replay
- `discard` drops the stored packet

Outputs:
- replayed packet stream
- packet length
- packet done/available flags
- overflow flag

Why it matters:
without a packet buffer, the forwarder would have to decide before the first
byte leaves the FPGA. That is not practical once payload signature checks are
included.

### `rtl/buffer/frame_rx_fifo.v`

Status: current support.

This is a packet-aware FIFO between receive-side logic and downstream policy
logic. It preserves:
- data bytes
- SOP/EOP markers
- source-port tag

It absorbs short backpressure moments so the W5500 receive side and firewall
side do not have to be perfectly timed on every cycle.

In the final top-level, it sits between:

```text
w5500_udp_rx_adapter -> frame_rx_fifo -> firewall_forwarder
```

Learning value:
- shows why packet boundaries are more complicated than a plain byte FIFO
- introduces overflow handling
- helps separate adapter timing from policy timing

## Debug and Display Modules

### `rtl/debug/debug_counters.v`

Status: current support.

This is a tiny counter block. It counts pulses for:
- received packets
- allowed packets
- dropped packets

It is used by both `firewall_core.v` and `firewall_forwarder.v`.

Learning value: it is a simple, clean module for understanding reset, pulse
counting, and debug visibility.

### `rtl/debug/seven_seg_hex.v`

Status: current support.

This converts a 4-bit value into active-low seven-segment display signals for
the DE1-SoC HEX displays.

It does not know anything about networking. The top-level file chooses what
values to display; this module only turns a nibble into segments.

### `rtl/debug/uart_tx.v`

Status: current support.

This sends one byte at a time over UART. It implements:
- idle state
- start bit
- 8 data bits
- stop bit
- ready/valid style byte input

At 50 MHz with `CLKS_PER_BIT = 434`, it is set up for about 115200 baud.

### `rtl/debug/firewall_telemetry_uart.v`

Status: current support.

This builds a human-readable ASCII telemetry line from firewall counters and
sends it through `uart_tx`.

The PC2 rule dashboard can read this UART stream and show FPGA-side histograms.
That is useful because PC2 packet capture only proves what reached PC2; UART
helps prove what the FPGA counted internally.

Example fields:
- `RX`
- `AL`
- `DR`
- `U80`
- `U51`
- `D52`
- `SIG`
- `FIL`
- `SIN`

## Common Definitions

### `rtl/common/defs.vh`

Status: current support.

This header defines shared constants:
- `ACTION_DROP`
- `ACTION_ALLOW`
- `PROTO_TCP`
- `PROTO_UDP`
- wildcard helper constants

It is small, but important because the parser/rule modules should agree on the
same protocol and action values.

## What Is Obsolete?

The word "obsolete" is a little too strong for most files, because many older
modules are still useful for tests and explanation. A safer classification is:

| File | Current classification |
| --- | --- |
| `rtl/eth_if/ethernet_controller_adapter.v` | legacy/diagnostic A-side MACRAW receive path |
| `rtl/top/firewall_top.v` | reusable older integration wrapper, not final demo top |
| `rtl/firewall/firewall_core.v` | reusable original inspect-only core, not final forwarding path |
| `rtl/eth_if/w5500_tx_engine.v` | reusable focused TX engine, not the board-level TX adapter |

Files that are definitely current in the final demo:

| File | Why current |
| --- | --- |
| `rtl/top/de1_soc_w5500_top.v` | real board top |
| `rtl/eth_if/w5500_udp_rx_adapter.v` | W5500 A UDP ingress |
| `rtl/buffer/frame_rx_fifo.v` | ingress buffering |
| `rtl/firewall/firewall_forwarder.v` | policy, signatures, forwarding decision |
| `rtl/buffer/packet_buffer.v` | packet replay/drop support |
| `rtl/eth_if/w5500_macraw_tx_adapter.v` | W5500 B egress |
| `rtl/spi/spi_master.v` | W5500 SPI transfers |
| `rtl/debug/*` | board/dashboard visibility |

## Recommended Reading Order

For learning, read the RTL in this order:

1. `rtl/common/defs.vh`
2. `rtl/debug/debug_counters.v`
3. `rtl/parser/eth_ipv4_parser.v`
4. `rtl/rules/rule_engine.v`
5. `rtl/firewall/firewall_core.v`
6. `rtl/buffer/packet_buffer.v`
7. `rtl/firewall/firewall_forwarder.v`
8. `rtl/spi/spi_master.v`
9. `rtl/eth_if/w5500_udp_rx_adapter.v`
10. `rtl/eth_if/w5500_macraw_tx_adapter.v`
11. `rtl/top/de1_soc_w5500_top.v`

That order moves from small pure-logic modules to the full hardware integration.
