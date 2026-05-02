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
- one-port hardware bring-up has reached live RX inspection on `DE1-SoC + W5500`,
- W5500 SPI register access, MACRAW initialization, RX polling, and PC-generated packet reception have been demonstrated on hardware,
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

Current hardware evidence:
- the DE1-SoC programs successfully over USB-Blaster/JTAG,
- the W5500 responds to the `VERSIONR` register read after reset,
- the adapter reaches RX polling with `init_done` active and `init_error` inactive,
- Wireshark confirmed deterministic Scapy packets on the PC Ethernet interface:
  - `udp_allow`
  - `tcp_drop`
  - `tcp_allow_ssh`
- board LEDs show receive/allow/drop counter activity while traffic is present.

Remaining hardware work:
- correlate each deterministic packet profile with the expected allow/drop counter behavior more cleanly,
- close the new stream-level forwarding and W5500 TX simulations,
- add a shared W5500 B hardware path for transmit,
- add UART telemetry for dashboard-visible FPGA counters,
- run the final two-port file/video chunk demo.

## Hardware target

The current hardware plan is frozen around:
- Terasic DE1-SoC
- W5500 over `SPI + RESET + INT`
- one proven W5500 RX path on `GPIO_0`
- a staged second W5500 path on `GPIO_1[0..5]`
- one-way inline forwarding before bidirectional forwarding

Final demo target:

```text
PC1 sender -> W5500 A -> FPGA rules/forwarder -> W5500 B -> PC2 receiver
```

The planned proof is a chunked file transfer. Allowed chunks use UDP destination port `5001`; blocked decoy/error traffic is intentionally interleaved and should not appear on PC2. PC2 verifies the reconstructed file with SHA-256.

## Two-PC demo setup

This is the handoff checklist for the final inline demo once the FPGA image supports W5500 B transmit.

### Both PCs

Install:
- Git
- Python 3.9 or newer
- Npcap with WinPcap-compatible mode enabled
- Wireshark

Clone and enter the repo:

```powershell
git clone <repo-url>
cd ELE432_ethernet
```

Install Python dependency:

```powershell
py -3.9 -m pip install scapy
```

Find the Ethernet interface name:

```powershell
py -3.9 -c "from scapy.all import get_if_list; print('\n'.join(get_if_list()))"
```

Use the interface name that matches the wired Ethernet adapter. In the examples below it is `"Ethernet"`.

### PC1: sender side

Connect PC1 Ethernet to W5500 A, the FPGA ingress module.

For the simplest continuous rule demo, run this first:

```bash
sudo python3 scripts/rule_demo_sender.py --iface enX --rate 2
```

This sends known-good deterministic rule profiles every cycle: UDP/80 allow, TCP/22 SSH allow, and TCP/23 drop.

For the continuous live demo, run:

```powershell
py -3.9 .\scripts\sine_sender.py --iface "Ethernet"
```

This continuously sends:
- allowed sine-wave packets on UDP destination port `5001`,
- blocked decoy packets on TCP port `23` by default,
- a persistent stream ID/sequence state file so the live demo can continue across sender restarts,
- a small default packet shape (`5` packets/sec, `16` samples/packet, `1 Hz`) that is readable for the live demo.

Put a small test file in the repo folder, for example `demo.mp4` or `demo.bin`, then run:

```powershell
py -3.9 .\scripts\file_sender.py --iface "Ethernet" --file .\demo.mp4
```

What PC1 does:
- splits the file into numbered chunks,
- sends real file chunks as UDP destination port `5001`,
- interleaves blocked decoy/error traffic,
- prints the file SHA-256 and sent counts.

### PC2: receiver side

Connect W5500 B, the FPGA egress module, to PC2 Ethernet.

For the simplest continuous rule demo, start this browser receiver before PC1 starts sending:

```powershell
py -3.9 .\scripts\rule_demo_receiver_dashboard.py --iface "Ethernet" --port 8091
```

Then open:

```text
http://127.0.0.1:8091
```

Expected result: allowed packets increase, expected drops increase, and `Drop leaks` stays `0`.

For the continuous live demo, start the browser receiver before PC1 starts sending:

```powershell
py -3.9 .\scripts\sine_receiver_dashboard.py --iface "Ethernet" --port 8090
```

Then open:

```text
http://127.0.0.1:8090
```

The dashboard shows:
- received sine waveform,
- packet-by-packet decision strip,
- allowed packet count,
- expected drop count,
- missing sequence count,
- packets per second,
- run ID and ignored stale packet count,
- decoy leak count.

The expected result is a moving sine wave, green allowed packet marks, faded red expected-drop marks, and `Leaks = 0`.

Use **Restart dashboard** to clear the PC2 counters, waveform, packet strip, event log, and rate graph without restarting the receiver process.

If the button is not visible, stop and restart `sine_receiver_dashboard.py` once. The dashboard HTML is embedded in the Python process, so an already-running dashboard will keep serving the old page until the process restarts.

Before a clean demo take, stop old sender processes on PC1 and start only one new sender. The sender saves `.sine_sender_state.json` by default, so restarting it continues the same run ID and sequence. Use `--fresh-run` only when you intentionally want a new demo run. The dashboard locks onto the first new-format `FWSINE2` run it sees and ignores legacy or different-run packets, but a single sender gives the cleanest waveform and packet strip. W5500 B TX now uses burst TX-buffer writes in RTL, so higher sender rates are more realistic, but increase `--packets-per-second` gradually while watching PC2 packet gaps and leaks.

For a hard-locked presentation stream, use the same explicit run ID on both PCs:

```powershell
py -3.9 .\scripts\sine_receiver_dashboard.py --iface "Ethernet" --port 8090 --lock-run-id 0x4321
```

```bash
sudo python3 scripts/sine_sender.py --iface enX --run-id 0x4321 --packets-per-second 5 --samples-per-packet 16 --sine-hz 1
```

For the file/video checksum demo, start the receiver before PC1 starts sending:

```powershell
py -3.9 .\scripts\file_receiver.py --iface "Ethernet" --output .\received_demo.mp4
```

What PC2 does:
- listens for forwarded UDP port `5001` chunks,
- reconstructs the file,
- reports missing chunks,
- verifies SHA-256,
- prints `PASS` when the reconstructed file matches PC1's original file.

Optional Wireshark checks on PC2:

```text
udp.port == 5001
```

Blocked traffic should not show up on PC2:

```text
tcp.port == 23
```

```text
frame contains "FW-DECOY-DROP"
```

For the no-UART version of the demo, PC1 sender output, PC2 receiver output, PC2 Wireshark, and the DE1-SoC HEX/LED counters are the proof sources.

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
