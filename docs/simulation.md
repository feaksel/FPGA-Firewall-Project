# Simulation Notes

## Preferred compile order
1. `fake_eth_source_tb`
2. `parser_tb`
3. `rule_engine_tb`
4. `packet_buffer_tb`
5. `firewall_core_tb`
6. `spi_master_tb`
7. `eth_controller_adapter_tb`
8. `adapter_firewall_integration_tb`

## Tooling

The repo includes `scripts/run_iverilog.ps1` for Windows PowerShell environments.
The repo also includes `scripts/run_xsim.ps1` and `scripts/run_questa.ps1` for machines with Vivado or Questa installed.
For the current project flow, `scripts/run_xsim_suite.ps1` runs the full pre-hardware bench set in order.

Expected include path:
- `rtl/common`
- `tb/common`

## Mixed-language verification

The preferred verification style is:
- Verilog or conservative synthesizable SystemVerilog in `rtl/`
- SystemVerilog in `tb/` for packages, shared tasks, assertions, and cleaner stimulus

This keeps the FPGA path simple while making the benches easier to extend.

Recommended order on this machine:
- use `run_xsim.ps1` first because Vivado 2025.1 is installed,
- use `run_questa.ps1` when you want an alternate simulator check,
- keep `run_iverilog.ps1` available for lightweight environments that already have Icarus installed.

## Packet vectors

Current packet vectors:
- `tb/packets/udp_allow.mem`
- `tb/packets/tcp_drop.mem`
- `tb/packets/udp_subnet.mem`
- `tb/packets/tcp_allow_ssh.mem`

Each file is a byte-per-line hex memory file intended for `$readmemh`.

## What to look for

- parser extracts protocol, IPs, and ports at the expected byte positions
- rule engine honors first-match priority
- packet buffer preserves byte order and SOP/EOP positions
- firewall core increments counters exactly once per packet
- SPI master returns the expected response byte from the testbench slave model
- the W5500 adapter reaches MACRAW-ready state and streams a frame into the internal firewall interface
