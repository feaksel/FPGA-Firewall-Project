# FPGA Firewall Project Bootstrap

This repository is structured so the team can:
1. build and verify the firewall core before hardware arrives,
2. isolate hardware-risky parts behind a clean adapter interface,
3. track bugs, design decisions, and milestone status clearly.

## Core philosophy

Do not start with full dual-port inline forwarding.

Build in this order:
1. simulated packet source
2. parser
3. rule engine
4. firewall core integration
5. one Ethernet controller hardware bring-up
6. optional second-port forwarding

## Main directories

- `rtl/`      : synthesizable Verilog modules
- `tb/`       : simulation models and testbenches
- `docs/`     : architecture, interfaces, test plan, bring-up plan
- `scripts/`  : helper scripts
- `BUGS.md`   : active and resolved bugs
- `DECISIONS.md` : architectural decisions and rationale
- `TODO.md`   : current tasks
- `CHANGELOG.md` : meaningful changes

## Required working order

### Before hardware arrives
- parser testbench passes
- rule engine testbench passes
- firewall core testbench passes
- packet buffer testbench passes
- fake packet source drives known packet vectors

### When hardware arrives
- SPI master verified
- controller register read/write verified
- one-port packet receive verified
- real bytes mapped into internal frame interface
- firewall core reused without architecture changes

## Simulation baseline in this repo

The starter implementation already includes:
- packet vectors for UDP allow and TCP drop smoke tests,
- a parser that handles Ethernet II + IPv4 + TCP/UDP without IPv4 options,
- a four-rule parameterized rule engine with first-match priority,
- a single-packet buffer that stores frame bytes and can replay them,
- a W5500-oriented adapter with a MACRAW-mode RX simulation path,
- a DE1-SoC board wrapper for first hardware bring-up,
- dedicated testbenches for source, parser, rules, buffer, SPI, adapter, and firewall core.

## Hardware target

The current hardware plan is frozen around:
- Intel DE1-SoC
- W5500 over `SPI + RESET + INT`
- one-port RX inspection before any forwarding work

See [de1_soc_w5500_hardware.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/de1_soc_w5500_hardware.md) for the board-facing contract.

## Language policy

Use a mixed-language approach:
- synthesizable RTL should stay conservative and Vivado-friendly,
- SystemVerilog is encouraged for testbenches, packages, assertions, and reusable verification helpers,
- any synthesizable SystemVerilog should stay within a simple subset that maps cleanly to the FPGA flow.

## Rules for contributors

Every significant change must update:
- `CHANGELOG.md`
- `DECISIONS.md` if architecture changed
- `BUGS.md` if a bug was found or fixed
- `TODO.md` milestone status

Do not silently change interfaces.
Do not add complexity before the previous milestone passes.
