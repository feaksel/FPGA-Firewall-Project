# Interfaces

## Global assumptions
- Ethernet II framing
- IPv4 inspection only for MVP
- No IPv4 options in MVP
- TCP/UDP header basic field extraction
- Default policy = DROP
- First matching rule wins

## Internal frame stream interface

This interface is used between:
- fake packet source
- future Ethernet RX adapter
- packet buffer
- firewall core

Signals:
- `frame_valid` : current byte valid
- `frame_data[7:0]` : current byte
- `frame_sop` : start of packet
- `frame_eop` : end of packet
- `frame_ready` : sink ready for the current byte
- `frame_src_port[0:0]` : source port id for future dual-port extension

Current baseline:
- the firewall core is always ready,
- the packet buffer can apply backpressure when full,
- the adapter shell keeps the same interface even before real RX logic exists.

## Parser output interface

- `hdr_valid`
- `is_ipv4`
- `protocol[7:0]`
- `src_ip[31:0]`
- `dst_ip[31:0]`
- `src_port[15:0]`
- `dst_port[15:0]`
- `parse_error`

Notes:
- `hdr_valid` pulses when the minimum supported header fields are available.
- `parse_error` pulses on short frames or unsupported header forms.

## Rule format

Per rule:
- valid
- src_ip
- src_mask
- dst_ip
- dst_mask
- protocol
- src_port_min
- src_port_max
- dst_port_min
- dst_port_max
- action

Conventions:
- `protocol == 8'h00` means wildcard
- all-zero masks mean wildcard IP match
- first matching rule wins

## Rule engine outputs
- `decision_valid`
- `action_allow`
- `matched_rule_id`

## Counter visibility

The top-level integration must expose:
- `rx_count`
- `allow_count`
- `drop_count`
- `adapter_debug_state`
- `init_done`
- `init_error`
- `rx_packet_seen`

These counters are intended for debug and bring-up before optional forwarding is added.

## Board-facing hardware signals

For the DE1-SoC + W5500 path, the external interface must include:
- `w5500_reset_n`
- `w5500_int_n`
- `spi_sclk`
- `spi_mosi`
- `spi_miso`
- `spi_cs_n`
