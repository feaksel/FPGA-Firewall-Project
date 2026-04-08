# Simulation Notes

## Preferred compile order
1. `fake_eth_source_tb`
2. `parser_tb`
3. `rule_engine_tb`
4. `packet_buffer_tb`
5. `firewall_core_tb`
6. `spi_master_tb`
7. `eth_controller_adapter_tb`

## Tooling

The repo includes `scripts/run_iverilog.ps1` for Windows PowerShell environments.

Expected include path:
- `rtl/common`

## Packet vectors

Current starter vectors:
- `tb/packets/udp_allow.mem`
- `tb/packets/tcp_drop.mem`
- `tb/packets/udp_subnet.mem`

Each file is a byte-per-line hex memory file intended for `$readmemh`.

## What to look for

- parser extracts protocol, IPs, and ports at the expected byte positions
- rule engine honors first-match priority
- packet buffer preserves byte order and SOP/EOP positions
- firewall core increments counters exactly once per packet
- SPI master returns the expected response byte from the testbench slave model
