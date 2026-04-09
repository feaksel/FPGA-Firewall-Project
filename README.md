# FPGA Firewall Project

This repository is organized so the team can:
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

## Repository status

The current implementation includes:
- packet vectors for UDP allow and TCP drop smoke tests,
- a parser that handles Ethernet II + IPv4 + TCP/UDP without IPv4 options,
- a four-rule parameterized rule engine with first-match priority,
- a single-packet buffer that stores frame bytes and can replay them,
- a W5500-oriented adapter with a MACRAW-mode RX simulation path,
- a DE1-SoC board wrapper for first hardware bring-up,
- dedicated testbenches for source, parser, rules, buffer, SPI, adapter, and firewall core.

## Current verification status

The XSim regression suite currently passes for:
- `fake_eth_source_tb`
- `parser_tb`
- `rule_engine_tb`
- `packet_buffer_tb`
- `firewall_core_tb`
- `spi_master_tb`
- `eth_controller_adapter_tb`
- `adapter_firewall_integration_tb`

Run the full suite with:
- `powershell -ExecutionPolicy Bypass -File .\scripts\run_xsim_suite.ps1`

Run a single testbench with:
- `powershell -ExecutionPolicy Bypass -File .\scripts\run_xsim.ps1 <testbench_name>`

Simulation artifacts are written to designated build folders instead of the repo root:
- `build/xsim/<testbench>/`
- `build/iverilog/<testbench>/`
- `build/questa/<testbench>/`

## Hardware target

The current hardware plan is frozen around:
- Intel DE1-SoC
- W5500 over `SPI + RESET + INT`
- one-port RX inspection before any forwarding work

See [de1_soc_w5500_hardware.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/de1_soc_w5500_hardware.md) for the board-facing contract.
See [hands_on_plan.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/hands_on_plan.md) for the step-by-step buy, wire, compile, program, and bring-up flow.

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
