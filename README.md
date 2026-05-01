# FPGA Firewall Project

This repository is organized so the team can:
1. build and verify the firewall core before hardware arrives,
2. isolate hardware-risky parts behind a clean adapter interface,
3. track bugs, design decisions, and milestone status clearly.

This project builds a simple FPGA-based Ethernet firewall MVP on `DE1-SoC + W5500`. The short version is:
- packets come in from simulation or from the W5500,
- the parser extracts IPv4/TCP/UDP header fields,
- the rule engine decides allow or drop,
- an RX FIFO can absorb backpressure between the adapter and the firewall core,
- and the firewall core records the result with counters and debug visibility.

If you are new to the repo, start with [project_overview.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/project_overview.md). It explains the goal, architecture, stages, testing flow, deployment path, hardware setup, and which code/files matter at each phase.

## Start here

Recommended reading order for new teammates:
- [docs/project_overview.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/project_overview.md)
- [docs/architecture.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/architecture.md)
- [docs/interfaces.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/interfaces.md)
- [docs/test_plan.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/test_plan.md)
- [docs/hands_on_plan.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/hands_on_plan.md)
- [docs/quartus_learning_guide.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/quartus_learning_guide.md)

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
- `docs/`     : overview, architecture, interfaces, test plan, and bring-up plan
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
- a dedicated RX-side frame FIFO between the adapter and firewall core,
- a W5500-oriented adapter with a MACRAW-mode RX simulation path,
- a DE1-SoC board wrapper for first hardware bring-up,
- dedicated testbenches for source, parser, rules, buffer, SPI, adapter, and firewall core.

The current project phase is:
- simulation-complete for the main MVP pipeline,
- hardware-bring-up-ready for the first DE1-SoC + W5500 receive path,
- not yet in the optional forwarding stage.

## Current verification status

The XSim regression suite currently passes for:
- `fake_eth_source_tb`
- `parser_tb`
- `rule_engine_tb`
- `packet_buffer_tb`
- `frame_rx_fifo_tb`
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

The Quartus flow has also been validated on this machine:
- recreate the project with `powershell -ExecutionPolicy Bypass -File .\scripts\create_quartus_project.ps1`
- compile with `& 'C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe' --flow compile de1_soc_w5500 -c de1_soc_w5500`
- use `build/quartus/de1_soc_w5500.sof` for JTAG/SRAM programming
- review `build/quartus/de1_soc_w5500.pin`, `.fit.rpt`, and `.sta.rpt` as the primary hardware handoff artifacts

## Hardware target

The current hardware plan is frozen around:
- Terasic DE1-SoC
- W5500 over `SPI + RESET + INT`
- one-port RX inspection before any forwarding work

For the full newcomer-friendly explanation, see [project_overview.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/project_overview.md).
See [de1_soc_w5500_hardware.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/de1_soc_w5500_hardware.md) for the board-facing contract.
See [hands_on_plan.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/hands_on_plan.md) for the step-by-step buy, wire, compile, program, and bring-up flow.
See [quartus_learning_guide.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/quartus_learning_guide.md) for a beginner-friendly explanation of the Quartus project files and compile/program flow in this repo.
See [simulation.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/simulation.md) for the validated regression order and simulator commands.

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
