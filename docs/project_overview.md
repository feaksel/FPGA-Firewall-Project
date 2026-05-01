# Project Overview and Working Guide

## Who this is for

This document is for teammates who are not deep FPGA specialists but will be working on this project and need to understand:
- what we are building,
- why it is organized this way,
- what stage the project is in,
- how we test progress,
- how we move from simulation to real hardware,
- and which files, tools, and hardware matter most.

## The project in one sentence

This project builds a simple FPGA-based Ethernet firewall that reads incoming packets, extracts key header fields, checks them against firewall rules, and decides whether each packet should be allowed or dropped.

## What we are actually trying to achieve

The main goal is not to build a full commercial firewall in one step.

The main goal is to build a clean, testable MVP that can:
- receive Ethernet frames,
- inspect IPv4 TCP/UDP packet headers,
- apply a small ordered rule set,
- count allowed and dropped packets,
- and prove that the exact same firewall logic works first in simulation and then on real hardware.

This is important because hardware projects fail easily when too many things are attempted at once. The repo is intentionally structured so that the core firewall can be developed and verified before the board-level Ethernet path is fully proven.

## What the system does today

At the current stage, the design is a one-port packet receive and inspection pipeline that has now been exercised on the physical DE1-SoC + W5500 hardware.

In plain language, the flow is:

1. A packet arrives from either a simulation source or a real Ethernet controller.
2. The packet can pass through a small RX FIFO so the receive side can tolerate backpressure cleanly.
3. The packet bytes are presented on a shared internal frame interface.
4. The parser reads the Ethernet and IPv4 headers.
5. The parser extracts fields such as protocol, source IP, destination IP, source port, and destination port.
6. The rule engine compares those fields to the configured firewall rules.
7. The firewall core records whether the packet was allowed or dropped.
8. Debug counters and LEDs show what happened.

Right now, the system is focused on receive-side inspection. It is not yet a full inline two-port forwarding firewall. That later extension is planned only after the receive path and allow/drop validation are repeatable on hardware.

## Why the project is organized in stages

The project follows a risk-reduction strategy.

Instead of starting with "real Ethernet cable in, real forwarding out", we first separate the problem into smaller parts:
- simulate packet input,
- verify parsing,
- verify rule decisions,
- verify integration,
- verify Ethernet controller communication,
- then connect that to the physical board,
- and only after that consider forwarding.

The most important design idea is this:

The firewall core should not care where a packet came from.

That means the core logic should work the same whether the packet is coming from:
- a fake simulation packet source,
- a packet memory file,
- or the real W5500 Ethernet controller.

That separation is the main reason the project is understandable and testable.

## Main hardware target

The current hardware path is frozen around:
- FPGA board: `Terasic DE1-SoC`
- Ethernet controller/module: `W5500` over `SPI + RESET + INT`
- Clock source: `CLOCK_50`
- First hardware goal: one-port receive inspection

The current recommended module style is a `WIZ850io`-type W5500 module because it already includes the RJ45 connector and is a good fit for the SPI-based approach in this project.

## Main technologies used

This project uses a mix of hardware-description code, testbench code, and helper scripts.

### RTL and synthesizeable logic

Used for the real FPGA design:
- Verilog in `rtl/`
- conservative coding style so synthesis stays predictable

Important RTL modules:
- [rtl/top/de1_soc_w5500_top.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/top/de1_soc_w5500_top.v)
- [rtl/top/firewall_top.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/top/firewall_top.v)
- [rtl/eth_if/ethernet_controller_adapter.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/eth_if/ethernet_controller_adapter.v)
- [rtl/firewall/firewall_core.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/firewall/firewall_core.v)
- [rtl/parser/eth_ipv4_parser.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/parser/eth_ipv4_parser.v)
- [rtl/rules/rule_engine.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/rules/rule_engine.v)
- [rtl/spi/spi_master.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/spi/spi_master.v)
- [rtl/debug/debug_counters.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/debug/debug_counters.v)

### Verification code

Used to prove the logic works before hardware:
- SystemVerilog testbenches in `tb/`
- packet vectors in `tb/packets/`
- shared verification helpers in `tb/common/`
- a W5500 simulation model in `tb/models/`

Important testbenches:
- `fake_eth_source_tb`
- `parser_tb`
- `rule_engine_tb`
- `packet_buffer_tb`
- `firewall_core_tb`
- `spi_master_tb`
- `eth_controller_adapter_tb`
- `adapter_firewall_integration_tb`

### Build and helper scripts

Used to run tests and hardware build steps:
- PowerShell scripts in `scripts/`
- Python for deterministic packet generation

Most used scripts:
- [scripts/run_xsim_suite.ps1](/c:/Users/furka/Projects/ELE432_ethernet/scripts/run_xsim_suite.ps1)
- [scripts/run_xsim.ps1](/c:/Users/furka/Projects/ELE432_ethernet/scripts/run_xsim.ps1)
- [scripts/traffic_dashboard.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/traffic_dashboard.py)
- [scripts/run_questa.ps1](/c:/Users/furka/Projects/ELE432_ethernet/scripts/run_questa.ps1)
- [scripts/create_quartus_project.ps1](/c:/Users/furka/Projects/ELE432_ethernet/scripts/create_quartus_project.ps1)
- [scripts/send_test_packets.py](/c:/Users/furka/Projects/ELE432_ethernet/scripts/send_test_packets.py)

### FPGA and debug tools

Used outside the repo:
- `Vivado/XSim` for the preferred simulation flow on this machine
- `Questa` as an alternate simulator
- `Quartus` for FPGA synthesis, fitting, and programming
- `Wireshark` for observing PC-side Ethernet traffic
- `Scapy` for sending known packet patterns from the PC

## The main internal architecture

The project has a very simple mental model.

### 1. Packet source or Ethernet adapter

This is where packet bytes come from.

In simulation, the bytes come from fake sources or memory-backed test vectors.
On hardware, the bytes come from the W5500 through the adapter.

### 2. Internal frame interface

This is the shared "packet byte stream" boundary in the project.

Important signals are:
- `frame_valid`
- `frame_data[7:0]`
- `frame_sop`
- `frame_eop`
- `frame_ready`
- `frame_src_port`

This interface is the bridge that allows simulation and hardware paths to feed the same firewall logic.

### 2a. RX FIFO

The current integrated receive path includes a small single-clock RX FIFO between the adapter and the firewall core.

Its purpose is to:
- absorb temporary backpressure,
- keep the adapter/firewall boundary stable,
- and let the team test a more realistic integration path before hardware arrives.

### 3. Parser

The parser reads packet bytes and extracts:
- EtherType
- IPv4 protocol
- source IP
- destination IP
- source port
- destination port

The current parser scope is intentionally limited to:
- Ethernet II
- IPv4
- TCP and UDP
- no IPv4 options in the MVP

Unsupported or malformed packets produce a parse error and are effectively dropped.

### 4. Rule engine

The rule engine compares parsed packet fields against firewall rules.

Current behavior:
- four ordered rules
- first match wins
- default action is drop if no rule matches

This is simple on purpose. The rule table is still parameter-based for the MVP so the project can get to a working demo quickly. A more dynamic or BRAM-backed rule table can come later.

### 5. Firewall core

The firewall core ties parser and rule engine together and exposes counters such as:
- total received packets
- allowed packets
- dropped packets

This module is the central "decision layer" of the project.

### 6. W5500 adapter

The adapter is the hardware-facing side.

Its job is to:
- control reset for the W5500,
- communicate with the W5500 over SPI,
- initialize the chip for `MACRAW` receive mode,
- poll for received packets,
- read packet bytes from the W5500 receive buffer,
- and stream those bytes into the internal frame interface.

This is the bridge between real Ethernet hardware and the reusable firewall core.

## Development stages

The project is meant to progress in clear stages, and each stage has a "do not move on until this works" mindset.

### Stage 1: Packet source simulation

Goal:
- prove that packet bytes can be driven through the internal frame interface in a controlled way

Main files:
- `tb/tests/fake_eth_source_tb.v`
- `tb/packets/*.mem`

What gets tested:
- byte ordering
- packet length
- correct start-of-packet and end-of-packet handling

Move forward when:
- known packet vectors stream correctly into the design

### Stage 2: Parser verification

Goal:
- prove we can correctly extract the needed fields from Ethernet/IPv4/TCP/UDP packets

Main files:
- [rtl/parser/eth_ipv4_parser.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/parser/eth_ipv4_parser.v)
- `tb/tests/parser_tb.sv`

What gets tested:
- EtherType decoding
- protocol extraction
- source and destination IP extraction
- source and destination port extraction
- parse error handling on unsupported or short frames

Move forward when:
- parser testbench passes for the supported packet types

### Stage 3: Rule engine verification

Goal:
- prove the firewall decision logic behaves correctly

Main files:
- [rtl/rules/rule_engine.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/rules/rule_engine.v)
- `tb/tests/rule_engine_tb.sv`

What gets tested:
- exact-match behavior
- subnet-mask behavior
- port-range behavior
- first-match priority
- default drop behavior

Move forward when:
- rule decisions match the expected rule set for all test cases

### Stage 4: Firewall core integration

Goal:
- prove the parser and rule engine work correctly as one pipeline

Main files:
- [rtl/firewall/firewall_core.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/firewall/firewall_core.v)
- `tb/tests/firewall_core_tb.sv`

What gets tested:
- packet counting
- allow/drop decision pulses
- integration behavior with mixed packet cases

Move forward when:
- the integrated firewall core testbench passes

### Stage 5: SPI master verification

Goal:
- prove that the project can reliably talk SPI to the Ethernet controller

Main files:
- [rtl/spi/spi_master.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/spi/spi_master.v)
- `tb/tests/spi_master_tb.v`

What gets tested:
- clock generation
- transfer sequencing
- response-byte handling
- multi-byte transfer behavior with held chip-select

Move forward when:
- SPI transactions behave correctly in simulation

### Stage 6: Ethernet controller adapter verification

Goal:
- prove the W5500-oriented receive path can be simulated and can feed the firewall

Main files:
- [rtl/eth_if/ethernet_controller_adapter.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/eth_if/ethernet_controller_adapter.v)
- `tb/models/w5500_macraw_model.sv`
- `tb/tests/eth_controller_adapter_tb.sv`
- `tb/tests/adapter_firewall_integration_tb.sv`

What gets tested:
- controller reset and initialization sequence
- register read/write behavior
- MACRAW receive flow
- streaming a received frame into the firewall core

Move forward when:
- both adapter-level and adapter-to-firewall integration benches pass

### Stage 7: One-port hardware bring-up

Goal:
- prove the simulated design also works on the real board and real Ethernet module

Hardware used:
- `DE1-SoC`
- `W5500` module
- USB-Blaster connection
- Ethernet cable
- PC NIC or USB Ethernet adapter

What gets tested first:
- power and voltage correctness
- reset behavior
- SPI pin activity
- known register reads
- successful adapter initialization

What gets tested next:
- packet arrival at the W5500
- packet length reads
- streaming packet bytes into the firewall
- allow/drop counter behavior

Move forward when:
- the board receives real traffic and the firewall counters respond as expected

Current status as of 2026-05-01:
- W5500 reset, SPI register access, and MACRAW initialization work on real hardware.
- The adapter reaches RX polling on the DE1-SoC with `init_done` active.
- Deterministic Scapy packets sent by the PC were captured in Wireshark and observed by the FPGA receive path.
- Single-bit LED counters show activity, but a clearer debug method is still needed to prove every packet profile maps to the expected allow/drop counter result.

### Stage 8: Optional forwarding work

Goal:
- extend the project from receive-side inspection into a more complete forwarding design

This stage is intentionally delayed until the receive path is stable and allow/drop counter correlation is documented.

Likely work here:
- second-port handling
- transmit path buffering
- forwarding only allowed packets

This is not the MVP and should not be allowed to destabilize the current bring-up path.

## How testing works in practice

The project uses a gate-based workflow. Each layer is tested before adding the next layer.

### Simulation-first testing

This is the default development flow.

The preferred regression command is:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_xsim_suite.ps1
```

That suite is the main confidence check before hardware work.

You can also run one testbench at a time:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_xsim.ps1 parser_tb
```

Why simulation matters so much:
- it is faster than hardware debugging,
- it isolates logic bugs from wiring bugs,
- it gives deterministic repeatable tests,
- and it prevents the team from blaming hardware for problems caused by RTL mistakes.

### Hardware testing

Hardware testing starts only after the simulation baseline is healthy.

The basic bring-up sequence is:

1. Compile the FPGA image.
2. Program the DE1-SoC over JTAG.
3. Start the adapter init sequence using the board controls.
4. Watch LED debug outputs.
5. Verify SPI activity.
6. Send Ethernet traffic from the PC.
7. Check whether `rx_packet_seen`, `rx_count`, `allow_count`, and `drop_count` react correctly.

### Deterministic packet testing from the PC

Once basic packet reception is stable, the project uses a Python + Scapy helper to send known packet types that match the simulation intent.

Examples:

```powershell
python .\scripts\send_test_packets.py --iface "Ethernet" --packet udp_allow
python .\scripts\send_test_packets.py --iface "Ethernet" --packet tcp_drop
python .\scripts\send_test_packets.py --iface "Ethernet" --packet tcp_allow_ssh
```

These are useful because they let us compare:
- what the PC sent,
- what Wireshark captured,
- what the FPGA parsed,
- and whether the firewall counters behaved as expected.

## How we decide when to move to the next stage

The project should move to the next stage only when the current stage has clear evidence behind it.

In practical terms, this means:
- passing the relevant testbench or regression suite,
- confirming the expected debug signals or counters,
- and documenting any blocking issue before continuing.

We should not pile on new features if the current layer is unstable.

Examples:
- Do not debug live Ethernet traffic if SPI register reads are still inconsistent.
- Do not add forwarding logic if receive-side packet parsing is not proven.
- Do not expand the rule system if the base parser and counters are still unreliable.

## What deployment means in this project

In software projects, deployment usually means sending code to a server.
In this FPGA project, deployment means turning RTL into a board-programming file and loading it into the FPGA.

### The deployment flow

1. Create or refresh the Quartus project.
2. Compile the design in Quartus.
3. Generate the `.sof` programming file.
4. Program the DE1-SoC over JTAG using USB-Blaster.
5. Use switches, keys, LEDs, and Ethernet traffic to validate behavior on the board.

### Main project build files

Important Quartus files:
- [quartus/de1_soc_w5500.qpf](/c:/Users/furka/Projects/ELE432_ethernet/quartus/de1_soc_w5500.qpf)
- [quartus/de1_soc_w5500.qsf](/c:/Users/furka/Projects/ELE432_ethernet/quartus/de1_soc_w5500.qsf)
- [quartus/de1_soc_w5500.sdc](/c:/Users/furka/Projects/ELE432_ethernet/quartus/de1_soc_w5500.sdc)
- [quartus/create_de1_soc_w5500_project.tcl](/c:/Users/furka/Projects/ELE432_ethernet/quartus/create_de1_soc_w5500_project.tcl)

Main helper command:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\create_quartus_project.ps1
```

Compile command:

```powershell
& 'C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe' --flow compile de1_soc_w5500 -c de1_soc_w5500
```

Expected build outputs go under:
- `build/quartus/`

The most important deployment file is:
- `build/quartus/de1_soc_w5500.sof`

That file is the board image loaded into the FPGA for testing.

## What hardware connections and board controls matter

The board-facing top-level wrapper is:
- [rtl/top/de1_soc_w5500_top.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/top/de1_soc_w5500_top.v)

Important board controls:
- `KEY[0]` is used as reset release
- `SW[0]` starts the initialization sequence

Current W5500 wiring contract:
- `GPIO_0[0]` = `SCLK`
- `GPIO_0[1]` = `MOSI`
- `GPIO_0[2]` = `CS_n`
- `GPIO_0[3]` = `RESET_n`
- `GPIO_0[4]` = `MISO`
- `GPIO_0[5]` = `INT_n`

Current LED debug contract:
- `LEDR[0]` = `init_done`
- `LEDR[1]` = `init_error`
- `LEDR[2]` = `rx_packet_seen`
- `LEDR[6:3]` = adapter `debug_state`
- `LEDR[7]` = `rx_count[0]`
- `LEDR[8]` = `allow_count[0]`
- `LEDR[9]` = `drop_count[0]`

These LEDs are extremely important during early bring-up because they tell us whether the design is alive before any advanced debug tooling is available.

## What kinds of code teammates will likely work on

Different people can contribute in different layers.

### RTL / FPGA logic work

Examples:
- parser improvements
- firewall rule changes
- adapter state-machine fixes
- counter/debug visibility improvements

Main folders:
- `rtl/`
- `quartus/`

### Verification work

Examples:
- adding test cases
- extending packet vectors
- improving W5500 simulation coverage
- regression cleanup

Main folders:
- `tb/`
- `tb/packets/`
- `docs/test_plan.md`

### Bring-up and bench work

Examples:
- wiring verification
- Quartus compile/program flow
- observing LED behavior
- logic analyzer captures
- Wireshark comparisons

Main docs:
- [docs/de1_soc_w5500_hardware.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/de1_soc_w5500_hardware.md)
- [docs/hardware_bringup.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/hardware_bringup.md)
- [docs/hands_on_plan.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/hands_on_plan.md)
- [docs/pc_traffic.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/pc_traffic.md)

### Tooling and support scripts

Examples:
- simulation runner improvements
- deterministic traffic generators
- automation for build and test steps

Main folders:
- `scripts/`

## What is already stable vs what is still in progress

Broadly speaking, the pre-hardware simulation path is the most mature part of the project.

Already established:
- parser path
- rule engine path
- firewall integration
- RX FIFO integration path
- SPI master behavior
- W5500 adapter simulation path
- DE1-SoC top-level wrapper
- Quartus project layer

Already established on hardware:
- real-board wiring validation for the first GPIO_0_D0 through GPIO_0_D5 W5500 connection,
- real W5500 `VERSIONR` register access,
- W5500 MACRAW initialization,
- real packet receive activity from PC traffic,
- Wireshark confirmation of deterministic Scapy packets.

Still considered active bring-up work:
- clean allow/drop counter correlation against deterministic PC traffic,
- better debug visibility than single-bit counter LEDs,
- later forwarding work.

## The most important project habits

To keep this project understandable and healthy, the team should keep following these habits:

1. Do not skip stages just because the next step seems more interesting.
2. Keep simulation passing before touching hardware.
3. Document decisions and bugs instead of carrying tribal knowledge in chat.
4. Do not silently change shared interfaces.
5. Use deterministic packets when debugging packet behavior.
6. Treat board bring-up and RTL debugging as separate problems whenever possible.

## If you only remember five things

1. This is an FPGA firewall MVP, not a full network appliance yet.
2. The core idea is to reuse the same firewall logic in simulation and on hardware.
3. The project flows from packet source -> parser -> rule engine -> firewall core -> hardware adapter.
4. We only move forward when the current stage is proven by tests or bring-up evidence.
5. Real success for the current phase is now narrower: receive real packets is working; the next proof point is clean, repeatable allow/drop correlation for each deterministic packet type.

## Recommended reading order for a new teammate

If you are new to the project, the easiest reading order is:

1. [README.md](/c:/Users/furka/Projects/ELE432_ethernet/README.md)
2. [docs/project_overview.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/project_overview.md)
3. [docs/architecture.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/architecture.md)
4. [docs/interfaces.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/interfaces.md)
5. [docs/test_plan.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/test_plan.md)
6. [docs/hands_on_plan.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/hands_on_plan.md)
7. [docs/quartus_learning_guide.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/quartus_learning_guide.md)

After that, move into the RTL and testbench files for the area you will be working on.
